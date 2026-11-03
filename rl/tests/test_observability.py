import json
import shutil
from pathlib import Path

import numpy as np
import pytest
import torch
import yaml
from test_decks import synthetic_catalog

from samstone_rl.bridge import GodotProtocolError
from samstone_rl.evaluation import MatchAction, MatchRecord, MatchStore
from samstone_rl.observability import (
    HealthMonitor,
    RunTracker,
    build_run_manifest,
    summarize_run_profile,
)
from samstone_rl.observability.balance_report import generate_balance_report
from samstone_rl.observability.training_report import (
    generate_training_report,
    latest_status,
    load_json_lines,
)
from samstone_rl.training.ppo_cleanrl import PPOTrainer


def test_training_profiler_identifies_simulation_bottleneck(tmp_path):
    run = tmp_path / "profiled"
    run.mkdir()
    events = []
    for step in (1024, 2048):
        events.append({
            "stream": "training",
            "step": step,
            "metrics": {
                "update_seconds": 1.0,
                "profile": {
                    "total_seconds": 1.0,
                    "environment_seconds": 0.55,
                    "reset_seconds": 0.05,
                    "policy_seconds": 0.10,
                    "optimization_seconds": 0.15,
                    "other_seconds": 0.15,
                },
            },
        })
    events.append({"stream": "evaluation", "step": 2048,
                   "metrics": {"evaluation_seconds": 0.5}})
    (run / "metrics.jsonl").write_text(
        "\n".join(json.dumps(item) for item in events) + "\n", encoding="utf-8")

    summary = summarize_run_profile(run)

    assert summary["updates_analyzed"] == 2
    assert summary["dominant_phase"] == "environment"
    assert summary["simulation_fraction"] == pytest.approx(0.60)
    assert summary["evaluation_fraction_of_measured_time"] == pytest.approx(0.20)
    assert summary["decision"] == "vectorization_recommended"


def test_evaluation_restarts_a_crashed_godot_worker():
    trainer = object.__new__(PPOTrainer)
    attempts = 0

    def flaky(*_args):
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise GodotProtocolError("connection reset")
        return {"winner": 1}

    trainer._evaluation_game = flaky

    class FakeEnv:
        closed = 0

        def close(self):
            self.closed += 1

    env = FakeEnv()
    result = trainer._evaluation_game_with_retry(object(), 0, 1, 1, 42, env, 2)

    assert result == {"winner": 1}
    assert attempts == 2
    assert env.closed == 1


def test_tracker_reports_and_manifest_are_recoverable(tmp_path):
    config = tmp_path / "config.yaml"
    config.write_text("seed: 7\n", encoding="utf-8")
    with RunTracker(tmp_path / "run", "test", tensorboard=True) as tracker:
        tracker.write_manifest(build_run_manifest("test", {"seed": 7}, config, 7))
        tracker.log("training", 10, {"episode_return_mean": 0.5, "nested": {"value": 2}})
        tracker.log("training", 20, {"episode_return_mean": 0.8, "normalized_entropy": 0.4})
        tracker.log("evaluation", 20, {"win_rate": 0.6, "wilson_lower": 0.5})
        tracker.log_alert({"step": 20, "severity": "warning", "code": "demo",
                           "message": "test", "recommendation": "none"})

    summary = generate_training_report(tmp_path / "run")
    status = latest_status(tmp_path / "run")

    assert summary["events"] == 3
    assert summary["alerts"] == 1
    assert summary["best"]["training/episode_return_mean"]["value"] == 0.8
    assert "evaluation" in status["streams"]
    assert list((tmp_path / "run" / "tensorboard").glob("events.out.tfevents.*"))
    assert (tmp_path / "run" / "reports" / "training" / "training_report.html").is_file()
    manifest = json.loads((tmp_path / "run" / "run_manifest.json").read_text(encoding="utf-8"))
    assert manifest["seed"] == 7


