"""Phase-4 orchestration with real checkpoints and controlled gate outcomes."""

import json
import os
import sqlite3
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace

import pytest
import torch
import yaml

from samstone_rl.training.ppo_cleanrl import PPOTrainer
from samstone_rl.utils.certification import require_certified
from samstone_rl.utils.checkpoints import file_checksum, load_checkpoint, policy_checksum


@pytest.fixture
def setup_run(tmp_path, monkeypatch):
    config = yaml.safe_load(
        (Path(__file__).resolve().parents[1] / "configs/ppo_phase4_vectorized.yaml").read_text(
            encoding="utf-8"
        )
    )
    config["device"] = "cpu"
    config["output_dir"] = str(tmp_path / "run")
    config["environment"].update(evaluation_backend="python", profile_backend="python_approximate")
    config["model"].update(hidden_dim=16, action_hidden_dim=8)
    config["ppo"].update(
        num_envs=2,
        rollout_steps=4,
        total_timesteps=16,
        minibatches=2,
        min_update_epochs=1,
        max_update_epochs=1,
    )
    config["curriculum"]["bootstrap_evaluation"] = {"enabled": False}
    config["monitoring"].update(
        tensorboard=False, checkpoint_every_updates=0, snapshot_every_updates=0
    )
    config["phase4_automation"]["minimum_updates_between_attempts"] = 2
    path = tmp_path / "config.yaml"

    def oracle(self):
        return dict(
            godot_version="test fixture",
            catalogue_checksum=self.provenance["content"],
            rules_checksum=self.provenance["game_rules"],
            action_feature_schema=self.provenance["feature_schema"],
        )

    monkeypatch.setattr(PPOTrainer, "_evaluation_manifest", oracle)

    def create(*, resume=False):
        path.write_text(yaml.safe_dump(config), encoding="utf-8")
        trainer = PPOTrainer(path, mode="resume" if resume else "create")
        # Unit tests control gate results, not Godot match execution.
        trainer.evaluation_backend = "godot"
        return trainer

    return config, create


def ready(trainer):
    trainer.curriculum.stage_index = len(trainer.curriculum.stages) - 1
    trainer.curriculum.awaiting_final_validation = True
    trainer.curriculum.bootstrap_evaluation_completed = True


def gate(trainer, passed, calls):
    def run(**kwargs):
        calls.append(kwargs)
        kwargs["on_progress"](4, 4)
        trainer.curriculum.accept_final_validation(passed)
        return SimpleNamespace(passed=passed, to_dict=lambda: {"passed": passed})

    return run


def advance_weights(trainer):
    with torch.no_grad():
        next(trainer.model.parameters()).add_(0.01)


def test_success_certifies_exact_policy_and_resume_stops_before_ppo(setup_run, monkeypatch):
    _, create = setup_run
    calls = []
    with create() as trainer:
        ready(trainer)
        monkeypatch.setattr(trainer, "run_final_gate", gate(trainer, True, calls))
        assert trainer._automatic_phase_four_gate(64, 8, {})
        certified = load_checkpoint(trainer.output / "phase4_validated.pt")
        require_certified(certified, "phase4", trainer.provenance)
        assert certified["global_step"] == 64
        assert certified["update"] == 8
        latest = trainer.output / "latest.pt"
        assert load_checkpoint(latest)["phase4_automation"]["status"] == "completed"
    with create(resume=True) as trainer:
        trainer.load_checkpoint(latest)
        monkeypatch.setattr(trainer, "_collect_rollout", lambda *a: pytest.fail("unexpected PPO"))
        trainer.train()
        assert trainer._phase4_exit_code == 0
        assert len(calls) == 1


def test_failure_requires_new_weights_cooldown_and_confirmations(setup_run, monkeypatch):
    _, create = setup_run
    calls = []
    with create() as trainer:
        ready(trainer)
        monkeypatch.setattr(trainer, "run_final_gate", gate(trainer, False, calls))
        assert not trainer._automatic_phase_four_gate(64, 8, {})
        assert not trainer.curriculum.awaiting_final_validation
        assert trainer.curriculum.consecutive_promotion_successes == 0
        assert trainer._phase4_auto["retry_after_update"] == 10
        assert not (trainer.output / "phase4_validated.pt").exists()
        ready(trainer)
        assert not trainer._automatic_phase_four_gate(72, 9, {})
        advance_weights(trainer)
        # Reaching the cooldown alone does not replace confirmations.
        assert not trainer._automatic_phase_four_gate(80, 10, {})
        ready(trainer)
        assert not trainer._automatic_phase_four_gate(80, 10, {})
        assert len(calls) == 2
        assert calls[0]["seed_offset"] != calls[1]["seed_offset"]
        assert calls[0]["identity"]["policy"] != calls[1]["identity"]["policy"]


