import hashlib
import json
import os
from pathlib import Path

import numpy as np
import pytest
import torch
import yaml

from samstone_rl.models.actor_critic import ActorCritic
from samstone_rl.opponents.baselines import GodotProfileOpponent
from samstone_rl.opponents.checkpoint import CheckpointOpponent
from samstone_rl.training.curriculum import DEFAULT_STAGES
from samstone_rl.training.league import LeagueOpponent, SelfPlayLeague
from samstone_rl.training.phase_five_gate import (
    GODS,
    MatchCount,
    PhaseFiveValidator,
    judge_phase_five,
)
from samstone_rl.training.ppo_self_play import PhaseFiveTrainer
from samstone_rl.training.self_play import PhaseFiveNotReady, SelfPlaySession


def _checkpoint(path: Path, completed: bool = True) -> None:
    model = ActorCritic(929, 128, 16)
    torch.save({"model": model.state_dict(), "global_step": 42,
                "evaluation": {"win_rate": 0.96},
                "config": {"model": {"hidden_dim": 16}},
                "curriculum": {"completed": completed}}, path)


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
    with pytest.raises(PhaseFiveNotReady, match="garde finale"):
        SelfPlaySession(config, checkpoint)
    with pytest.raises(ValueError, match="phase4_validated"):
        PhaseFiveTrainer(config, phase4_checkpoint=checkpoint)


def test_validated_checkpoint_activates_self_play_environment(tmp_path):
    checkpoint = tmp_path / "validated.pt"
    _checkpoint(checkpoint)
    source = Path(__file__).resolve().parents[1] / "configs" / "ppo_phase4_tactical.yaml"
    config_data = yaml.safe_load(source.read_text(encoding="utf-8"))
    config_data["phase5"]["league_directory"] = str(tmp_path / "league")
    config = tmp_path / "config.yaml"
    config.write_text(yaml.safe_dump(config_data), encoding="utf-8")
    session = SelfPlaySession(config, checkpoint)
    try:
        assert len(session.league.entries) == 2
        assert session.league.weights["godot"] == 0.80
        session.set_training_update(501)
        assert session.league.weights["godot"] == 0.25
        assert isinstance(session.env.opponent, LeagueOpponent)
        session.env.opponent.selected_name = session.league.entries[0].name
        session.env.opponent.selected_category = "current"
        metrics = session.record_episode(100, "policy_100", {
            "won": True, "draw": False, "margin": 4, "turns": 15,
            "agent_captures": 3, "opponent_captures": 1,
            "god": "veskar", "opponent_god": "veskar",
            "agent_player": 1, "first_player": 2,
        })
        assert metrics["agent_rating"] > 1500
        assert (tmp_path / "league" / "metrics.jsonl").is_file()
    finally:
        session.close()


def test_phase_five_trains_mixed_gods_against_frozen_checkpoint(tmp_path):
    source = tmp_path / "phase4_validated.pt"
    _checkpoint(source)
    config_data = yaml.safe_load((Path(__file__).resolve().parents[1]
                                  / "configs" / "ppo_self_play_v2.yaml").read_text(encoding="utf-8"))
    run = tmp_path / "run"
    config_data["output_dir"] = str(run)
    config_data["phase5"]["league_directory"] = str(run / "league")
    config_data["phase5"]["weight_schedule"][0]["weights"] = {
        "current": 1.0, "recent": 0.0, "historical": 0.0, "best": 0.0, "godot": 0.0}
    config_data["phase5"]["mirror_probability"] = 0.0
    config_data["phase5"]["snapshot_every_updates"] = 1
    config_data["model"]["hidden_dim"] = 16
    config_data["ppo"].update({"rollout_steps": 8, "num_envs": 2,
                                "minibatches": 2, "total_timesteps": 64})
    config_data["evaluation"]["every_updates"] = 100
    config_data["monitoring"]["tensorboard"] = False
    config = tmp_path / "phase5.yaml"
    config.write_text(yaml.safe_dump(config_data), encoding="utf-8")
    trainer = PhaseFiveTrainer(config, phase4_checkpoint=source)
    match = trainer._training_scenario_options(0, 1)["config"]
    assert match["human_god"] != match["ai_god"]
    trainer.train()
    checkpoint = torch.load(run / "latest.pt", map_location="cpu", weights_only=False)
    assert checkpoint["global_step"] == 64
    assert checkpoint["phase5"]["completed"] is False
    assert (run / "phase4_baseline.pt").is_file()
    assert len(trainer.league.entries) >= 3
    results = (run / "league" / "results.jsonl").read_text(encoding="utf-8")
    assert '"god": ' in results
    assert any(
        item["context"]["god"] != item["context"]["opponent_god"]
        for item in (json.loads(line) for line in results.splitlines()))
    resumed = PhaseFiveTrainer(config, resume=run / "latest.pt")
    try:
        assert resumed._resume_global_step == 64
        assert resumed.league.entries
    finally:
        resumed.tracker.close()
        resumed._close_training_envs()
    checkpoint["phase5"]["completed"] = True
    certified = run / "phase5_validated.pt"
    torch.save(checkpoint, certified)
    resumed = PhaseFiveTrainer(config, resume=certified)
    try:
        assert resumed._checkpoint_extra()["phase5"]["completed"] is False
    finally:
        resumed.tracker.close()
        resumed._close_training_envs()