def test_health_monitor_detects_persistent_and_critical_problems(tmp_path):
    monitor = HealthMonitor(tmp_path, {"consecutive_updates": 2, "target_kl": 0.01})
    assert monitor.check(1, {"approx_kl": 0.02}) == ()
    alerts = monitor.check(2, {"approx_kl": 0.03})
    assert {item.code for item in alerts} == {"high_kl"}
    critical = monitor.check(3, {"loss": float("nan"), "illegal_actions": 1})
    assert {item.code for item in critical} == {"non_finite_metric", "illegal_action"}
    assert len(monitor.critical(critical)) == 2
    assert (tmp_path / "health_state.json").is_file()

    alignment = HealthMonitor(tmp_path / "alignment", {"maximum_reward_divergence": 0.2})
    alignment.check(1, {"episode_return_mean": 0.0})
    alignment.check(2, {"evaluation_win_rate": 0.6})
    alignment.check(3, {"episode_return_mean": 0.5})
    mismatch = alignment.check(4, {"evaluation_win_rate": 0.6})
    assert "reward_misalignment" in {item.code for item in mismatch}
    forgetting = alignment.check(5, {"historical_win_rate": 0.5})
    assert "historical_regression" in {item.code for item in forgetting}


def test_balance_report_uses_match_and_action_telemetry(tmp_path):
    database = tmp_path / "matches.sqlite3"
    records = []
    actions = []
    for seed in range(8):
        won = seed < 6
        record = MatchRecord(
            "engine", "catalog", "policy", f"deck-{seed % 2}", "veskar",
            ("devoracle_n3", "avortons_des_caves_n2"), "opponent", "nerava", ("porte_fievre_n2",),
            seed, 1 if seed % 2 == 0 else 2, 1, 1 if won and seed % 2 == 0 else (
                2 if won else (2 if seed % 2 == 0 else 1)),
            10 if won else 6, 6 if won else 10, ((0, 0),), 2, 1, 0, True)
        records.append(record)
        actions.append(MatchAction(
            "engine", "catalog", "policy", record.candidate_hash, "opponent",
            seed, record.agent_player, 1, 1, record.agent_player,
            "devoracle_n3", 1, 2, 1, ({"type": "swarm"},), (),
            ("devoracle_n3", "avortons_des_caves_n2")))
    with MatchStore(database) as store:
        store.insert_many(records, actions)
        assert store.has_hand_telemetry(records[0])

    report = generate_balance_report(database, tmp_path / "report", minimum_samples=2)

    assert report["matches"] == 8
    assert report["overall"]["wins"] == 6
    assert report["tables"]["card_played"][0]["key"] == "devoracle_n3"
    assert report["tables"]["triggered_effect"][0]["key"] == "swarm"
    assert report["card_action_statistics"][0]["captures_per_play"] == 1.0
    usage = next(item for item in report["card_usage_statistics"]
                 if item["stone_id"] == "devoracle_n3")
    assert usage["available_decisions"] == 8
    assert usage["selection_rate_when_available"] == 1.0
    assert (tmp_path / "report" / "balance_report.html").is_file()
    assert (tmp_path / "report" / "balance_card_in_deck.csv").is_file()
    assert (tmp_path / "report" / "balance_card_usage.csv").is_file()


def test_balance_report_lists_cards_never_selected_from_catalog(tmp_path):
    catalog = synthetic_catalog()
    snapshot = {
        "schema_version": catalog.schema_version,
        "deck_size": catalog.deck_size,
        "deck_budget": catalog.deck_budget,
        "checksum": catalog.checksum,
        "gods": [{"id": item} for item in catalog.gods],
        "variants": [
            {"stone_id": item.stone_id, "lineage_id": item.lineage_id,
             "level": item.level, "max_level": item.max_level,
             "affinity": item.affinity, "cost": item.cost}
            for item in catalog.variants.values()
        ],
    }
    catalog_path = tmp_path / "catalog_snapshot.json"
    catalog_path.write_text(json.dumps(snapshot), encoding="utf-8")
    records = [MatchRecord(
        "engine", catalog.checksum, "policy", f"deck-{index}", "veskar",
        ("n00_n1",), "opponent", "veskar", ("avortons_des_caves_n1",), index,
        1, 1, 1, 10, 5) for index in range(5)]
    database = tmp_path / "matches.sqlite3"
    with MatchStore(database) as store:
        store.insert_many(records)

    report = generate_balance_report(
        database, tmp_path / "report", minimum_samples=2,
        catalog_snapshot=catalog_path)

    never = {item["stone_id"] for item in report["findings"]["never_selected_cards"]}
    assert "n01_n1" in never
    assert "n00_n1" not in never


