import json
from pathlib import Path

import numpy as np
import pytest
import torch
import yaml
from checkpoint_fixtures import certified

from samstone_rl.models.policy import build_policy
from samstone_rl.opponents.checkpoint import CheckpointOpponent
from samstone_rl.training.league import LeagueOpponent, SelfPlayLeague
from samstone_rl.training.ppo_self_play import PhaseFiveTrainer
from samstone_rl.utils.certification import require_certified
from samstone_rl.utils.checkpoints import (
    load_checkpoint,
    policy_checksum,
    save_checkpoint,
    state_checksum,
)


def _checkpoint(path: Path, completed: bool = True) -> None:
    model_config = {"architecture": "tactical_actor_critic", "hidden_dim": 16}
    model = build_policy({"model": model_config})
    torch.save(
        certified(
            {
                "model": model.state_dict(),
                "global_step": 42,
                "evaluation": {"win_rate": 0.96},
                "config": {"model": model_config},
                "curriculum": {"completed": completed, "stage_index": 7},
            },
            "phase4",
        ),
        path,
    )


def test_league_persists_and_samples_frozen_checkpoint(tmp_path):
    checkpoint = tmp_path / "source.pt"
    _checkpoint(checkpoint)
    league = SelfPlayLeague(tmp_path / "league", {"current": 1.0, "godot": 0.0})
    league.register(checkpoint, 42, 0.96, "current")
    opponent = league.sample(np.random.default_rng(4))
    assert isinstance(opponent, CheckpointOpponent)
    metrics = league.metrics_snapshot()
    assert metrics["samples"]["current"] == 1
    rating = league.record_result("agent", league.entries[0].name, 1.0, 42)
    assert rating["agent_rating"] > 1500.0
    assert (tmp_path / "league" / "results.jsonl").is_file()
    restored = SelfPlayLeague(tmp_path / "league", {"current": 1.0})
    assert len(restored.entries) == 1
    assert restored.ratings["agent"] == rating["agent_rating"]


def test_phase_five_rejects_unvalidated_checkpoint(tmp_path):
    checkpoint = tmp_path / "unvalidated.pt"
    _checkpoint(checkpoint, completed=False)
    config = Path(__file__).resolve().parents[1] / "configs" / "ppo_phase4_tactical.yaml"
    with pytest.raises(ValueError, match="phase4_validated"):
        PhaseFiveTrainer(config, phase4_checkpoint=checkpoint)


@pytest.fixture
def run_config(tmp_path):
    config = yaml.safe_load(
        (Path(__file__).resolve().parents[1] / "configs/ppo_self_play_v2.yaml").read_text(
            encoding="utf-8"
        )
    )
    config["output_dir"] = str(tmp_path / "run")
    config["model"]["hidden_dim"] = 16
    config["ppo"].update(
        rollout_steps=8,
        num_envs=2,
        minibatches=2,
        total_timesteps=64,
        min_update_epochs=1,
        max_update_epochs=1,
    )
    config["environment"]["evaluation_backend"] = "python"
    config["monitoring"].update(
        tensorboard=False, checkpoint_every_updates=0, snapshot_every_updates=0
    )
    config["evaluation"]["every_updates"] = 100
    config["phase5"]["training_weights"] = {"current": 1.0}
    config["phase5"]["minimum_updates_between_attempts"] = 1
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    source = tmp_path / "phase4_validated.pt"
    _checkpoint(source)
    return config, path, source


def test_initial_champion_is_frozen_and_is_not_replaced_on_a_timer(run_config):
    config, path, source = run_config
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        assert len(trainer.league.entries) == 1
        assert trainer.curriculum.stage_index == 7
        champion = dict(trainer.phase5_state["champions"][0])
        trainer._after_training_update(0, 501, [], None)
        assert trainer.phase5_state["champions"] == [champion]
        assert isinstance(trainer._training_opponent(), LeagueOpponent)
        assert not trainer._phase4_auto_enabled