def test_same_failed_weights_are_never_rerolled(setup_run, monkeypatch):
    _, create = setup_run
    calls = []
    with create() as trainer:
        ready(trainer)
        monkeypatch.setattr(trainer, "run_final_gate", gate(trainer, False, calls))
        trainer._automatic_phase_four_gate(64, 8, {})
        ready(trainer)
        assert not trainer._automatic_phase_four_gate(800, 100, {})
        assert len(calls) == 1


def test_interruption_resumes_frozen_candidate_even_beyond_ppo_budget(setup_run, monkeypatch):
    _, create = setup_run
    with create() as trainer:
        ready(trainer)

        def interrupt(**kwargs):
            kwargs["on_progress"](1, 4)
            raise InterruptedError("Godot unavailable")

        monkeypatch.setattr(trainer, "run_final_gate", interrupt)
        with pytest.raises(InterruptedError):
            trainer._automatic_phase_four_gate(64, 8, {})
        latest = trainer.output / "latest.pt"
        candidate = deepcopy(trainer._phase4_auto["candidate"])
        assert load_checkpoint(latest)["phase4_automation"]["failures"] == 0
        assert json.loads((trainer.output / "phase4_status.json").read_text())[
            "resumable_validation"
        ]
    calls = []
    with create(resume=True) as trainer:
        trainer.load_checkpoint(latest)
        assert trainer._phase4_auto["candidate"] == candidate
        monkeypatch.setattr(trainer, "run_final_gate", gate(trainer, True, calls))
        monkeypatch.setattr(trainer, "_collect_rollout", lambda *a: pytest.fail("unexpected PPO"))
        trainer.train()
        assert calls[0]["identity"] == candidate["identity"]
        assert calls[0]["seed_offset"] == candidate["seed_offset"]
        assert file_checksum(Path(candidate["path"])) == candidate["checksum"]


@pytest.mark.parametrize("changed", ["source", "criteria"])
def test_pending_gate_cannot_mix_source_or_criteria(setup_run, monkeypatch, changed):
    _, create = setup_run
    with create() as trainer:
        ready(trainer)
        monkeypatch.setattr(trainer, "run_final_gate", lambda **k: (_ for _ in ()).throw(OSError()))
        with pytest.raises(OSError):
            trainer._automatic_phase_four_gate(64, 8, {})
        saved = load_checkpoint(trainer.output / "latest.pt")
        if changed == "source":
            trainer.provenance = {**trainer.provenance, "python_source": "changed"}
        else:
            trainer.config["evaluation"]["final_gate"]["maximum_loss_rate"] = 0.09
        with pytest.raises(ValueError, match="modifie"):
            trainer._restore_phase_four_automation(saved, criteria_changed=changed == "criteria")


def test_tampered_candidate_is_rejected(setup_run, monkeypatch):
    _, create = setup_run
    with create() as trainer:
        ready(trainer)
        monkeypatch.setattr(trainer, "run_final_gate", lambda **k: (_ for _ in ()).throw(OSError()))
        with pytest.raises(OSError):
            trainer._automatic_phase_four_gate(64, 8, {})
        Path(trainer._phase4_auto["candidate"]["path"]).write_bytes(b"damaged")
        with pytest.raises(ValueError, match="altere"):
            trainer._automatic_phase_four_gate(64, 8, {})


def test_crash_after_candidate_save_adopts_matching_orphan(setup_run, monkeypatch):
    _, create = setup_run
    with create() as trainer:
        ready(trainer)
        trainer._save("latest.pt", 64, {}, 8)
        latest = trainer.output / "latest.pt"
        original_save = trainer._save

        def crash(name, *args):
            if name == "latest.pt":
                raise OSError("crash before latest")
            original_save(name, *args)

        monkeypatch.setattr(trainer, "_save", crash)
        with pytest.raises(OSError):
            trainer._automatic_phase_four_gate(64, 8, {})
        candidate = Path(trainer._phase4_auto["candidate"]["path"])
        checksum = file_checksum(candidate)
    with create(resume=True) as trainer:
        trainer.load_checkpoint(latest)
        monkeypatch.setattr(trainer, "run_final_gate", gate(trainer, True, []))
        assert trainer._automatic_phase_four_gate(64, 8, {})
        assert file_checksum(candidate) == checksum


