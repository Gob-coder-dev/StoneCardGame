"""Revised entry criteria and audit-preserving reuse of frozen Godot results."""

import json
import sqlite3
from contextlib import closing
from copy import deepcopy
from pathlib import Path

import pytest
import torch
import yaml

from samstone_rl.evaluation.tournament import tournament_path
from samstone_rl.training.phase_four_gate import phase_four_cases, phase_four_report
from samstone_rl.training.phase_four_reassessment import reassess_phase_four
from samstone_rl.training.ppo_cleanrl import PPOTrainer
from samstone_rl.training.ppo_self_play import PhaseFiveTrainer
from samstone_rl.training.validation import EvaluationSlice, PhaseFourGateReport
from samstone_rl.utils.certification import require_certified
from samstone_rl.utils.checkpoints import (
    file_checksum,
    load_checkpoint,
    save_checkpoint,
    state_checksum,
)


def pooled_report(nerava):
    rows = []
    for i, (agent, first) in enumerate(((1, 1), (1, 2), (2, 1), (2, 2))):
        for god, counts in (("nerava", nerava[i]), ("ilyr", (98, 2, 0)), ("veskar", (60, 20, 20))):
            rows.append(EvaluationSlice("hard", god, agent, first, *counts))
    return PhaseFourGateReport.build(
        rows,
        ["hard"],
        ["nerava", "ilyr", "veskar"],
        overall_threshold=0.8,
        confidence_floor=0.8,
        slice_floor=0.7,
        minimum_games_per_slice=100,
        maximum_loss_rate=0.1,
        non_loss_confidence_floor=0.87,
        maximum_slice_loss_rate=0.2,
        god_thresholds={"veskar": {"minimum_win_rate": 0.6, "maximum_loss_rate": 0.2}},
        core_god_thresholds={"minimum_win_rate": 0.8, "maximum_loss_rate": 0.1},
    )


def test_local_16_percent_loss_can_pass_when_pooled_god_remains_strong():
    result = pooled_report([(74, 10, 16)] + [(90, 8, 2)] * 3)
    assert result.passed
    assert result.god_stage_results["hard"]["nerava"]["games"] == 400
    assert result.god_stage_results["hard"]["nerava"]["loss_rate"] == 0.055


@pytest.mark.parametrize("outcome", [(79, 16, 5), (80, 9, 11)])
def test_other_gods_cannot_hide_a_weak_god_in_the_average(outcome):
    result = pooled_report([outcome] * 4)
    assert not result.passed
    assert result.failed_god_stages == ("hard:nerava",)
    assert not result.failed_slices


@pytest.mark.parametrize("outcome", [(70, 9, 21), (69, 25, 6)])
def test_local_safeguards_still_reject_a_weak_slice(outcome):
    result = pooled_report([outcome] + [(98, 2, 0)] * 3)
    assert not result.passed and result.failed_slices
    assert not result.failed_god_stages