def test_adaptive_ratio_rearms_legacy_plateau_and_reuses_interrupted_followup(
    run_config, monkeypatch
):
    config, path, source = run_config
    settings = config["phase5"].pop("adaptive_opponents")
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        trainer._stop_phase5("plateau", 24000, 1500)
        latest = trainer.output / "latest.pt"
        baseline = state_checksum(trainer.model.state_dict())

    settings["every_updates"] = 1
    config["phase5"]["adaptive_opponents"] = settings
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    seeds = []

    def interrupt(_actor, _baseline, _games, seed, _label):
        seeds.append(seed)
        raise InterruptedError

    with PhaseFiveTrainer(path, resume=latest) as trainer:
        assert trainer._before_training() is False
        assert trainer.league.weights["godot"] == 0.40
        assert trainer.league.weights["current"] == 0.60
        assert state_checksum(trainer.model.state_dict()) == baseline
        monkeypatch.setattr(trainer.arena, "retention", interrupt)
        with pytest.raises(InterruptedError):
            trainer._evaluate_opponent_sampling(24016, 1501, {})

    with PhaseFiveTrainer(path, resume=latest) as trainer:
        state = trainer.phase5_state["opponent_sampling"]
        stages = [stage.name for stage in trainer.league.godot_stages]
        deltas = {f"stage:{stage}": 0.0 for stage in stages}
        deltas[f"stage:{stages[-1]}"] = -0.30
        passed = False

        def followup(_actor, _baseline, _games, seed, label):
            seeds.append(seed)
            assert label == "bot_followup"
            return dict(passed=passed, win_rate_deltas=deltas)

        monkeypatch.setattr(trainer.arena, "retention", followup)
        assert trainer._before_training() is False
        assert seeds[0] == seeds[1]
        assert state["streak"] == 1
        assert trainer.league.weights["godot"] == 0.40
        trainer._evaluate_opponent_sampling(24032, 1502, {})
        assert trainer.league.weights["godot"] == pytest.approx(0.45)
        assert trainer.league.bot_stage_weights[-1] > trainer.league.bot_stage_weights[0] > 0
        assert trainer.phase5_state["promotions"] == 0
        passed = True
        deltas = dict.fromkeys(deltas, 0.0)
        trainer._evaluate_opponent_sampling(24048, 1503, {})
        trainer._evaluate_opponent_sampling(24064, 1504, {})
        assert trainer.league.weights["godot"] == pytest.approx(0.40)
        assert (
            load_checkpoint(latest)["phase5"]["champion_curriculum"]["opponent_sampling"] == state
        )


def test_candidate_trains_with_mixed_gods_and_resume_preserves_adam(run_config):
    config, path, source = run_config
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        trainer.config["phase5"]["mirror_probability"] = 0
        match = trainer._training_scenario_options(0, 1)["config"]
        assert match["human_god"] != match["ai_god"]
        trainer.config["phase5"]["mirror_probability"] = config["phase5"]["mirror_probability"]
        trainer.train()
        latest = trainer.output / "latest.pt"
        saved = load_checkpoint(latest)
        assert saved["global_step"] == 64
        assert saved["phase5"]["champion_curriculum"]["status"] == "budget_exhausted"
        assert not saved["phase5"]["completed"]
        assert len(trainer.league.entries) == 1
        assert saved["optimizer"]["state"]
        events = [
            json.loads(line)
            for line in (trainer.output / "league/results.jsonl").read_text().splitlines()
        ]
        assert any(e["context"]["god"] != e["context"]["opponent_god"] for e in events)
    with PhaseFiveTrainer(path, resume=latest) as trainer:
        assert trainer._resume_global_step == 64
        assert len(trainer.optimizer.state) == len(saved["optimizer"]["state"])
        assert state_checksum(trainer.model.state_dict()) == state_checksum(saved["model"])


