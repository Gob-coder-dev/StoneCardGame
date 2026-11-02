import json
import os
import sqlite3
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
import torch
import yaml

from samstone_rl.bridge.godot_process import GodotProcess
from samstone_rl.bridge.process_pool import GodotProcessPool
from samstone_rl.decks import DeckCatalog, DeckGenerator, GodotDeckValidator
from samstone_rl.envs.samstone_env import RewardScheme, SamStoneEnv
from samstone_rl.evaluation import (
    BatchedDeckEvaluator,
    DeckEvaluator,
    EvaluationOpponent,
    MatchStore,
    common_schedule,
)
from samstone_rl.models.actor_critic import ActorCritic
from samstone_rl.opponents import CheckpointOpponent, GodotProfileOpponent
from samstone_rl.training.ppo_cleanrl import PPOTrainer


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_godot_and_python_expose_same_tactical_feature_schema():
    godot = SamStoneEnv(backend="godot", tactical_features=True,
                        opponent=GodotProfileOpponent(1.0, False))
    python = SamStoneEnv(backend="python", tactical_features=True,
                         opponent=GodotProfileOpponent(1.0, False))
    options = {"config": {**env_config(), "first_player": 1, "blocked": []}}
    try:
        godot_obs, godot_info = godot.reset(seed=6001, options=options)
        python_obs, python_info = python.reset(seed=6001, options=options)
        assert np.array_equal(godot_obs, python_obs)
        assert np.array_equal(godot_info["action_mask"], python_info["action_mask"])
        godot_features = godot_info["action_features"]
        python_features = python_info["action_features"]
        assert godot_features.shape == python_features.shape == (128, 79)
        # Card, target-cell and action-position features are canonical across engines.
        assert np.array_equal(godot_features[:, :74], python_features[:, :74])
        assert np.isfinite(godot_features).all()
        assert np.count_nonzero(godot_features[~godot_info["action_mask"]]) == 0
    finally:
        godot.close()
        python.close()


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_complete_profile_match_is_deterministic():
    traces = []
    for _repeat in range(2):
        env = SamStoneEnv(opponent=GodotProfileOpponent(0.0, False))
        try:
            observation, info = env.reset(seed=4242)
            trace = [observation.tobytes()]
            done = False
            while not done:
                action = int(np.flatnonzero(info["action_mask"])[0])
                observation, reward, terminated, truncated, info = env.step(action)
                scheme = RewardScheme()
                expected = scheme.captures(info["agent_captures"]) - scheme.captures(
                    info["opponent_captures"])
                if terminated:
                    expected += scheme.terminal if info["winner"] == env.agent_player else (
                        -scheme.terminal if info["winner"] else 0.0)
                assert np.isclose(reward, expected)
                trace.append((observation.tobytes(), reward, info["winner"]))
                done = terminated or truncated
            assert info["score_human"] + info["score_ai"] in (14, 15, 16)
            traces.append(trace)
        finally:
            env.close()
    assert traces[0] == traces[1]


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_profile_opponent_can_play_human_side():
    env = SamStoneEnv(opponent=GodotProfileOpponent(0.0, False), agent_player=2)
    try:
        _observation, info = env.reset(seed=99, options={"config": {"first_player": 1}})
        assert info["action_mask"].any()
        _observation, _reward, _terminated, _truncated, _info = env.step(
            int(np.flatnonzero(info["action_mask"])[0]))
    finally:
        env.close()


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_episode_telemetry_contains_reward_breakdown_and_sampled_trace():
    env = SamStoneEnv(opponent=GodotProfileOpponent(0.0, False))
    total_reward = 0.0
    try:
        _observation, info = env.reset(seed=707, options={"trace": True})
        done = False
        while not done:
            action = int(np.flatnonzero(info["action_mask"])[0])
            _observation, reward, terminated, truncated, info = env.step(action)
            assert np.isclose(reward, info["capture_reward"] + info["terminal_reward"])
            total_reward += reward
            done = terminated or truncated
        episode = info["episode"]
        assert np.isclose(episode["return"], total_reward)
        assert episode["turns"] == len(episode["actions"])
        assert episode["agent_decisions"] > 0
        assert episode["agent_captures"] >= 0
        assert episode["first_player"] in (1, 2)
        assert 0 <= episode["blocked_count"] <= 2
    finally:
        env.close()


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_godot_catalog_validation_and_batch_protocol():
    bridge = GodotProcess()
    try:
        bridge.start()
        catalog = DeckCatalog(bridge.deck_catalog())
        assert len(catalog.gods) == 6
        assert len(catalog.variants) == 275
        generator = DeckGenerator(catalog)
        candidates = [generator.random_candidate("inari", np.random.default_rng(index))
                      for index in range(32)]
        GodotDeckValidator(bridge, catalog).require_all_valid(candidates)
        requests = [{"match_id": str(index), "observer": 1,
                     "config": {**env_config(), "seed": index + 1,
                                "first_player": 1, "blocked": []}}
                    for index in range(4)]
        reset = bridge.batch_reset(requests)
        steps = [{"match_id": item["match_id"], "observer": 1,
                  "action": item["result"]["legal_actions"][0]} for item in reset]
        assert all(item["ok"] for item in bridge.batch_step(steps))
        assert bridge.release_matches([str(index) for index in range(4)]) == 0
    finally:
        bridge.close()


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_phase_six_reference_decks_are_accepted_by_godot():
    config_path = Path(__file__).resolve().parents[1] / "configs" / "deck_evolution.yaml"
    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    bridge = GodotProcess()
    try:
        bridge.start()
        catalog = DeckCatalog(bridge.deck_catalog())
        candidates = [catalog.candidate(item["god"], item["deck"])
                      for item in config["opponents"]]
        assert {item.god_id for item in candidates} == set(catalog.gods)
        GodotDeckValidator(bridge, catalog).require_all_valid(candidates)
    finally:
        bridge.close()


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_process_pool_routes_matches_across_workers():
    with GodotProcessPool(2) as pool:
        requests = [{"match_id": str(index), "observer": 1,
                     "config": {**env_config(), "seed": 100 + index,
                                "first_player": 1, "blocked": []}}
                    for index in range(4)]
        reset = pool.batch_reset(requests)
        assert all(item["ok"] for item in reset)
        states = pool.batch_get_state([{"match_id": str(index), "observer": 1}
                                       for index in range(4)])
        assert all(len(item["result"]["legal_actions"]) == 128 for item in states)
        pool.release_matches([str(index) for index in range(4)])


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_deck_evaluator_runs_real_matches_and_resumes_from_cache(tmp_path):
    checkpoint_path = tmp_path / "policy.pt"
    model = ActorCritic(929, 128, 16)
    torch.save({"model": model.state_dict(), "config": {"model": {"hidden_dim": 16}}},
               checkpoint_path)
    bridge = GodotProcess()
    env = SamStoneEnv()
    store = MatchStore(tmp_path / "matches.sqlite3")
    try:
        bridge.start()
        catalog = DeckCatalog(bridge.deck_catalog())
        candidate = catalog.candidate("inari", env_config()["human_deck"])
        opponent_policy = CheckpointOpponent(checkpoint_path)
        opponent = EvaluationOpponent("mirror", "inari", candidate.stone_ids, opponent_policy)
        manifest = bridge.engine_manifest()
        evaluator = DeckEvaluator(env, checkpoint_path, (opponent,), store,
                                  str(manifest["catalogue_checksum"]), catalog.checksum)
        schedule = common_schedule(("mirror",), 1, 7654321)

        first = evaluator.evaluate(candidate, schedule)
        second = evaluator.evaluate(candidate, schedule)

        assert first == second
        assert first.games == 4
        assert len(store.records_for(evaluator.engine_checksum, evaluator.catalog_checksum,
                                     evaluator.policy_checksum, candidate.deck_hash)) == 4
    finally:
        store.close()
        env.close()
        bridge.close()


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_batched_deck_evaluator_runs_policy_on_both_sides(tmp_path):
    checkpoint_path = tmp_path / "policy.pt"
    model = ActorCritic(929, 128, 16)
    torch.save({"model": model.state_dict(), "config": {"model": {"hidden_dim": 16}}},
               checkpoint_path)
    bridge = GodotProcess()
    store = MatchStore(tmp_path / "matches.sqlite3")
    pool = GodotProcessPool(2)
    try:
        bridge.start()
        pool.start()
        catalog = DeckCatalog(bridge.deck_catalog())
        candidate = catalog.candidate("inari", env_config()["human_deck"])
        opponent = EvaluationOpponent("mirror", "inari", candidate.stone_ids)
        evaluator = BatchedDeckEvaluator(
            pool, checkpoint_path, (opponent,), store, "engine", catalog.checksum,
            batch_size=4)

        result = evaluator.evaluate(candidate, common_schedule(("mirror",), 1, 8765432))

        assert result.games == 4
        assert result.wins + result.draws + result.losses == 4
    finally:
        pool.close()
        store.close()
        bridge.close()


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_phase_six_cli_pilot_end_to_end(tmp_path):
    root = Path(__file__).resolve().parents[1]
    checkpoint_path = tmp_path / "policy.pt"
    model = ActorCritic(929, 128, 16)
    torch.save({"model": model.state_dict(), "config": {"model": {"hidden_dim": 16}}},
               checkpoint_path)
    config = {
        "seed": 17,
        "device": "cpu",
        "output_dir": "unused",
        "parallel": {"workers": 2, "batch_size": 4},
        "telemetry": {"action_sample_rate": 1.0},
        "evolution": {
            "population_size": 4,
            "elites": 1,
            "crossover_children": 1,
            "strong_mutations": 1,
            "random_immigrants": 1,
            "tournament_size": 2,
            "generations": 1,
        },
        "evaluation": {
            "short_games_per_side_order": 1,
            "medium_games_per_side_order": 1,
            "final_games_per_side_order": 1,
            "short_seed_base": 9100000,
            "medium_seed_base": 9200000,
            "final_seed_base": 9300000,
            "medium_finalists": 2,
            "final_finalists": 1,
        },
        "final_gate": {"minimum_win_rate": 0.0, "minimum_worst_matchup": 0.0},
        "opponents": [{
            "id": "mirror_inari",
            "god": "inari",
            "deck": env_config()["human_deck"],
        }],
    }
    config_path = tmp_path / "pilot.yaml"
    config_path.write_text(yaml.safe_dump(config), encoding="utf-8")
    output = tmp_path / "output"

    command = [sys.executable, str(root / "scripts" / "run_deck_evolution.py"),
               "inari", str(checkpoint_path), "--config", str(config_path),
               "--output", str(output), "--pilot"]
    completed = subprocess.run(
        command,
        cwd=root, capture_output=True, text=True, timeout=90, check=False)

    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert (output / "state_inari.json").is_file()
    assert (output / "matches.sqlite3").is_file()
    assert (output / "reports" / "phase6_inari.json").is_file()
    assert (output / "reports" / "phase6_gate_inari.json").is_file()
    with sqlite3.connect(output / "matches.sqlite3") as connection:
        match_count = int(connection.execute("SELECT COUNT(*) FROM matches").fetchone()[0])
        action_count = int(connection.execute("SELECT COUNT(*) FROM match_actions").fetchone()[0])
        assert action_count > match_count

    resumed = subprocess.run(
        command, cwd=root, capture_output=True, text=True, timeout=90, check=False)

    assert resumed.returncode == 0, resumed.stdout + resumed.stderr
    with sqlite3.connect(output / "matches.sqlite3") as connection:
        assert int(connection.execute("SELECT COUNT(*) FROM matches").fetchone()[0]) == match_count
        assert int(connection.execute("SELECT COUNT(*) FROM match_actions").fetchone()[0]) == action_count
    events = [json.loads(line) for line in (
        output / "monitoring" / "inari" / "metrics.jsonl").read_text(
        encoding="utf-8").splitlines() if line]
    assert {event["stream"] for event in events} >= {
        "deck_evolution/generation", "deck_evolution/medium", "deck_evolution/final"}
    balance = subprocess.run(
        [sys.executable, str(root / "scripts" / "generate_balance_report.py"),
         str(output / "matches.sqlite3"), "--output", str(output / "balance"),
         "--minimum-samples", "1"],
        cwd=root, capture_output=True, text=True, timeout=30, check=False)
    progress = subprocess.run(
        [sys.executable, str(root / "scripts" / "generate_training_report.py"),
         str(output / "monitoring" / "inari"), "--output", str(output / "progress")],
        cwd=root, capture_output=True, text=True, timeout=30, check=False)
    assert balance.returncode == 0, balance.stdout + balance.stderr
    assert progress.returncode == 0, progress.stdout + progress.stderr
    assert (output / "balance" / "balance_report.html").is_file()
    assert (output / "progress" / "training_report.html").is_file()


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_short_ppo_run_writes_metrics_evaluation_and_atomic_checkpoint(tmp_path):
    root = Path(__file__).resolve().parents[1]
    config = yaml.safe_load((root / "configs" / "ppo_phase4_tactical.yaml").read_text(
        encoding="utf-8"))
    config["output_dir"] = str(tmp_path / "ppo_run")
    config["environment"].update({"backend": "godot", "evaluation_backend": "godot"})
    config["environment"]["scenarios"] = config["environment"]["scenarios"][:1]
    config["ppo"].update({
        "total_timesteps": 16,
        "rollout_steps": 16,
        "num_envs": 1,
        "minibatches": 4,
        "update_epochs": 1,
    })
    config["evaluation"].update({"every_updates": 1, "games": 4, "num_envs": 1})
    config["monitoring"].update({
        "tensorboard": False,
        "checkpoint_every_updates": 1,
        "snapshot_every_updates": 0,
    })
    config_path = tmp_path / "ppo_smoke.yaml"
    config_path.write_text(yaml.safe_dump(config), encoding="utf-8")

    PPOTrainer(config_path).train()

    output = tmp_path / "ppo_run"
    events = [json.loads(line) for line in (output / "metrics.jsonl").read_text(
        encoding="utf-8").splitlines() if line]
    assert {event["stream"] for event in events} == {"training", "evaluation"}
    training = next(event for event in events if event["stream"] == "training")
    assert "normalized_entropy" in training["metrics"]
    assert "steps_per_second" in training["metrics"]
    assert (output / "latest.pt").is_file()
    assert not (output / "latest.pt.tmp").exists()
    manifest = json.loads((output / "run_manifest.json").read_text(encoding="utf-8"))
    assert manifest["extra"]["engine_manifest"]["protocol_version"] == 2


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_vectorized_ppo_collects_from_four_godot_environments(tmp_path):
    root = Path(__file__).resolve().parents[1]
    config = yaml.safe_load((root / "configs" / "ppo_phase4_tactical.yaml").read_text(
        encoding="utf-8"))
    config["output_dir"] = str(tmp_path / "ppo_vectorized_run")
    config["environment"].update({"backend": "godot", "evaluation_backend": "godot"})
    config["environment"]["scenarios"] = config["environment"]["scenarios"][:1]
    config["ppo"].update({
        "total_timesteps": 1024,
        "rollout_steps": 256,
        "num_envs": 4,
        "minibatches": 8,
        "update_epochs": 1,
    })
    config["evaluation"].update({"every_updates": 1, "games": 4, "num_envs": 1})
    config["monitoring"].update({
        "tensorboard": False,
        "checkpoint_every_updates": 1,
        "snapshot_every_updates": 0,
    })
    config_path = tmp_path / "ppo_vectorized_smoke.yaml"
    config_path.write_text(yaml.safe_dump(config), encoding="utf-8")

    PPOTrainer(config_path).train()

    output = tmp_path / "ppo_vectorized_run"
    events = [json.loads(line) for line in (output / "metrics.jsonl").read_text(
        encoding="utf-8").splitlines() if line]
    training = next(event for event in events if event["stream"] == "training")
    assert training["step"] == 1024
    assert training["metrics"]["environment_count"] == 4.0
    assert training["metrics"]["rollout_batch_size"] == 1024.0
    assert training["metrics"]["simulator_workers"] == 4.0
    assert training["metrics"]["steps_per_second"] > 0.0
    manifest = json.loads((output / "run_manifest.json").read_text(encoding="utf-8"))
    assert manifest["extra"]["environment_count"] == 4
    assert len(manifest["extra"]["worker_engine_checksums"]) == 4


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_fast_python_training_is_evaluated_by_vectorized_godot_oracles(tmp_path):
    root = Path(__file__).resolve().parents[1]
    config = yaml.safe_load((root / "configs" / "ppo_phase4_tactical.yaml").read_text(
        encoding="utf-8"))
    config["output_dir"] = str(tmp_path / "ppo_fast_run")
    config["environment"]["scenarios"] = config["environment"]["scenarios"][:2]
    config["ppo"].update({
        "total_timesteps": 256,
        "rollout_steps": 8,
        "num_envs": 32,
        "minibatches": 8,
        "update_epochs": 1,
    })
    config["evaluation"].update({
        "every_updates": 1,
        "games": 8,
        "num_envs": 4,
        "anchor_games_per_stage": 0,
    })
    config["monitoring"].update({
        "tensorboard": False,
        "checkpoint_every_updates": 1,
        "snapshot_every_updates": 0,
    })
    config_path = tmp_path / "ppo_fast_smoke.yaml"
    config_path.write_text(yaml.safe_dump(config), encoding="utf-8")

    PPOTrainer(config_path).train()

    output = tmp_path / "ppo_fast_run"
    events = [json.loads(line) for line in (output / "metrics.jsonl").read_text(
        encoding="utf-8").splitlines() if line]
    training = next(event for event in events if event["stream"] == "training")
    evaluation = next(event for event in events if event["stream"] == "evaluation")
    assert training["metrics"]["environment_count"] == 32.0
    assert training["metrics"]["rollout_batch_size"] == 256.0
    assert evaluation["metrics"]["games"] == 8
    assert evaluation["metrics"]["evaluation_seconds"] > 0.0
    manifest = json.loads((output / "run_manifest.json").read_text(encoding="utf-8"))
    assert manifest["extra"]["training_backend"] == "python_batch"
    assert manifest["extra"]["evaluation_backend"] == "godot"
    assert manifest["extra"]["engine_manifest"]["backend"] == "python_batch"


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_official_phase_four_config_runs_and_records_its_first_stage(tmp_path):
    root = Path(__file__).resolve().parents[1]
    config = yaml.safe_load((root / "configs" / "ppo_phase4_tactical.yaml").read_text(
        encoding="utf-8"))
    config["output_dir"] = str(tmp_path / "ppo_progressive_run")
    config["environment"]["scenarios"] = config["environment"]["scenarios"][:2]
    config["ppo"].update({
        "total_timesteps": 256,
        "rollout_steps": 8,
        "num_envs": 32,
        "minibatches": 8,
        "update_epochs": 1,
    })
    config["evaluation"].update({
        "every_updates": 1,
        "games": 8,
        "num_envs": 4,
        "anchor_games_per_stage": 0,
    })
    config["monitoring"].update({
        "tensorboard": False,
        "checkpoint_every_updates": 1,
        "snapshot_every_updates": 0,
    })
    config_path = tmp_path / "ppo_phase4_smoke.yaml"
    config_path.write_text(yaml.safe_dump(config), encoding="utf-8")

    trainer = PPOTrainer(config_path)
    assert trainer.curriculum.current.name == "precision_0"
    assert not trainer.curriculum.current.anticipation
    trainer.train()

    output = tmp_path / "ppo_progressive_run"
    events = [json.loads(line) for line in (output / "metrics.jsonl").read_text(
        encoding="utf-8").splitlines() if line]
    assert {event["context"]["stage"] for event in events} == {
        "precision_0"}
    checkpoint = torch.load(output / "latest.pt", map_location="cpu", weights_only=False)
    assert checkpoint["curriculum"]["stage_index"] == 0
    assert checkpoint["curriculum"]["current"]["anticipation"] is False


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_adaptive_god_sampling_is_logged_by_vectorized_ppo(tmp_path):
    root = Path(__file__).resolve().parents[1]
    config = yaml.safe_load((root / "configs" / "ppo_phase4_tactical.yaml").read_text(
        encoding="utf-8"))
    config["output_dir"] = str(tmp_path / "ppo_adaptive_run")
    config["environment"].update({"backend": "godot", "evaluation_backend": "godot"})
    config["environment"]["scenarios"] = config["environment"]["scenarios"][:2]
    config["ppo"].update({
        "total_timesteps": 1024,
        "rollout_steps": 256,
        "num_envs": 4,
        "minibatches": 8,
        "update_epochs": 1,
    })
    config["curriculum"]["god_sampling"] = {
        "enabled": True,
        "target_wilson": 0.90,
        "minimum_multiplier": 0.60,
        "maximum_multiplier": 2.20,
        "deficit_exponent": 1.0,
        "smoothing": 0.35,
    }
    config["curriculum"]["terrain_sampling"] = {
        "enabled": True,
        "blocked_counts": [0, 1, 2],
        "target_wilson": 0.90,
        "minimum_multiplier": 0.70,
        "maximum_multiplier": 1.80,
        "deficit_exponent": 1.0,
        "smoothing": 0.35,
        "max_reset_attempts": 12,
    }
    config["evaluation"].update({"every_updates": 1, "games": 4, "num_envs": 1})
    config["monitoring"].update({
        "tensorboard": False,
        "checkpoint_every_updates": 1,
        "snapshot_every_updates": 0,
    })
    config_path = tmp_path / "ppo_adaptive_smoke.yaml"
    config_path.write_text(yaml.safe_dump(config), encoding="utf-8")

    PPOTrainer(config_path).train()

    events = [json.loads(line) for line in (tmp_path / "ppo_adaptive_run" / "metrics.jsonl").read_text(
        encoding="utf-8").splitlines() if line]
    training = next(event for event in events if event["stream"] == "training")
    evaluation = next(event for event in events if event["stream"] == "evaluation")
    assert set(training["metrics"]["god_sampling"]["weights"]) == {"inari", "izanami"}
    assert "episodes" in training["metrics"]["god_sampling"]
    assert set(training["metrics"]["terrain_sampling"]["weights"]) == {"0", "1", "2"}
    assert "episodes" in training["metrics"]["terrain_sampling"]
    assert "god_sampling" in evaluation["metrics"]
    assert "terrain_sampling" in evaluation["metrics"]


def env_config():
    from samstone_rl.envs.samstone_env import DEFAULT_CONFIG
    return DEFAULT_CONFIG