@pytest.fixture
def recorded_run(tmp_path, monkeypatch):
    config = yaml.safe_load(
        (Path(__file__).resolve().parents[1] / "configs/ppo_phase4_vectorized.yaml").read_text(
            encoding="utf-8"
        )
    )
    config["device"] = "cpu"
    config["output_dir"] = str(tmp_path / "run")
    config["monitoring"]["tensorboard"] = False
    config["model"].update(hidden_dim=16, action_hidden_dim=8)
    config["ppo"].update(num_envs=1, rollout_steps=1, minibatches=1)
    config["evaluation"]["num_envs"] = 1
    config["environment"]["scenarios"] = [
        s for s in config["environment"]["scenarios"] if s["god"] in ("nerava", "veskar")
    ]
    config["curriculum"]["stages"] = config["curriculum"]["stages"][:1]
    config["evaluation"]["final_gate"].pop("core_god_thresholds")
    config["evaluation"]["final_gate"]["maximum_slice_loss_rate"] = 0.1
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    with PPOTrainer(path) as trainer:
        oracle = dict(
            godot_version="test fixture",
            catalogue_checksum=trainer.provenance["content"],
            rules_checksum=trainer.provenance["game_rules"],
            action_feature_schema=2,
        )
        trainer._oracle_manifest = oracle
        sum(p.sum() for p in trainer.model.parameters()).backward()
        trainer.optimizer.step()
        trainer.curriculum.awaiting_final_validation = True
        snapshot = trainer.output / "evaluations/phase4/candidates/attempt_0001.pt"
        identity = dict(
            provenance=trainer.provenance,
            oracle=oracle,
            policy=state_checksum(trainer.model.state_dict()),
            config=deepcopy(trainer.config),
        )
        candidate = dict(path=str(snapshot), checksum=None, seed_offset=1000000, identity=identity)
        trainer._phase4_auto.update(status="validating", attempts=1, candidate=candidate)
        trainer._save(str(snapshot), 100, {}, 10)
        trainer._phase4_auto.update(status="retry_limit_reached", failures=3, candidate=None)
        trainer.curriculum.awaiting_final_validation = False
        trainer._save("latest.pt", 100, {}, 10)
        latest = trainer.output / "latest.pt"
    cases = phase_four_cases(identity["config"], candidate["seed_offset"])
    ledger = tournament_path(cases, snapshot.parent.parent, identity)
    with closing(sqlite3.connect(ledger)) as db, db:
        db.execute("CREATE TABLE results (case_id INTEGER PRIMARY KEY, info TEXT NOT NULL)")
        for i, case in enumerate(cases):
            within_slice = i % 100
            god = config["environment"]["scenarios"][case["scenario"]]["god"]
            win, draw = (60, 20) if god == "veskar" else (85, 10)
            winner = (
                case["agent"]
                if within_slice < win
                else 0
                if within_slice < win + draw
                else 3 - case["agent"]
            )
            db.execute("INSERT INTO results VALUES (?, ?)", (i, json.dumps({"winner": winner})))
    revised = deepcopy(config)
    revised["evaluation"]["final_gate"].update(
        maximum_slice_loss_rate=0.2,
        core_god_thresholds=dict(minimum_win_rate=0.8, maximum_loss_rate=0.1),
    )
    path.write_text(yaml.safe_dump(revised), encoding="utf-8")

    class Oracle:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def engine_manifest(self):
            return oracle

    monkeypatch.setattr("samstone_rl.training.phase_four_reassessment.GodotProcess", Oracle)
    return dict(
        config=revised,
        path=path,
        latest=latest,
        snapshot=snapshot,
        ledger=ledger,
        oracle=oracle,
        identity=identity,
        cases=cases,
    )


def test_preview_does_not_write_and_reassessment_preserves_weights_and_adam(recorded_run):
    data = recorded_run
    before = load_checkpoint(data["latest"])
    checksum = file_checksum(data["latest"])
    ledger_checksum = file_checksum(data["ledger"])
    preview = reassess_phase_four(data["path"], data["latest"], commit=False)
    assert preview["passed"] and preview["reassessment"]["recorded_games"] == 800
    assert file_checksum(data["latest"]) == checksum
    assert not (data["latest"].parent / "phase4_validated.pt").exists()
    report = reassess_phase_four(data["path"], data["latest"])
    certified = load_checkpoint(data["latest"].parent / "phase4_validated.pt")
    require_certified(certified, "phase4", before["provenance"])
    assert report["reassessment"]["retrospective"]
    assert not report["reassessment"]["independent_evaluation"]
    assert state_checksum(certified["model"]) == state_checksum(before["model"])
    assert (certified["global_step"], certified["update"]) == (100, 10)
    assert file_checksum(data["ledger"]) == ledger_checksum
    for key, values in before["optimizer"]["state"].items():
        for name, value in values.items():
            assert torch.equal(certified["optimizer"]["state"][key][name], value)
    assert load_checkpoint(data["latest"])["phase4_automation"]["status"] == "completed"
    assert reassess_phase_four(data["path"], data["latest"])["passed"]
    with PPOTrainer(data["path"], mode="resume") as trainer:
        trainer._oracle_manifest = data["oracle"]
        trainer.load_checkpoint(data["latest"])
        assert trainer._automatic_phase_four_gate(100, 10, {})