def test_ppo_metrics_are_aggregated_and_checkpoint_resume_is_versioned(tmp_path):
    source = yaml.safe_load(
        (Path(__file__).resolve().parents[1]
         / "configs" / "ppo_phase4_tactical.yaml").read_text(encoding="utf-8"))
    source["output_dir"] = str(tmp_path / "run")
    source["monitoring"]["tensorboard"] = False
    source["ppo"].update({"total_timesteps": 16, "rollout_steps": 16,
                          "num_envs": 1, "minibatches": 4, "update_epochs": 2})
    source["evaluation"]["num_envs"] = 1
    config_path = tmp_path / "ppo.yaml"
    config_path.write_text(yaml.safe_dump(source), encoding="utf-8")
    trainer = PPOTrainer(config_path)
    try:
        storage = trainer._empty_storage(16)
        storage["obs"].normal_()
        storage["masks"][:, :8] = True
        storage["actions"] = torch.arange(16, device=trainer.device) % 8
        with torch.no_grad():
            if trainer.tactical_features_enabled:
                distribution, values = trainer.model.distribution_and_value(
                    storage["obs"], storage["masks"], storage["action_features"])
            else:
                distribution, values = trainer.model.distribution_and_value(
                    storage["obs"], storage["masks"])
            storage["log_probs"] = distribution.log_prob(storage["actions"])
            storage["values"] = values
        advantages = torch.linspace(-1, 1, 16, device=trainer.device)
        returns = storage["values"] + advantages

        metrics = trainer._optimize(storage, advantages, returns)
        trainer._save("latest.pt", 16, {"win_rate": 0.5}, update=1)

        assert {"normalized_entropy", "gradient_norm", "explained_variance"} <= metrics.keys()
        assert all(np.isfinite(value) for value in metrics.values())
        assert not (tmp_path / "run" / "latest.pt.tmp").exists()
        assert (tmp_path / "run" / "latest.pt.sha256").is_file()
    finally:
        trainer.tracker.close()
        trainer._close_training_envs()

    resumed = PPOTrainer(config_path)
    try:
        resumed.load_checkpoint(tmp_path / "run" / "latest.pt")
        assert resumed._resume_global_step == 16
        assert resumed._resume_update == 1
        corrupt = tmp_path / "run" / "corrupt.pt"
        shutil.copy2(tmp_path / "run" / "latest.pt", corrupt)
        shutil.copy2(tmp_path / "run" / "latest.pt.sha256",
                     tmp_path / "run" / "corrupt.pt.sha256")
        corrupt.write_bytes(corrupt.read_bytes() + b"corrupt")
        with pytest.raises(RuntimeError, match="checksum invalide"):
            resumed.load_checkpoint(corrupt)
    finally:
        resumed.tracker.close()
        resumed._close_training_envs()


def test_jsonl_loader_ignores_interrupted_last_line(tmp_path):
    path = tmp_path / "events.jsonl"
    path.write_text('{"ok": 1}\n{"partial":', encoding="utf-8")
    assert load_json_lines(path) == ({"ok": 1},)


