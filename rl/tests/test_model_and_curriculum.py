import numpy as np
import pytest
import torch

from samstone_rl.models.actor_critic import ActorCritic
from samstone_rl.opponents import GodotProfileOpponent
from samstone_rl.opponents.checkpoint import CheckpointOpponent
from samstone_rl.training.curriculum import (
    CurriculumManager,
    CurriculumStage,
    stages_from_config,
)
from samstone_rl.training.ppo_cleanrl import PPOTrainer
from samstone_rl.training.ppo_cleanrl import main as ppo_main
from samstone_rl.training.validation import EvaluationSlice, PhaseFourGateReport


def test_masked_ppo_evaluation_updates_actor():
    torch.manual_seed(7)
    model = ActorCritic(12, 8, 32)
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-2)
    observations = torch.randn(16, 12)
    masks = torch.zeros(16, 8, dtype=torch.bool)
    masks[:, :3] = True
    with torch.no_grad():
        actions, old_log_prob, _ = model.act(observations, masks)
    before = model.actor.weight.detach().clone()
    new_log_prob, entropy, value = model.evaluate_actions(observations, masks, actions)
    ratio = (new_log_prob - old_log_prob).exp()
    loss = -(new_log_prob * torch.linspace(-1, 1, 16)).mean() - 0.01 * entropy.mean() + value.pow(2).mean()
    optimizer.zero_grad()
    loss.backward()
    assert model.actor.weight.grad is not None
    optimizer.step()
    assert not torch.equal(before, model.actor.weight)
    distribution, _ = model.distribution_and_value(observations, masks)
    assert torch.all(distribution.probs[:, 3:] == 0)
    assert torch.allclose(ratio, torch.ones_like(ratio))
    changed_log_prob, _, _ = model.evaluate_actions(observations, masks, actions)
    assert not torch.allclose((changed_log_prob - old_log_prob).exp(), torch.ones_like(ratio))


def test_curriculum_requires_final_stage_victory_before_phase_five():
    curriculum = CurriculumManager(target_win_rate=0.95, confidence_floor=0.0)
    for expected_index in range(1, 5):
        assert curriculum.consider_promotion(95, 100)
        assert curriculum.stage_index == expected_index
        assert not curriculum.phase_five_ready
    assert curriculum.consider_promotion(95, 100)
    assert curriculum.awaiting_final_validation
    assert not curriculum.phase_five_ready
    assert not curriculum.consider_promotion(100, 100)
    assert not curriculum.accept_final_validation(False)
    assert curriculum.accept_final_validation(True)
    assert curriculum.phase_five_ready


def test_curriculum_replays_old_stages():
    curriculum = CurriculumManager(target_win_rate=0.5, confidence_floor=0.0, replay_probability=1.0)
    curriculum.consider_promotion(10, 10)
    sampled = curriculum.training_stage(np.random.default_rng(1))
    assert sampled.name == "precision_0"


class _ProfileBridge:
    def __init__(self):
        self.anticipation: list[bool] = []

    def choose_profile_action(self, precision, anticipation):
        assert precision == 1.0
        self.anticipation.append(bool(anticipation))
        return {"anticipation": bool(anticipation)}


def test_progressive_anticipation_is_seeded_and_preserves_legacy_extremes():
    bridge_a, bridge_b = _ProfileBridge(), _ProfileBridge()
    first = GodotProfileOpponent(1.0, anticipation_probability=0.25)
    second = GodotProfileOpponent(1.0, anticipation_probability=0.25)
    rng_a, rng_b = np.random.default_rng(4721), np.random.default_rng(4721)
    for _ in range(100):
        first.choose(bridge_a, [], rng_a, 2)
        second.choose(bridge_b, [], rng_b, 2)
    assert bridge_a.anticipation == bridge_b.anticipation
    assert 15 <= sum(bridge_a.anticipation) <= 35

    for probability, expected in ((0.0, False), (1.0, True)):
        bridge = _ProfileBridge()
        actual_rng = np.random.default_rng(91)
        untouched_rng = np.random.default_rng(91)
        opponent = GodotProfileOpponent(
            1.0, anticipation=not expected,
            anticipation_probability=probability)
        opponent.choose(bridge, [], actual_rng, 2)
        assert bridge.anticipation == [expected]
        # The exact endpoints retain legacy RNG consumption.
        assert actual_rng.integers(1_000_000) == untouched_rng.integers(1_000_000)


