from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import torch
import yaml

from samstone_rl.batch_engine import BatchSamStoneEnv
from samstone_rl.envs.samstone_env import RewardScheme, SamStoneEnv
from samstone_rl.fast_engine import FastSimulator, StoneCatalog
from samstone_rl.models import ActorCritic, TacticalActorCritic
from samstone_rl.opponents import RandomOpponent
from samstone_rl.tactics import TacticalActionEncoder
from samstone_rl.training.ppo_cleanrl import PPOTrainer

DECK = ["devoracle_n3", "griffe_a_jetons_n3", "sou_ricanant_n3", "croupier_manchot_n2",
        "jumeau_de_cuivre_n2", "valet_a_lenvers_n2", "avortons_des_caves_n2", "le_voyeur_n1"]


def _config() -> dict:
    return {"human_god": "veskar", "ai_god": "veskar",
            "human_deck": DECK, "ai_deck": DECK,
            "first_player": 1, "blocked": [[0, 0]]}


def test_tactical_scores_are_deterministic_and_do_not_mutate_match():
    simulator = FastSimulator(StoneCatalog())
    simulator.reset({**_config(), "seed": 1701})
    before = json.dumps(simulator.serialize_for_player(1), sort_keys=True)
    game_rng = simulator.state.rng.getstate()
    opponent_rng = simulator.opponent_rng.getstate()
    first = simulator.tactical_action_scores(1)
    second = simulator.tactical_action_scores(1)
    assert first == second
    assert first
    assert json.dumps(simulator.serialize_for_player(1), sort_keys=True) == before
    assert simulator.state.rng.getstate() == game_rng
    assert simulator.opponent_rng.getstate() == opponent_rng


def test_action_encoder_keeps_illegal_rows_zero():
    encoder = TacticalActionEncoder()
    observation = np.linspace(-1, 1, encoder.OBSERVATION_SIZE, dtype=np.float32)
    mask = np.zeros(encoder.ACTION_COUNT, dtype=np.bool_)
    mask[[17, 62]] = True
    values = encoder.encode(observation, mask, {
        17: (2.0, -1.0, 3.0, 1.0, 5.0),
        62: (0.0, 0.0, 0.0, 0.0, 1.0),
    })
    assert values.shape == (128, 79)
    assert np.count_nonzero(values[~mask]) == 0
    assert values[17, -5:].tolist() == [0.5, -0.25, 0.75, 1.0, 0.3125]


def test_tactical_model_preserves_legacy_policy_on_import():
    torch.manual_seed(77)
    legacy = ActorCritic(929, 128, 32)
    tactical = TacticalActorCritic(929, 128, 79, 32, 16)
    transferred = tactical.import_legacy_state(legacy.state_dict())
    assert "legacy_actor.weight" in transferred
    observations = torch.randn(3, 929)
    masks = torch.rand(3, 128) > 0.3
    features = torch.randn(3, 128, 79)
    legacy_distribution, legacy_value = legacy.distribution_and_value(observations, masks)
    tactical_distribution, tactical_value = tactical.distribution_and_value(
        observations, masks, features)
    assert torch.allclose(legacy_distribution.logits, tactical_distribution.logits)
    assert torch.allclose(legacy_value, tactical_value)


def test_batch_and_scalar_tactical_features_match():
    reward = RewardScheme()
    scalar = SamStoneEnv(
        backend="python", opponent=RandomOpponent(), agent_player=1,
        reward_scheme=reward, tactical_features=True)
    batch = BatchSamStoneEnv(1, reward, tactical_features=True)
    options = {"config": _config()}
    try:
        scalar_obs, scalar_info = scalar.reset(seed=902, options=options)
        batch_obs, batch_info = batch.reset_one(
            0, seed=902, opponent=RandomOpponent(), agent_player=1,
            options=options)
        assert np.array_equal(scalar_obs, batch_obs)
        assert np.array_equal(scalar_info["action_mask"], batch_info["action_mask"])
        assert np.array_equal(
            scalar_info["action_features"], batch_info["action_features"])
    finally:
        scalar.close()
        batch.close()


def test_tactical_trial_config_builds_isolated_trainer(tmp_path: Path):
    config = Path(__file__).resolve().parents[1] / "configs" / "ppo_phase4_tactical.yaml"
    trainer = PPOTrainer(config, output_override=tmp_path / "trial")
    try:
        assert isinstance(trainer.model, TacticalActorCritic)
        assert trainer.tactical_features_enabled
        assert trainer.batch_env is not None
        assert trainer.evaluation_backend == "godot"
    finally:
        trainer._close_training_envs()
        trainer.tracker.close()


def test_official_phase_four_config_keeps_basics_before_tactical_stages(tmp_path: Path):
    config = Path(__file__).resolve().parents[1] / "configs" / "ppo_phase4_tactical.yaml"
    trainer = PPOTrainer(config, output_override=tmp_path / "phase4")
    try:
        assert isinstance(trainer.model, TacticalActorCritic)
        assert trainer.evaluation_backend == "godot"
        assert [stage.name for stage in trainer.curriculum.stages] == [
            "precision_0", "precision_025", "precision_050", "precision_100",
            "precision_100_anticipation_25", "precision_100_anticipation_50",
            "precision_100_anticipation_75", "precision_100_anticipation",
        ]
        assert trainer.curriculum.promotion_confirmations == 2
        assert trainer.config["curriculum"]["bootstrap_evaluation"]["enabled"]
    finally:
        trainer._close_training_envs()
        trainer.tracker.close()