def test_vectorized_ppo_keeps_batch_shape_and_vector_gae(tmp_path):
    source = yaml.safe_load(
        (Path(__file__).resolve().parents[1]
         / "configs" / "ppo_phase4_tactical.yaml").read_text(encoding="utf-8"))
    source["output_dir"] = str(tmp_path / "vectorized")
    source["monitoring"]["tensorboard"] = False
    source["evaluation"]["num_envs"] = 1
    source["ppo"].update({
        "total_timesteps": 16,
        "rollout_steps": 4,
        "num_envs": 4,
        "minibatches": 4,
    })
    config_path = tmp_path / "vectorized.yaml"
    config_path.write_text(yaml.safe_dump(source), encoding="utf-8")
    trainer = PPOTrainer(config_path)
    try:
        storage = trainer._empty_storage(16)
        storage["rewards"] = torch.arange(16, dtype=torch.float32, device=trainer.device) / 10
        storage["values"] = torch.linspace(0, 1, 16, device=trainer.device)
        storage["dones"][3] = 1.0
        storage["dones"][11] = 1.0
        advantages, returns = trainer._gae_vectorized(
            storage, torch.zeros(4, device=trainer.device), steps=4)

        assert trainer.num_envs == 4
        assert trainer.batch_env is not None
        assert trainer.batch_env.num_envs == 4
        assert advantages.shape == (16,)
        assert returns.shape == (16,)
        assert torch.isfinite(advantages).all()
    finally:
        trainer.tracker.close()
        trainer._close_training_envs()


def test_environment_width_can_change_when_loading_a_checkpoint(tmp_path):
    source = yaml.safe_load(
        (Path(__file__).resolve().parents[1]
         / "configs" / "ppo_phase4_tactical.yaml").read_text(encoding="utf-8"))
    source["output_dir"] = str(tmp_path / "sequential")
    source["monitoring"]["tensorboard"] = False
    source["evaluation"]["num_envs"] = 1
    source["ppo"].update({"total_timesteps": 16, "rollout_steps": 16,
                          "num_envs": 1, "minibatches": 4})
    sequential_path = tmp_path / "sequential.yaml"
    sequential_path.write_text(yaml.safe_dump(source), encoding="utf-8")
    sequential = PPOTrainer(sequential_path)
    try:
        sequential._save("latest.pt", 16, {"win_rate": 0.5}, update=1)
    finally:
        sequential.tracker.close()
        sequential._close_training_envs()

    vectorized = yaml.safe_load(yaml.safe_dump(source))
    vectorized["output_dir"] = str(tmp_path / "vectorized")
    vectorized["ppo"].update({
        "total_timesteps": 16,
        "rollout_steps": 4,
        "num_envs": 4,
        "minibatches": 4,
    })
    vectorized_path = tmp_path / "vectorized.yaml"
    vectorized_path.write_text(yaml.safe_dump(vectorized), encoding="utf-8")
    trainer = PPOTrainer(vectorized_path)
    try:
        trainer.load_checkpoint(tmp_path / "sequential" / "latest.pt")
        assert trainer._resume_global_step == 16
        assert trainer._resume_update == 1
    finally:
        trainer.tracker.close()
        trainer._close_training_envs()


def test_python_batch_backend_runs_a_complete_ppo_update(tmp_path):
    source = yaml.safe_load(
        (Path(__file__).resolve().parents[1]
         / "configs" / "ppo_phase4_tactical.yaml").read_text(encoding="utf-8"))
    source["output_dir"] = str(tmp_path / "batch-run")
    source["environment"]["backend"] = "python_batch"
    source["environment"]["evaluation_backend"] = "python"
    source["monitoring"].update({
        "tensorboard": False,
        "checkpoint_every_updates": 0,
        "snapshot_every_updates": 0,
    })
    source["ppo"].update({
        "total_timesteps": 32,
        "rollout_steps": 4,
        "num_envs": 8,
        "minibatches": 4,
        "update_epochs": 1,
    })
    source["evaluation"]["every_updates"] = 2
    source["evaluation"]["num_envs"] = 1
    config_path = tmp_path / "batch.yaml"
    config_path.write_text(yaml.safe_dump(source), encoding="utf-8")

    trainer = PPOTrainer(config_path)
    trainer.train()

    events = load_json_lines(tmp_path / "batch-run" / "metrics.jsonl")
    training = [event for event in events if event["stream"] == "training"]
    assert len(training) == 1
    assert training[0]["metrics"]["environment_count"] == 8
    assert training[0]["metrics"]["illegal_actions"] == 0
    manifest = json.loads(
        (tmp_path / "batch-run" / "run_manifest.json").read_text(encoding="utf-8"))
    assert manifest["extra"]["training_backend"] == "python_batch"
    assert manifest["extra"]["engine_manifest"]["batch_size"] == 8