def test_explicit_progressive_curriculum_promotes_automatically():
    stages = stages_from_config([
        {"name": "anticipation_25", "precision": 1.0,
         "anticipation_probability": 0.25},
        {"name": "anticipation_50", "precision": 1.0,
         "anticipation_probability": 0.50},
        {"name": "anticipation_75", "precision": 1.0,
         "anticipation_probability": 0.75},
        {"name": "anticipation_100", "precision": 1.0,
         "anticipation_probability": 1.0},
    ])
    curriculum = CurriculumManager(
        target_win_rate=0.85, confidence_floor=0.0, stages=stages)
    assert curriculum.current.name == "anticipation_25"
    for expected in ("anticipation_50", "anticipation_75", "anticipation_100"):
        assert curriculum.consider_promotion(90, 100)
        assert curriculum.current.name == expected
    assert curriculum.consider_promotion(90, 100)
    assert curriculum.awaiting_final_validation


def test_explicit_curriculum_rejects_invalid_or_duplicate_stages():
    with pytest.raises(ValueError, match="au moins un palier"):
        stages_from_config([])
    with pytest.raises(ValueError, match="uniques"):
        stages_from_config([
            {"name": "same", "precision": 1.0},
            {"name": "same", "precision": 1.0},
        ])
    with pytest.raises(ValueError, match="probabilite"):
        CurriculumStage("bad", 1.0, False, 1.1)


def test_adaptive_god_sampling_targets_weak_held_out_matchups_and_persists():
    curriculum = CurriculumManager(god_sampling={
        "enabled": True,
        "target_wilson": 0.90,
        "minimum_multiplier": 0.50,
        "maximum_multiplier": 3.00,
        "deficit_exponent": 1.0,
        "smoothing": 1.0,
    })
    scenarios = ({"god": "weak"}, {"god": "strong"})
    curriculum.initialize_god_sampling(["weak", "strong"])
    metrics = curriculum.update_god_sampling({
        "weak": {"wilson_lower": 0.50},
        "strong": {"wilson_lower": 0.89},
    })
    assert metrics["weights"]["weak"] > metrics["weights"]["strong"] * 3

    rng = np.random.default_rng(12)
    sampled = [scenarios[curriculum.sample_scenario_index(scenarios, rng)]["god"]
               for _ in range(2_000)]
    assert sampled.count("weak") > sampled.count("strong") * 3

    restored = CurriculumManager(god_sampling={"enabled": True})
    restored.initialize_god_sampling(["weak", "strong"])
    restored.load_state_dict(curriculum.state_dict())
    assert restored.god_sampling_metrics()["weights"] == metrics["weights"]


def test_adaptive_terrain_sampling_targets_weak_layout_and_persists():
    curriculum = CurriculumManager(terrain_sampling={
        "enabled": True,
        "target_wilson": 0.90,
        "minimum_multiplier": 0.50,
        "maximum_multiplier": 3.00,
        "deficit_exponent": 1.0,
        "smoothing": 1.0,
        "blocked_counts": [0, 1, 2],
    })
    metrics = curriculum.update_terrain_sampling({
        "0": {"wilson_lower": 0.89},
        "1": {"wilson_lower": 0.50},
        "2": {"wilson_lower": 0.80},
    })
    assert metrics["weights"]["1"] > metrics["weights"]["2"] > metrics["weights"]["0"]

    rng = np.random.default_rng(9)
    sampled = [curriculum.sample_blocked_count(rng) for _ in range(2_000)]
    assert sampled.count(1) > sampled.count(2) > sampled.count(0)

    restored = CurriculumManager(terrain_sampling={"enabled": True})
    restored.load_state_dict(curriculum.state_dict())
    assert restored.terrain_sampling_metrics()["weights"] == pytest.approx(metrics["weights"])