def test_attempt_limit_stops_and_increasing_budget_allows_learning(setup_run, monkeypatch):
    config, create = setup_run
    config["phase4_automation"]["maximum_failed_attempts"] = 1
    with create() as trainer:
        ready(trainer)
        monkeypatch.setattr(trainer, "run_final_gate", gate(trainer, False, []))
        assert trainer._automatic_phase_four_gate(64, 8, {})
        assert trainer._phase4_exit_code == 2
        latest = trainer.output / "latest.pt"
        assert load_checkpoint(latest)["phase4_automation"]["status"] == "retry_limit_reached"
    config["phase4_automation"]["maximum_failed_attempts"] = 2
    with create(resume=True) as trainer:
        trainer.load_checkpoint(latest)
        assert not trainer._automatic_phase_four_gate(64, 8, {})
        assert trainer._phase4_exit_code == 0
        assert trainer._phase4_auto["status"] == "training"


def test_legacy_pending_checkpoint_trains_before_new_confirmations(setup_run):
    _, create = setup_run
    with create() as trainer:
        ready(trainer)
        trainer._resume_update = 8
        trainer._restore_phase_four_automation({}, criteria_changed=False)
        assert not trainer.curriculum.awaiting_final_validation
        assert trainer.curriculum.bootstrap_evaluation_completed
        assert trainer._phase4_auto["retry_after_update"] == 10


def test_final_confirmation_runs_gate_at_actual_update_and_stops(setup_run, monkeypatch):
    _, create = setup_run
    calls = []
    with create() as trainer:
        trainer.curriculum.bootstrap_evaluation_completed = True

        def confirm(step, update, episodes, evaluation):
            ready(trainer)

        monkeypatch.setattr(trainer, "_after_training_update", confirm)
        monkeypatch.setattr(trainer, "run_final_gate", gate(trainer, True, calls))
        trainer.train()
        latest = load_checkpoint(trainer.output / "latest.pt")
        assert latest["global_step"] == 8
        assert latest["update"] == 1
        assert len(calls) == 1


def test_budget_exhaustion_is_not_success(setup_run):
    _, create = setup_run
    with create() as trainer:
        trainer._resume_global_step = 16
        trainer._resume_update = 2
        trainer.train()
        assert trainer._phase4_exit_code == 2
        assert not trainer.curriculum.completed
        assert (
            json.loads((trainer.output / "phase4_status.json").read_text())["phase"]
            == "budget_exhausted"
        )


def test_failed_gate_returns_to_ppo_then_certifies_new_candidate(setup_run, monkeypatch):
    config, create = setup_run
    config["ppo"]["total_timesteps"] = 32
    with create() as trainer:
        trainer.curriculum.bootstrap_evaluation_completed = True
        policies = []

        def confirm(*args):
            ready(trainer)

        def final_gate(**kwargs):
            policies.append(kwargs["identity"]["policy"])
            return gate(trainer, len(policies) == 2, [])(**kwargs)

        monkeypatch.setattr(trainer, "_after_training_update", confirm)
        monkeypatch.setattr(trainer, "run_final_gate", final_gate)
        trainer.train()
        latest = load_checkpoint(trainer.output / "latest.pt")
        assert latest["update"] == 3
        assert latest["global_step"] == 24
        assert policies[0] != policies[1]
        assert latest["phase4_automation"]["attempts"] == 2
        assert latest["phase4_automation"]["failures"] == 1
        assert latest["optimizer"]["state"]
        assert trainer._phase4_exit_code == 0


