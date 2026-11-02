from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path
from typing import Any

import numpy as np
import torch
import yaml

from samstone_rl.envs import RewardScheme, SamStoneEnv
from samstone_rl.envs.action_space import ActionCodec
from samstone_rl.envs.observation import ObservationEncoder
from samstone_rl.fast_engine import StoneCatalog
from samstone_rl.models.actor_critic import ActorCritic
from samstone_rl.opponents import CheckpointOpponent, GodotProfileOpponent
from samstone_rl.training.validation import wilson_lower

from .roster import BOSS_GODS, BossRoster, file_checksum


def _stats(values: list[int]) -> dict[str, Any]:
    games = len(values)
    wins = values.count(1)
    draws = values.count(0)
    losses = values.count(-1)
    return {"games": games, "wins": wins, "draws": draws, "losses": losses,
            "win_rate": wins / games if games else 0.0,
            "score": (wins + 0.5 * draws) / games if games else 0.0,
            "win_wilson_lower": wilson_lower(wins, games)}


def judge_specialist(candidate: dict[str, Any], universal: dict[str, Any],
                     candidate_godot: dict[str, Any], universal_godot: dict[str, Any],
                     settings: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if candidate["overall"]["score"] < float(settings["minimum_overall_score"]):
        failures.append("score global contre la politique universelle insuffisant")
    if candidate["overall"]["win_wilson_lower"] < float(settings["minimum_wilson_win"]):
        failures.append("borne Wilson globale insuffisante")
    score_gain = candidate["overall"]["score"] - universal["overall"]["score"]
    if score_gain < float(settings.get("minimum_score_gain", 0.0)):
        failures.append(f"gain contre la politique universelle insuffisant: {score_gain:.3f}")
    for god_id in BOSS_GODS:
        result = candidate["by_matchup"].get(god_id)
        if result is None or result["score"] < float(settings["minimum_matchup_score"]):
            failures.append(f"matchup insuffisant contre {god_id}")
            continue
        baseline = universal["by_matchup"].get(god_id)
        if baseline is None:
            failures.append(f"reference universelle absente contre {god_id}")
            continue
        regression = baseline["score"] - result["score"]
        if regression > float(settings.get("maximum_matchup_regression", 1.0)):
            failures.append(f"regression du matchup {god_id}: {regression:.3f}")
    regression = universal_godot["win_rate"] - candidate_godot["win_rate"]
    if regression > float(settings["maximum_godot_regression"]):
        failures.append(f"regression contre le bot Godot: {regression:.3f}")
    if universal["overall"]["games"] != candidate["overall"]["games"]:
        failures.append("comparaison universelle incomplete")
    return not failures, failures


class BossSpecialistValidator:
    def __init__(self, config_path: str | Path, roster_path: str | Path,
                 god_id: str, checkpoint_path: str | Path,
                 godot_path: str | None = None) -> None:
        self.config_path = Path(config_path).resolve()
        self.config = yaml.safe_load(self.config_path.read_text(encoding="utf-8"))
        self.roster = BossRoster.load(roster_path)
        if self.roster.catalog_checksum != StoneCatalog().checksum:
            raise ValueError("les cartes ont change depuis la creation du registre")
        self.god_id = god_id
        self.deck = self.roster.deck(god_id)
        self.checkpoint_path = Path(checkpoint_path).resolve()
        root = Path(self.config["specialization"]["output_root"])
        if not root.is_absolute():
            root = self.config_path.parent.parent / root
        self.output = (root / god_id).resolve()
        if not self.checkpoint_path.is_relative_to(self.output):
            raise ValueError("checkpoint hors du run du dieu")
        self.checkpoint = self._load_verified(self.checkpoint_path)
        state = self.checkpoint.get("specialization", {})
        if state.get("god_id") != god_id or state.get("roster_checksum") != self.roster.checksum():
            raise ValueError("checkpoint et registre incompatibles")
        if int(self.checkpoint.get("update", 0)) < int(
                self.config["specialization"]["validation"]["minimum_updates"]):
            raise ValueError("entrainement specialise trop court")
        self.universal_path = self.output / "universal_baseline.pt"
        if (not self.universal_path.is_file()
                or file_checksum(self.universal_path) != state.get("universal_checksum")):
            raise ValueError("politique universelle absente ou modifiee")
        if state.get("universal_checksum") != self.roster.policy_checksum:
            raise ValueError("politique universelle differente du registre")
        self.universal = self._load_verified(self.universal_path)
        self.models = {"candidate": self._model(self.checkpoint),
                       "universal": self._model(self.universal)}
        reward = self.config["environment"]["reward"]
        self.env = SamStoneEnv(
            godot_path=godot_path or self.config["environment"].get("godot_path"),
            reward_scheme=RewardScheme(**reward), backend="godot")

    @staticmethod
    def _load_verified(path: Path) -> dict[str, Any]:
        sidecar = path.with_suffix(path.suffix + ".sha256")
        if sidecar.is_file() and sidecar.read_text(encoding="ascii").split()[0] != file_checksum(path):
            raise ValueError(f"checksum invalide: {path}")
        return torch.load(path, map_location="cpu", weights_only=False)

    @staticmethod
    def _model(checkpoint: dict[str, Any]) -> ActorCritic:
        model = ActorCritic(ObservationEncoder().get_obs_size(), ActionCodec().n_actions,
                            int(checkpoint["config"]["model"]["hidden_dim"]))
        model.load_state_dict(checkpoint["model"])
        model.eval()
        return model

    @staticmethod
    def _options(own, other, player: int, first: int) -> dict[str, Any]:
        if player == 1:
            config = {"human_god": own.god_id, "human_deck": list(own.stone_ids),
                      "ai_god": other.god_id, "ai_deck": list(other.stone_ids)}
        else:
            config = {"human_god": other.god_id, "human_deck": list(other.stone_ids),
                      "ai_god": own.god_id, "ai_deck": list(own.stone_ids)}
        config["first_player"] = first
        return {"config": config}

    def _play(self, model: ActorCritic, opponent, other, player: int,
              first: int, seed: int) -> int:
        self.env.opponent = opponent
        self.env.agent_player = player
        observation, info = self.env.reset(
            seed=seed, options=self._options(self.deck, other, player, first))
        while "episode" not in info:
            with torch.no_grad():
                action, _, _ = model.act(
                    torch.as_tensor(observation).unsqueeze(0),
                    torch.as_tensor(np.asarray(info["action_mask"]), dtype=torch.bool).unsqueeze(0),
                    deterministic=True)
            observation, _, _, _, info = self.env.step(int(action.item()))
        winner = int(info["winner"])
        return 1 if winner == player else (0 if winner == 0 else -1)

    def run(self) -> dict[str, Any]:
        settings = self.config["specialization"]["validation"]
        games = int(settings["games_per_slice"])
        base = int(settings["seed_base"])
        outcomes = {"candidate": defaultdict(list), "universal": defaultdict(list)}
        godot = {"candidate": [], "universal": []}
        universal_opponent = CheckpointOpponent(self.universal_path, deterministic=True)
        try:
            for other_index, other in enumerate(self.roster.decks):
                for player in (1, 2):
                    for first in (1, 2):
                        for offset in range(games):
                            seed = base + other_index * 10000 + player * 1000 + first * 100 + offset
                            for name in ("candidate", "universal"):
                                value = self._play(
                                    self.models[name], universal_opponent,
                                    other, player, first, seed)
                                outcomes[name][other.god_id].append(value)
            for player in (1, 2):
                for first in (1, 2):
                    for offset in range(games):
                        seed = base + 1000000 + player * 1000 + first * 100 + offset
                        for name in ("candidate", "universal"):
                            value = self._play(
                                self.models[name], GodotProfileOpponent(1.0, True),
                                self.deck, player, first, seed)
                            godot[name].append(value)
        finally:
            self.env.close()
        summaries = {}
        for name, grouped in outcomes.items():
            flat = [value for items in grouped.values() for value in items]
            summaries[name] = {"overall": _stats(flat),
                               "by_matchup": {key: _stats(values)
                                              for key, values in grouped.items()}}
        godot_stats = {name: _stats(values) for name, values in godot.items()}
        passed, failures = judge_specialist(
            summaries["candidate"], summaries["universal"],
            godot_stats["candidate"], godot_stats["universal"], settings)
        return {"schema_version": 1, "god_id": self.god_id, "passed": passed,
                "failures": failures, "criteria": settings,
                "candidate": summaries["candidate"],
                "universal": summaries["universal"],
                "candidate_vs_godot": godot_stats["candidate"],
                "universal_vs_godot": godot_stats["universal"],
                "candidate_checksum": file_checksum(self.checkpoint_path),
                "roster_checksum": self.roster.checksum(),
                "universal_checksum": file_checksum(self.universal_path)}

    def write(self, report: dict[str, Any]) -> Path:
        report_path = self.output / f"boss_gate_{self.god_id}.json"
        temporary = report_path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(report, indent=2), encoding="utf-8")
        temporary.replace(report_path)
        if report["passed"]:
            target = self.output / f"boss_{self.god_id}_validated.pt"
            payload = dict(self.checkpoint)
            payload["specialization"] = {
                **payload["specialization"], "completed": True,
                "gate_report": report_path.name,
                "source_checkpoint_checksum": report["candidate_checksum"]}
            temp_checkpoint = target.with_suffix(".pt.tmp")
            torch.save(payload, temp_checkpoint)
            temp_checkpoint.replace(target)
            checksum = file_checksum(target)
            checksum_path = target.with_suffix(".pt.sha256")
            checksum_temp = checksum_path.with_suffix(".sha256.tmp")
            checksum_temp.write_text(f"{checksum}  {target.name}\n", encoding="ascii")
            checksum_temp.replace(checksum_path)
        return report_path