def test_loss_aware_promotion_allows_draws_but_rejects_excess_losses():
    curriculum = CurriculumManager(
        target_win_rate=0.85,
        confidence_floor=0.90,
        maximum_loss_rate=0.05,
        non_loss_confidence_floor=0.90,
    )
    # 425 wins, 50 draws, 25 losses: wins and non-loss confidence both pass.
    assert curriculum.promotion_metrics(425, 50, 500)["eligible"]
    # Same number of wins but too many losses cannot be hidden by the win rate.
    assert not curriculum.promotion_metrics(425, 0, 500)["eligible"]


def test_relaxed_intermediate_loss_gate_still_requires_many_wins():
    curriculum = CurriculumManager(
        target_win_rate=0.85,
        confidence_floor=0.90,
        maximum_loss_rate=0.07,
        non_loss_confidence_floor=0.90,
    )
    # 85% wins, 8% draws and 7% losses is enough for an intermediate stage.
    assert curriculum.promotion_metrics(425, 40, 500)["eligible"]
    # A draw-focused policy cannot qualify despite only 7% losses.
    assert not curriculum.promotion_metrics(50, 415, 500)["eligible"]


def test_curriculum_requires_consecutive_held_out_evaluations_before_promotion():
    curriculum = CurriculumManager(
        target_win_rate=0.85,
        confidence_floor=0.81,
        maximum_loss_rate=0.07,
        non_loss_confidence_floor=0.90,
        promotion_confirmations=2,
    )
    # The first 500-game evaluation only starts the confirmation streak.
    assert not curriculum.consider_promotion(426, 500, 40)
    assert curriculum.stage_index == 0
    assert curriculum.consecutive_promotion_successes == 1
    # A weak evaluation breaks the streak rather than promoting from stale data.
    assert not curriculum.consider_promotion(420, 500, 45)
    assert curriculum.consecutive_promotion_successes == 0
    # Two immediately consecutive held-out successes are required.
    assert not curriculum.consider_promotion(426, 500, 40)
    assert curriculum.consider_promotion(427, 500, 39)
    assert curriculum.stage_index == 1
    assert curriculum.consecutive_promotion_successes == 0


def test_curriculum_promotion_confirmation_survives_checkpoint_state():
    first = CurriculumManager(promotion_confirmations=2, confidence_floor=0.0)
    assert not first.consider_promotion(95, 100)
    restored = CurriculumManager(promotion_confirmations=2, confidence_floor=0.0)
    restored.load_state_dict(first.state_dict())
    assert restored.consecutive_promotion_successes == 1
    assert restored.consider_promotion(95, 100)


def test_curriculum_bootstrap_completion_survives_checkpoint_state():
    first = CurriculumManager()
    first.complete_bootstrap_evaluation()
    restored = CurriculumManager()
    restored.load_state_dict(first.state_dict())
    assert restored.bootstrap_evaluation_completed


def test_final_gate_requires_every_stage_god_camp_and_first_player():
    stages = ("easy", "hard")
    gods = ("veskar", "nerava")
    slices = [EvaluationSlice(stage, god, agent, first, 95, 0, 5)
              for stage in stages for god in gods for agent in (1, 2) for first in (1, 2)]
    report = PhaseFourGateReport.build(slices, stages, gods, minimum_games_per_slice=100)
    assert report.passed
    incomplete = PhaseFourGateReport.build(slices[:-1], stages, gods, minimum_games_per_slice=100)
    assert not incomplete.passed
    assert incomplete.missing_slices


