import json
import os
from pathlib import Path

import pytest
import torch
import yaml

from samstone_rl.models.actor_critic import ActorCritic
from samstone_rl.opponents import CheckpointOpponent
from samstone_rl.specialization import BOSS_GODS, BossRoster, build_boss_roster
from samstone_rl.specialization.gate import (
    BossSpecialistValidator,
    judge_specialist,
    validate_boss_roster,
)
from samstone_rl.specialization.roster import file_checksum
from samstone_rl.specialization.trainer import BossSpecialistTrainer


def _validated_phase5(path: Path, hidden: int = 16) -> None:
    model = ActorCritic(929, 128, hidden)
    torch.save({"model": model.state_dict(), "global_step": 100, "update": 10,
                "config": {"model": {"hidden_dim": hidden}},
                "curriculum": {"stage_index": 4, "completed": True,
                               "awaiting_final_validation": False},
                "phase5": {"completed": True}}, path)


def _build_roster(tmp_path: Path, checkpoint: Path) -> BossRoster:
    reports = tmp_path / "reports"
    reports.mkdir()
    scenarios = yaml.safe_load((Path(__file__).resolve().parents[1]
                                / "configs" / "ppo_self_play_v2.yaml").read_text(
                                    encoding="utf-8"))["environment"]["scenarios"]
    from samstone_rl.fast_engine import StoneCatalog
    for scenario in scenarios:
        payload = {"version": 1, "god_id": scenario["god"], "official": True,
                   "passed": True, "catalog_checksum": StoneCatalog().checksum,
                   "policy_checksum": file_checksum(checkpoint),
                   "finalists": [{"deck_hash": f"hash-{scenario['god']}",
                                   "stone_ids": scenario["deck"], "win_rate": 0.6,
                                   "worst_matchup_win_rate": 0.45, "fitness": 0.55}]}
        (reports / f"phase6_gate_{scenario['god']}.json").write_text(
            json.dumps(payload), encoding="utf-8")
    return build_boss_roster(reports, checkpoint, tmp_path / "boss_roster.json")


def test_roster_requires_six_official_consistent_reports(tmp_path):
    checkpoint = tmp_path / "phase5_validated.pt"
    _validated_phase5(checkpoint)
    roster = _build_roster(tmp_path, checkpoint)
    assert tuple(item.god_id for item in roster.decks) == BOSS_GODS
    assert BossRoster.load(tmp_path / "boss_roster.json").checksum() == roster.checksum()
    payload = json.loads((tmp_path / "reports" / "phase6_gate_veskar.json").read_text())
    payload["official"] = False
    (tmp_path / "reports" / "phase6_gate_veskar.json").write_text(json.dumps(payload))
    with pytest.raises(ValueError, match="non officiel"):
        build_boss_roster(tmp_path / "reports", checkpoint, tmp_path / "bad.json")


def test_specialist_trainer_uses_fixed_god_and_final_deck_and_resumes(tmp_path):
    universal = tmp_path / "phase5_validated.pt"
    _validated_phase5(universal)
    roster = _build_roster(tmp_path, universal)
    config = yaml.safe_load((Path(__file__).resolve().parents[1]
                             / "configs" / "boss_specialization.yaml").read_text(
                                 encoding="utf-8"))
    config["specialization"]["output_root"] = str(tmp_path / "runs")
    config["specialization"]["snapshot_every_updates"] = 1
    config["model"]["hidden_dim"] = 16
    config["ppo"].update({"total_timesteps": 64, "rollout_steps": 8,
                          "num_envs": 2, "minibatches": 2})
    config["evaluation"]["every_updates"] = 100
    config["monitoring"]["tensorboard"] = False
    config_path = tmp_path / "boss.yaml"
    config_path.write_text(yaml.safe_dump(config), encoding="utf-8")
    trainer = BossSpecialistTrainer(
        config_path, "veskar", tmp_path / "boss_roster.json",
        universal_checkpoint=universal)
    assert trainer.scenarios == [{"god": "veskar", "deck": list(roster.deck("veskar").stone_ids)}]
    for player in (1, 2):
        options = trainer._training_scenario_options(0, player)["config"]
        own_key = "human_god" if player == 1 else "ai_god"
        assert options[own_key] == "veskar"
    trainer.train()
    run = tmp_path / "runs" / "veskar"
    checkpoint = torch.load(run / "latest.pt", map_location="cpu", weights_only=False)
    assert checkpoint["specialization"]["god_id"] == "veskar"
    assert checkpoint["specialization"]["completed"] is False
    resumed = BossSpecialistTrainer(
        config_path, "veskar", tmp_path / "boss_roster.json", resume=run / "latest.pt")
    try:
        assert resumed._resume_global_step == 64
    finally:
        resumed.tracker.close()
        resumed._close_training_envs()