@pytest.mark.parametrize(
    "change", ["deck", "schedule", "model", "incomplete", "winner", "oracle", "source"]
)
def test_reassessment_rejects_mismatched_or_incomplete_evidence(recorded_run, change):
    data = recorded_run
    if change in ("deck", "schedule"):
        config = deepcopy(data["config"])
        if change == "deck":
            config["environment"]["scenarios"][0]["deck"].reverse()
        else:
            config["evaluation"]["final_gate"]["games_per_slice"] += 1
        data["path"].write_text(yaml.safe_dump(config), encoding="utf-8")
    elif change == "model":
        latest = load_checkpoint(data["latest"])
        next(iter(latest["model"].values())).add_(1)
        save_checkpoint(data["latest"], latest)
    elif change in ("incomplete", "winner"):
        with closing(sqlite3.connect(data["ledger"])) as db, db:
            if change == "incomplete":
                db.execute("DELETE FROM results WHERE case_id = 0")
            else:
                db.execute("UPDATE results SET info = ? WHERE case_id = 0", ('{"winner": 3}',))
    elif change == "oracle":
        data["oracle"]["godot_version"] = "another engine"
    else:
        snapshot = load_checkpoint(data["snapshot"])
        snapshot["provenance"]["python_source"] = "old"
        snapshot["phase4_automation"]["candidate"]["identity"]["provenance"]["python_source"] = (
            "old"
        )
        save_checkpoint(data["snapshot"], snapshot)
    with pytest.raises(ValueError):
        reassess_phase_four(data["path"], data["latest"])
    assert not (data["latest"].parent / "phase4_validated.pt").exists()


def test_explicit_python_migration_keeps_recorded_provenance(recorded_run):
    data = recorded_run
    # Reconstruct the ledger identity too: source provenance is part of its key.
    snapshot = load_checkpoint(data["snapshot"])
    snapshot["provenance"]["python_source"] = "previous Python source"
    identity = snapshot["phase4_automation"]["candidate"]["identity"]
    identity["provenance"]["python_source"] = "previous Python source"
    save_checkpoint(data["snapshot"], snapshot)
    replacement = tournament_path(data["cases"], data["snapshot"].parent.parent, identity)
    data["ledger"].rename(replacement)
    report = reassess_phase_four(data["path"], data["latest"], allow_python_source_change=True)
    assert report["passed"]
    assert (
        report["reassessment"]["recorded_provenance"]["python_source"] == "previous Python source"
    )


def test_reassessed_certificate_can_initialize_phase_five(recorded_run, tmp_path):
    data = recorded_run
    reassess_phase_four(data["path"], data["latest"])
    config = deepcopy(data["config"])
    phase5 = yaml.safe_load(
        (Path(__file__).resolve().parents[1] / "configs/ppo_self_play_v2.yaml").read_text(encoding="utf-8")
    )["phase5"]
    config["phase5"] = phase5
    config["output_dir"] = str(tmp_path / "phase5")
    config["phase4_automation"]["enabled"] = False
    path = tmp_path / "phase5.yaml"
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    with PhaseFiveTrainer(
        path, phase4_checkpoint=data["latest"].parent / "phase4_validated.pt"
    ) as trainer:
        assert state_checksum(trainer.model.state_dict()) == data["identity"]["policy"]
        assert trainer.league.entries


def test_live_and_recorded_matches_share_identical_scoring(recorded_run):
    data = recorded_run
    with closing(sqlite3.connect(data["ledger"])) as db, db:
        outcomes = [
            json.loads(row[0]) for row in db.execute("SELECT info FROM results ORDER BY case_id")
        ]
    live = phase_four_report(data["config"], data["cases"], outcomes).to_dict()
    reused = reassess_phase_four(data["path"], data["latest"], commit=False)
    reused.pop("reassessment")
    assert reused == live