def test_final_gate_can_enforce_loss_and_non_loss_criteria():
    stages, gods = ("hard",), ("veskar",)
    good = [EvaluationSlice("hard", "veskar", agent, first, 85, 10, 5)
            for agent in (1, 2) for first in (1, 2)]
    report = PhaseFourGateReport.build(
        good, stages, gods, overall_threshold=0.85, confidence_floor=0.90,
        slice_floor=0.80, minimum_games_per_slice=100,
        maximum_loss_rate=0.05, non_loss_confidence_floor=0.90,
        maximum_slice_loss_rate=0.10)
    assert report.passed
    failing = [EvaluationSlice("hard", "veskar", agent, first, 85, 0, 15)
               for agent in (1, 2) for first in (1, 2)]
    assert not PhaseFourGateReport.build(
        failing, stages, gods, overall_threshold=0.85, confidence_floor=0.90,
        slice_floor=0.80, minimum_games_per_slice=100,
        maximum_loss_rate=0.05, non_loss_confidence_floor=0.90,
        maximum_slice_loss_rate=0.10).passed


def test_checkpoint_reload_reproduces_deterministic_decision(tmp_path):
    torch.manual_seed(12)
    model = ActorCritic(929, 128, 32)
    observation = torch.randn(1, 929)
    mask = torch.zeros(1, 128, dtype=torch.bool)
    mask[:, :20] = True
    with torch.no_grad():
        expected, _, _ = model.act(observation, mask, deterministic=True)
    path = tmp_path / "checkpoint.pt"
    torch.save({"model": model.state_dict(), "config": {"model": {"hidden_dim": 32}}}, path)
    reloaded = CheckpointOpponent(path)
    with torch.no_grad():
        actual, _, _ = reloaded.model.act(observation, mask, deterministic=True)
    assert actual.item() == expected.item()


def test_weights_only_checkpoint_import_resets_training_state(tmp_path):
    source = ActorCritic(12, 8, 16)
    with torch.no_grad():
        for parameter in source.parameters():
            parameter.fill_(0.125)
    checkpoint = tmp_path / "source.pt"
    torch.save({
        "model": source.state_dict(),
        "global_step": 123_456,
        "update": 321,
        "best_win_rate": 0.99,
        "best_stage_index": 3,
        "curriculum": {"stage_index": 3, "completed": True},
    }, checkpoint)

    trainer = PPOTrainer.__new__(PPOTrainer)
    trainer.device = torch.device("cpu")
    trainer.model = ActorCritic(12, 8, 16)
    trainer.optimizer = torch.optim.Adam(trainer.model.parameters())
    trainer.curriculum = CurriculumManager(stages=(
        CurriculumStage("new_25", 1.0, False, 0.25),
        CurriculumStage("new_100", 1.0, False, 1.0),
    ))
    trainer.best_win_rate = -1.0
    trainer.best_stage_index = -1
    trainer._resume_global_step = 0
    trainer._resume_update = 0
    trainer.rng = np.random.default_rng(7)
    trainer.config = {"ppo": {"rollout_steps": 1, "num_envs": 1}}

    trainer.load_checkpoint(
        checkpoint, load_optimizer=False, load_training_state=False)
    assert all(torch.allclose(parameter, torch.full_like(parameter, 0.125))
               for parameter in trainer.model.parameters())
    assert trainer.curriculum.stage_index == 0
    assert not trainer.curriculum.completed
    assert trainer.best_win_rate == -1.0
    assert trainer._resume_global_step == 0
    assert trainer._resume_update == 0


def test_weights_only_refuses_to_overwrite_an_existing_run(tmp_path):
    output = tmp_path / "existing"
    output.mkdir()
    (output / "metrics.jsonl").write_text("{}\n", encoding="utf-8")
    config = tmp_path / "config.yaml"
    config.write_text(f"output_dir: '{output.as_posix()}'\n", encoding="utf-8")
    with pytest.raises(SystemExit, match="2"):
        ppo_main(["--config", str(config), "--resume", str(tmp_path / "source.pt"),
                  "--weights-only"])