def _improve(trainer):
    with torch.no_grad():
        next(trainer.model.parameters()).add_(0.001)


def _passed(trainer, pending):
    return dict(
        passed=True,
        candidate={"score": 0.6},
        confirmations=[{"passed": True}] * 2,
        holdout={"passed": True} if pending["final"] else None,
    )


def test_promotions_require_validation_and_final_success_stops_ppo(run_config, monkeypatch):
    config, path, source = run_config
    config["phase5"]["target_promotions"] = 2
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        trainer.evaluation_backend = "godot"
        trainer._oracle_manifest = load_checkpoint(source)["certification"]["oracle"]
        monkeypatch.setattr(
            "samstone_rl.training.phase_five_curriculum.evaluate_candidate", _passed
        )
        _improve(trainer)
        assert not trainer._start_candidate(16, 1, {})
        assert trainer.phase5_state["promotions"] == 1
        assert len(trainer.league.entries) == 2
        assert trainer.league.entries[-1].category == "current"
        _improve(trainer)
        assert trainer._start_candidate(32, 2, {})
        assert trainer.phase5_completed
        assert trainer.phase5_state["promotions"] == 2
        certified = load_checkpoint(trainer.output / "phase5_validated.pt")
        require_certified(certified, "phase5", trainer.provenance)
        assert certified["certification"]["report"]["independent_final_holdout"]
        assert certified["update"] == 2
        assert trainer._before_training()


def test_failed_promotion_keeps_champion_and_optimizer(run_config, monkeypatch):
    _, path, source = run_config
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        trainer.evaluation_backend = "godot"
        trainer._oracle_manifest = load_checkpoint(source)["certification"]["oracle"]
        original = dict(trainer.phase5_state["champions"][0])
        _improve(trainer)
        monkeypatch.setattr(
            "samstone_rl.training.phase_five_curriculum.evaluate_candidate",
            lambda *a: dict(passed=False, reason="confirmation"),
        )
        assert not trainer._start_candidate(16, 1, {})
        assert trainer.phase5_state["champions"] == [original]
        assert trainer.phase5_state["failed_attempts"] == 1
        assert trainer.phase5_state["next_attempt_update"] == 2
        assert not (trainer.output / "phase5_validated.pt").exists()
        attempts = trainer.phase5_state["attempts"]
        assert not trainer._start_candidate(32, 2, {})
        assert trainer.phase5_state["attempts"] == attempts


def test_interrupted_candidate_resumes_before_any_ppo_even_when_budget_exhausted(
    run_config, monkeypatch
):
    _, path, source = run_config
    oracle = load_checkpoint(source)["certification"]["oracle"]
    monkeypatch.setattr(PhaseFiveTrainer, "_evaluation_manifest", lambda self: oracle)
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        trainer.evaluation_backend = "godot"
        trainer._oracle_manifest = oracle
        _improve(trainer)

        def interrupt(*args):
            raise InterruptedError("simulated")

        monkeypatch.setattr(
            "samstone_rl.training.phase_five_curriculum.evaluate_candidate", interrupt
        )
        with pytest.raises(InterruptedError):
            trainer._start_candidate(64, 4, {})
        latest = trainer.output / "latest.pt"
        frozen = dict(trainer.phase5_state["pending"])
    with PhaseFiveTrainer(path, resume=latest) as trainer:
        trainer._oracle_manifest = oracle
        monkeypatch.setattr(
            "samstone_rl.training.phase_five_curriculum.evaluate_candidate", _passed
        )
        monkeypatch.setattr(trainer, "_collect_rollout", lambda *a: pytest.fail("unexpected PPO"))
        trainer.train()
        assert trainer.phase5_state["promotions"] == 1
        assert trainer.phase5_state["status"] == "budget_exhausted"
        assert load_checkpoint(trainer.output / frozen["path"])["global_step"] == 64