def test_specialist_gate_and_global_roster_gate(tmp_path):
    settings = {"minimum_overall_score": 0.52, "minimum_wilson_win": 0.40,
                "minimum_matchup_score": 0.40, "maximum_godot_regression": 0.06,
                "minimum_score_gain": 0.01, "maximum_matchup_regression": 0.05}
    matchup = {god: {"games": 100, "score": 0.55} for god in BOSS_GODS}
    candidate = {"overall": {"games": 600, "score": 0.56,
                              "win_wilson_lower": 0.50}, "by_matchup": matchup}
    universal = {"overall": {"games": 600, "score": 0.50},
                 "by_matchup": {god: {"games": 100, "score": 0.50}
                                  for god in BOSS_GODS}}
    assert judge_specialist(candidate, universal, {"win_rate": 0.80},
                            {"win_rate": 0.82}, settings)[0]
    matchup["enigma"] = {"games": 100, "score": 0.30}
    assert not judge_specialist(candidate, universal, {"win_rate": 0.80},
                                {"win_rate": 0.82}, settings)[0]
    matchup["enigma"] = {"games": 100, "score": 0.55}
    candidate["overall"]["score"] = 0.505
    assert not judge_specialist(candidate, universal, {"win_rate": 0.80},
                                {"win_rate": 0.82}, settings)[0]

    universal_path = tmp_path / "phase5_validated.pt"
    _validated_phase5(universal_path)
    roster = _build_roster(tmp_path, universal_path)
    root = tmp_path / "bosses"
    for god_id in BOSS_GODS:
        directory = root / god_id
        directory.mkdir(parents=True)
        model = ActorCritic(929, 128, 16)
        source_checksum = f"source-{god_id}"
        report_name = f"boss_gate_{god_id}.json"
        (directory / report_name).write_text(json.dumps({
            "passed": True, "god_id": god_id,
            "roster_checksum": roster.checksum(),
            "universal_checksum": roster.policy_checksum,
            "candidate_checksum": source_checksum,
            "candidate": {
                "overall": {"score": 0.55, "win_rate": 0.52},
                "by_matchup": {other: {"score": 0.5} for other in BOSS_GODS}},
            "candidate_vs_godot": {"win_rate": 0.8},
        }), encoding="utf-8")
        torch.save({"model": model.state_dict(), "specialization": {
            "completed": True, "god_id": god_id, "roster_checksum": roster.checksum(),
            "universal_checksum": roster.policy_checksum,
            "gate_report": report_name,
            "source_checkpoint_checksum": source_checksum}},
            directory / f"boss_{god_id}_validated.pt")
    report = validate_boss_roster(root, tmp_path / "boss_roster.json")
    assert report["passed"]
    assert set(report["strength_ranking"]) == set(BOSS_GODS)


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_specialist_validator_plays_a_real_godot_match(tmp_path):
    universal = tmp_path / "phase5_validated.pt"
    _validated_phase5(universal)
    roster = _build_roster(tmp_path, universal)
    config = yaml.safe_load((Path(__file__).resolve().parents[1]
                             / "configs" / "boss_specialization.yaml").read_text(
                                 encoding="utf-8"))
    config["specialization"]["output_root"] = str(tmp_path / "runs")
    config["specialization"]["validation"]["minimum_updates"] = 0
    config["model"]["hidden_dim"] = 16
    config["monitoring"]["tensorboard"] = False
    config_path = tmp_path / "boss.yaml"
    config_path.write_text(yaml.safe_dump(config), encoding="utf-8")
    trainer = BossSpecialistTrainer(
        config_path, "veskar", tmp_path / "boss_roster.json",
        universal_checkpoint=universal)
    trainer.tracker.close()
    trainer._close_training_envs()
    checkpoint = tmp_path / "runs" / "veskar" / "latest.pt"
    validator = BossSpecialistValidator(
        config_path, tmp_path / "boss_roster.json", "veskar", checkpoint)
    try:
        value = validator._play(
            validator.models["candidate"],
            CheckpointOpponent(validator.universal_path, deterministic=True),
            roster.deck("nerava"), 1, 1, 123456)
        assert value in (-1, 0, 1)
    finally:
        validator.env.close()