def test_bootstrap_evaluation_promotes_solved_stages_before_training(
        tmp_path: Path, monkeypatch):
    source = Path(__file__).resolve().parents[1] / "configs" / "ppo_phase4_tactical.yaml"
    config = yaml.safe_load(source.read_text(encoding="utf-8"))
    config["output_dir"] = str(tmp_path / "run")
    config["monitoring"]["tensorboard"] = False
    config["curriculum"]["god_sampling"]["enabled"] = False
    config["curriculum"]["terrain_sampling"]["enabled"] = False
    path = tmp_path / "bootstrap.yaml"
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    trainer = PPOTrainer(path)
    observed_stages: list[str] = []
    observed_offsets: list[int] = []
    outcomes = [(500, 0), (500, 0), (250, 0)]

    def evaluate(seed_offset: int = 0) -> dict:
        wins, draws = outcomes.pop(0)
        games = 500
        losses = games - wins - draws
        observed_stages.append(trainer.curriculum.current.name)
        observed_offsets.append(seed_offset)
        return {
            "wins": wins, "draws": draws, "losses": losses, "games": games,
            "win_rate": wins / games, "wilson_lower": 0.90 if wins == games else 0.40,
            "loss_rate": losses / games, "non_loss_rate": (wins + draws) / games,
            "non_loss_wilson_lower": 0.90 if wins == games else 0.40,
            "mean_margin": 1.0, "mean_turns": 10.0, "anchors": {},
            "by_god": {}, "by_blocked_count": {},
        }

    monkeypatch.setattr(trainer, "evaluate", evaluate)
    try:
        result = trainer._run_bootstrap_evaluation()
        assert result is not None
        assert observed_stages == ["precision_0", "precision_0", "precision_025"]
        assert observed_offsets == [100000, 200000, 300000]
        assert trainer.curriculum.current.name == "precision_025"
        assert trainer.curriculum.bootstrap_evaluation_completed
        checkpoint = torch.load(tmp_path / "run" / "latest.pt", weights_only=False)
        assert checkpoint["curriculum"]["stage_index"] == 1
        assert checkpoint["curriculum"]["bootstrap_evaluation_completed"]
    finally:
        trainer._close_training_envs()
        trainer.tracker.close()


def test_adaptive_terrain_is_drawn_directly_without_rejected_resets(tmp_path: Path,
                                                                     monkeypatch):
    config = Path(__file__).resolve().parents[1] / "configs" / "ppo_phase4_tactical.yaml"
    trainer = PPOTrainer(config, output_override=tmp_path / "trial")
    attempts = [0]
    try:
        monkeypatch.setattr(trainer.curriculum, "sample_blocked_count", lambda _rng: 2)
        observations, infos = trainer._reset_training_episodes(
            [0, 1], initial=True, terrain_attempts=attempts)
        assert len(observations) == len(infos) == 2
        assert attempts == [0]
        assert all(len(info["blocked"]) == 2 for info in infos)
        first = trainer._sample_training_blocked(2)
        second = trainer._sample_training_blocked(2)
        assert len(first) == len(second) == 2
        assert len({tuple(item) for item in first}) == 2
    finally:
        trainer._close_training_envs()
        trainer.tracker.close()


def test_tactical_trainer_completes_one_update_and_evaluation(tmp_path: Path):
    source = Path(__file__).resolve().parents[1] / "configs" / "ppo_phase4_tactical.yaml"
    config = yaml.safe_load(source.read_text(encoding="utf-8"))
    config["output_dir"] = str(tmp_path / "run")
    config["environment"]["evaluation_backend"] = "python"
    config["environment"]["scenarios"] = config["environment"]["scenarios"][:1]
    config["ppo"].update({
        "total_timesteps": 8,
        "rollout_steps": 4,
        "num_envs": 2,
        "minibatches": 2,
        "min_update_epochs": 1,
        "max_update_epochs": 1,
        "update_epochs": 1,
    })
    config["monitoring"].update({
        "tensorboard": False,
        "checkpoint_every_updates": 0,
        "snapshot_every_updates": 0,
    })
    config["curriculum"]["god_sampling"]["enabled"] = False
    config["curriculum"]["terrain_sampling"]["enabled"] = False
    config["curriculum"]["bootstrap_evaluation"]["enabled"] = False
    config["evaluation"].update({
        "every_updates": 1,
        "games": 4,
        "num_envs": 1,
        "anchor_games_per_stage": 0,
    })
    path = tmp_path / "smoke.yaml"
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    trainer = PPOTrainer(path)
    trainer.train()
    assert (tmp_path / "run" / "latest.pt").is_file()
    lines = (tmp_path / "run" / "metrics.jsonl").read_text(encoding="utf-8").splitlines()
    streams = [json.loads(line)["stream"] for line in lines]
    assert "training" in streams
    assert "evaluation" in streams