def validate_boss_roster(root: str | Path, roster_path: str | Path) -> dict[str, Any]:
    directory = Path(root).resolve()
    roster = BossRoster.load(roster_path)
    failures: list[str] = []
    checkpoints: dict[str, str] = {}
    bosses: dict[str, dict[str, Any]] = {}
    for god_id in BOSS_GODS:
        path = directory / god_id / f"boss_{god_id}_validated.pt"
        if not path.is_file():
            failures.append(f"checkpoint absent: {god_id}")
            continue
        payload = torch.load(path, map_location="cpu", weights_only=False)
        state = payload.get("specialization", {})
        if (not state.get("completed") or state.get("god_id") != god_id
                or state.get("roster_checksum") != roster.checksum()
                or state.get("universal_checksum") != roster.policy_checksum):
            failures.append(f"checkpoint incompatible: {god_id}")
        report_path = path.parent / str(state.get("gate_report", ""))
        if not report_path.is_file():
            failures.append(f"rapport de validation absent: {god_id}")
        else:
            report = json.loads(report_path.read_text(encoding="utf-8"))
            if (not report.get("passed") or report.get("god_id") != god_id
                    or report.get("roster_checksum") != roster.checksum()
                    or report.get("universal_checksum") != roster.policy_checksum
                    or report.get("candidate_checksum")
                    != state.get("source_checkpoint_checksum")):
                failures.append(f"rapport de validation incompatible: {god_id}")
            candidate = report.get("candidate", {}).get("overall", {})
            godot = report.get("candidate_vs_godot", {})
            matchup_scores = [float(item.get("score", 0.0)) for item in
                              report.get("candidate", {}).get("by_matchup", {}).values()]
            bosses[god_id] = {
                "score_vs_universal": float(candidate.get("score", 0.0)),
                "win_rate_vs_universal": float(candidate.get("win_rate", 0.0)),
                "godot_win_rate": float(godot.get("win_rate", 0.0)),
                "worst_matchup_score": min(matchup_scores) if matchup_scores else 0.0,
            }
        checkpoints[god_id] = file_checksum(path)
    strength_ranking = sorted(bosses, key=lambda god_id: (
        -bosses[god_id]["score_vs_universal"],
        -bosses[god_id]["godot_win_rate"], god_id))
    report = {"schema_version": 1, "passed": not failures, "failures": failures,
              "roster_checksum": roster.checksum(), "checkpoints": checkpoints,
              "bosses": bosses, "strength_ranking": strength_ranking}
    target = directory / "boss_roster_gate.json"
    temporary = target.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(report, indent=2), encoding="utf-8")
    temporary.replace(target)
    return report