def test_plateau_stops_without_fabricating_a_certificate(run_config):
    config, path, source = run_config
    config["phase5"]["maximum_updates_without_promotion"] = 1
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        trainer.train()
        latest = load_checkpoint(trainer.output / "latest.pt")
        assert latest["global_step"] == 16
        assert latest["phase5"]["champion_curriculum"]["status"] == "plateau"
        assert trainer._phase5_exit_code == 2
        assert not (trainer.output / "phase5_validated.pt").exists()


def test_snapshot_commit_is_recovered_before_any_new_rollout(run_config, monkeypatch):
    _, path, source = run_config
    oracle = load_checkpoint(source)["certification"]["oracle"]
    monkeypatch.setattr(PhaseFiveTrainer, "_evaluation_manifest", lambda self: oracle)
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        trainer.evaluation_backend = "godot"
        _improve(trainer)
        trainer._save("latest.pt", 16, {}, 1)
        latest = trainer.output / "latest.pt"
        original = trainer._save

        def interrupted_save(name, *args):
            if name == "latest.pt":
                raise OSError("crash between candidate and latest commits")
            original(name, *args)

        monkeypatch.setattr(trainer, "_save", interrupted_save)
        with pytest.raises(OSError):
            trainer._start_candidate(16, 1, {})
    with PhaseFiveTrainer(path, resume=latest) as trainer:
        monkeypatch.setattr(
            "samstone_rl.training.phase_five_curriculum.evaluate_candidate", _passed
        )
        assert not trainer._before_training()
        assert trainer.phase5_state["promotions"] == 1
        assert trainer.phase5_state["attempts"] == 1


def test_legacy_migration_is_explicit_and_keeps_learned_state(run_config):
    _, path, source = run_config
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        trainer.train()
        latest = trainer.output / "latest.pt"
        payload = load_checkpoint(latest)
        payload["phase5"].pop("champion_curriculum")
        payload["config"]["phase5"] = dict(
            weight_schedule=[], league_directory=str(latest.parent / "league")
        )
        payload["config"]["evaluation"] = dict(
            every_updates=100,
            games=500,
            num_envs=10,
            seed_base=5100000000,
            anchor_games_per_stage=0,
            final_gate={"overall_win_rate": 0.85},
        )
        manifest = latest.parent / "run_manifest.json"
        recorded = json.loads(manifest.read_text(encoding="utf-8"))
        recorded["config"] = payload["config"]
        recorded["config_sha256"] = "legacy-config"
        manifest.write_text(json.dumps(recorded), encoding="utf-8")
        save_checkpoint(latest, payload)
    with pytest.raises(ValueError, match="migrate-legacy"):
        PhaseFiveTrainer(path, resume=latest)
    with PhaseFiveTrainer(path, resume=latest, migrate_legacy_phase5=True) as trainer:
        assert trainer._resume_update == payload["update"]
        assert state_checksum(trainer.model.state_dict()) == state_checksum(payload["model"])
        assert len(trainer.optimizer.state) == len(payload["optimizer"]["state"])
        assert trainer.phase5_state["promotions"] == 0
        assert trainer.phase5_state["legacy_migration"]
        assert (trainer.league_directory / "legacy_manifest.json").exists()
        assert (trainer.output / "checkpoints/legacy_phase5_source.pt").exists()


def test_champion_integrity_is_checked_on_resume(run_config):
    _, path, source = run_config
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        latest = trainer.output / "latest.pt"
        champion = trainer.output / trainer.phase5_state["champions"][0]["path"]
    champion.write_bytes(b"damaged")
    with pytest.raises(ValueError, match="altere"):
        PhaseFiveTrainer(path, resume=latest)