def test_bootstrap_after_resume_preserves_training_counters(setup_run, monkeypatch):
    config, create = setup_run
    config["curriculum"]["bootstrap_evaluation"] = {"enabled": True}
    config["curriculum"]["god_thresholds"] = {}
    config["curriculum"]["god_sampling"]["enabled"] = False
    config["curriculum"]["terrain_sampling"]["enabled"] = False
    with create() as trainer:
        trainer._resume_global_step, trainer._resume_update = 80, 10
        result = dict(
            wins=0,
            draws=0,
            losses=500,
            games=500,
            win_rate=0,
            wilson_lower=0,
            loss_rate=1,
            non_loss_rate=0,
            non_loss_wilson_lower=0,
            anchors={},
            by_god={},
            by_blocked_count={},
        )
        monkeypatch.setattr(trainer, "evaluate", lambda **kwargs: result)
        trainer._run_bootstrap_evaluation()
        latest = load_checkpoint(trainer.output / "latest.pt")
        assert latest["global_step"] == 80
        assert latest["update"] == 10
        assert latest["curriculum"]["bootstrap_evaluation_completed"]


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_real_godot_gate_resumes_without_replaying_committed_match(tmp_path, monkeypatch):
    config = yaml.safe_load(
        (Path(__file__).resolve().parents[1] / "configs/ppo_phase4_vectorized.yaml").read_text(
            encoding="utf-8"
        )
    )
    config["device"] = "cpu"
    config["output_dir"] = str(tmp_path / "real_run")
    config["environment"]["profile_backend"] = "python_approximate"
    config["environment"]["scenarios"] = config["environment"]["scenarios"][:1]
    config["model"].update(hidden_dim=16, action_hidden_dim=8)
    config["ppo"].update(
        num_envs=1,
        rollout_steps=4,
        total_timesteps=4,
        minibatches=1,
        min_update_epochs=1,
        max_update_epochs=1,
    )
    config["curriculum"]["stages"] = config["curriculum"]["stages"][:1]
    config["curriculum"]["god_thresholds"] = {}
    config["curriculum"]["bootstrap_evaluation"] = {"enabled": False}
    config["evaluation"]["num_envs"] = 1
    # Exercise certification plumbing, not the trained policy's strength.
    config["evaluation"]["final_gate"].update(
        games_per_slice=1,
        overall_win_rate=0,
        confidence_floor=0,
        maximum_loss_rate=1,
        non_loss_confidence_floor=0,
        minimum_slice_win_rate=0,
        maximum_slice_loss_rate=1,
        god_thresholds={},
        core_god_thresholds=None,
    )
    config["monitoring"].update(
        tensorboard=False, checkpoint_every_updates=0, snapshot_every_updates=0
    )
    path = tmp_path / "real_config.yaml"
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    with PPOTrainer(path) as trainer:
        trainer.train()
        latest = trainer.output / "latest.pt"
        assert load_checkpoint(latest)["optimizer"]["state"]
    with PPOTrainer(path, mode="resume") as trainer:
        trainer.load_checkpoint(latest)
        ready(trainer)
        original_gate = trainer.run_final_gate

        def interrupted_gate(**kwargs):
            original_progress = kwargs["on_progress"]

            def progress(completed, total):
                original_progress(completed, total)
                if completed == 1:
                    raise InterruptedError("simulated interruption after durable commit")

            return original_gate(**{**kwargs, "on_progress": progress})

        monkeypatch.setattr(trainer, "run_final_gate", interrupted_gate)
        with pytest.raises(InterruptedError):
            trainer._automatic_phase_four_gate(4, 1, {})
        candidate = deepcopy(trainer._phase4_auto["candidate"])
        pending = load_checkpoint(latest)
        ledger = next((trainer.output / "evaluations/phase4").glob("*.sqlite3"))
        with sqlite3.connect(ledger) as db:
            assert db.execute("SELECT COUNT(*) FROM results").fetchone()[0] == 1
    with PPOTrainer(path, mode="resume") as trainer:
        trainer.load_checkpoint(latest)
        played = []
        original_play = trainer._evaluation_game_with_retry

        def play(*args, **kwargs):
            played.append(args[4])
            return original_play(*args, **kwargs)

        monkeypatch.setattr(trainer, "_evaluation_game_with_retry", play)
        monkeypatch.setattr(trainer, "_collect_rollout", lambda *a: pytest.fail("unexpected PPO"))
        trainer.train()
        assert len(played) == 3
        assert trainer._phase4_exit_code == 0
        certified = load_checkpoint(trainer.output / "phase4_validated.pt")
        require_certified(certified, "phase4", trainer.provenance)
        assert certified["update"] == 1
        assert certified["global_step"] == 4
        assert policy_checksum(trainer.model) == candidate["identity"]["policy"]
        assert file_checksum(Path(candidate["path"])) == candidate["checksum"]
        for key, values in pending["optimizer"]["state"].items():
            for name, value in values.items():
                assert torch.equal(certified["optimizer"]["state"][key][name], value)