def test_phase_five_gate_requires_complete_tournament_and_no_regression():
    settings = {"godot_games_per_slice": 1, "mixed_games_per_slice": 1,
                "maximum_stage_regression": 0.05, "maximum_god_regression": 0.08,
                "minimum_head_to_head_score": 0.52,
                "minimum_head_to_head_wilson": 0.49,
                "minimum_god_score": 0.45, "minimum_matchup_score": 0.30}
    godot = {}
    mixed = {"overall": MatchCount(144)}
    for stage in DEFAULT_STAGES:
        godot[f"stage:{stage.name}"] = MatchCount(24)
    for god in GODS:
        godot[f"god:{god}"] = MatchCount(20)
        mixed[f"god:{god}"] = MatchCount(24)
        for stage in DEFAULT_STAGES:
            for player in (1, 2):
                for first in (1, 2):
                    godot[f"slice:{stage.name}:{god}:{player}:{first}"] = MatchCount(1)
        for other in GODS:
            mixed[f"matchup:{god}:{other}"] = MatchCount(4)
            for player in (1, 2):
                for first in (1, 2):
                    mixed[f"slice:{god}:{other}:{player}:{first}"] = MatchCount(1)
    assert judge_phase_five(godot, godot, mixed, settings)["passed"]
    mixed.pop("slice:veskar:enigma:1:1")
    report = judge_phase_five(godot, godot, mixed, settings)
    assert not report["passed"]
    assert any("tranche mixte incomplete" in message for message in report["failures"])


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_phase_five_gate_plays_godot_and_mixed_match(tmp_path):
    run = tmp_path / "run"
    run.mkdir()
    baseline = run / "phase4_baseline.pt"
    _checkpoint(baseline)
    candidate = run / "latest.pt"
    payload = torch.load(baseline, map_location="cpu", weights_only=False)
    payload["phase5"] = {"initial_policy_checksum": hashlib.sha256(
        baseline.read_bytes()).hexdigest(), "completed": False}
    config_data = yaml.safe_load((Path(__file__).resolve().parents[1]
                                  / "configs" / "ppo_self_play_v2.yaml").read_text(encoding="utf-8"))
    config_data["output_dir"] = str(run)
    config_data["phase5"]["validation"]["minimum_updates"] = 0
    config_data["model"]["hidden_dim"] = 16
    payload["config"] = config_data
    torch.save(payload, candidate)
    config = tmp_path / "config.yaml"
    config.write_text(yaml.safe_dump(config_data), encoding="utf-8")
    validator = PhaseFiveValidator(config, candidate)
    try:
        first, second = validator.scenarios[:2]
        assert validator._play(validator.models["candidate"], GodotProfileOpponent(0.0),
                               first, first, 1, 1, 4567) in (-1, 0, 1)
        opponent = CheckpointOpponent(baseline)
        assert validator._play(validator.models["candidate"], opponent,
                               first, second, 2, 1, 4568) in (-1, 0, 1)
        target = validator.write_result({"passed": True, "failures": []})
        assert target.is_file()
        validated = torch.load(run / "phase5_validated.pt", map_location="cpu",
                               weights_only=False)
        assert validated["phase5"]["completed"]
        trainer_run = tmp_path / "trainer"
        config_data["output_dir"] = str(trainer_run)
        config_data["phase5"]["league_directory"] = str(trainer_run / "league")
        config_data["model"]["hidden_dim"] = 16
        config_data["ppo"].update({"rollout_steps": 8, "num_envs": 2,
                                    "minibatches": 2, "total_timesteps": 16})
        config_data["evaluation"].update({"games": 8, "num_envs": 4,
                                           "every_updates": 1})
        config_data["phase5"]["snapshot_every_updates"] = 1
        config_data["monitoring"]["tensorboard"] = False
        config.write_text(yaml.safe_dump(config_data), encoding="utf-8")
        trainer = PhaseFiveTrainer(config, phase4_checkpoint=baseline)
        try:
            outcomes = trainer._mixed_worker(
                trainer.evaluation_env, [(first, second, 1, 2, 7890)],
                CheckpointOpponent(trainer.phase4_baseline))
            assert len(outcomes) == 1
            assert outcomes[0][:2] == (first["god"], second["god"])
            assert 0.0 <= trainer._evaluation_score({
                "win_rate": 0.8, "mixed_vs_phase4": {"score": 0.55}}) <= 1.0
            mixed = trainer._evaluate_mixed()
            assert mixed["games"] == 144
            assert len(mixed["by_matchup"]) == 36
            assert all(item["games"] == 4 for item in mixed["by_matchup"].values())
            trainer.train()
            assert (trainer_run / "best.pt").is_file()
            events = [json.loads(line) for line in (
                trainer_run / "metrics.jsonl").read_text(encoding="utf-8").splitlines()]
            evaluation = next(item for item in events if item["stream"] == "evaluation")
            assert evaluation["metrics"]["mixed_vs_phase4"]["games"] == 144
            assert "selection_score" in evaluation["metrics"]
        finally:
            trainer.tracker.close()
            trainer._close_training_envs()
    finally:
        validator.env.close()