def test_ppo_stops_at_the_actual_final_promotion_without_using_remaining_budget(
    run_config, monkeypatch
):
    config, path, source = run_config
    config["evaluation"]["every_updates"] = 1
    config["phase5"]["target_promotions"] = 2
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    oracle = load_checkpoint(source)["certification"]["oracle"]
    monkeypatch.setattr(PhaseFiveTrainer, "_evaluation_manifest", lambda self: oracle)
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        trainer.evaluation_backend = "godot"

        def screen(**kwargs):
            return dict(
                wins=16,
                draws=0,
                losses=0,
                games=16,
                win_rate=1.0,
                wilson_lower=0.8,
                by_god={},
                by_blocked_count={},
                anchors={},
                score=0.6,
                screening_eligible=True,
            )

        monkeypatch.setattr(trainer, "evaluate", screen)
        monkeypatch.setattr(
            "samstone_rl.training.phase_five_curriculum.evaluate_candidate", _passed
        )
        trainer.train()
        final = load_checkpoint(trainer.output / "phase5_validated.pt")
        assert final["global_step"] == 32
        assert final["update"] == 2
        assert final["optimizer"]["state"]
        assert final["phase5"]["champion_curriculum"]["promotions"] == 2
        assert trainer._phase5_exit_code == 0


def test_pending_evaluation_refuses_modified_sources(run_config, monkeypatch):
    _, path, source = run_config
    oracle = load_checkpoint(source)["certification"]["oracle"]
    monkeypatch.setattr(PhaseFiveTrainer, "_evaluation_manifest", lambda self: oracle)
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        trainer.evaluation_backend = "godot"
        _improve(trainer)

        def interrupt(*args):
            raise InterruptedError()

        monkeypatch.setattr(
            "samstone_rl.training.phase_five_curriculum.evaluate_candidate", interrupt
        )
        with pytest.raises(InterruptedError):
            trainer._start_candidate(16, 1, {})
        trainer.provenance = {**trainer.provenance, "python_source": "different"}
        with pytest.raises(ValueError, match="figee incompatible"):
            trainer._resolve_candidate()


def test_authorized_source_change_restarts_pending_candidate_before_learning(
    run_config, monkeypatch
):
    _, path, source = run_config
    oracle = load_checkpoint(source)["certification"]["oracle"]
    monkeypatch.setattr(PhaseFiveTrainer, "_evaluation_manifest", lambda self: oracle)
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        trainer.evaluation_backend = "godot"
        _improve(trainer)

        def interrupt(*args):
            raise InterruptedError()

        monkeypatch.setattr(
            "samstone_rl.training.phase_five_curriculum.evaluate_candidate", interrupt
        )
        with pytest.raises(InterruptedError):
            trainer._start_candidate(16, 1, {})
        previous = dict(trainer.phase5_state["pending"])
        weights = policy_checksum(trainer.model)
        trainer.provenance = {**trainer.provenance, "python_source": "new sources"}
        trainer._allow_pending_source_restart = True

        # Explicit source migration still cannot change tournament criteria.
        trainer.config["phase5"]["promotion"]["minimum_score"] += 0.01
        with pytest.raises(ValueError, match="figee incompatible"):
            trainer._before_training()
        trainer.config["phase5"]["promotion"]["minimum_score"] -= 0.01
        observed = []

        def evaluate(trainer, pending):
            observed.append(dict(pending))
            return dict(passed=False, reason="confirmation")

        monkeypatch.setattr(
            "samstone_rl.training.phase_five_curriculum.evaluate_candidate", evaluate
        )
        assert trainer._before_training() is False
        assert policy_checksum(trainer.model) == weights
        assert observed[0]["attempt"] == previous["attempt"] + 1
        assert observed[0]["step"] == previous["step"]
        assert observed[0]["update"] == previous["update"]
        assert observed[0]["contract"]["provenance"] == trainer.provenance
        assert (trainer.output / previous["path"]).is_file()
        assert trainer.phase5_state["superseded_attempts"][0]["path"] == previous["path"]
        assert trainer.phase5_state["failed_attempts"] == 1
