from __future__ import annotations

import hashlib
import json
from collections import defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import numpy as np
import torch
import yaml

from samstone_rl.envs.action_space import ActionCodec
from samstone_rl.envs.observation import ObservationEncoder
from samstone_rl.envs.samstone_env import RewardScheme, SamStoneEnv
from samstone_rl.fast_engine import StoneCatalog
from samstone_rl.models.actor_critic import ActorCritic
from samstone_rl.opponents.checkpoint import CheckpointOpponent
from samstone_rl.training.curriculum import DEFAULT_STAGES
from samstone_rl.training.validation import wilson_lower

GODS = ("inari", "izanami", "hachiman", "tsukuyomi", "okuninushi", "susanoo")


@dataclass(frozen=True)
class MatchCount:
    wins: int = 0
    draws: int = 0
    losses: int = 0

    @property
    def games(self) -> int:
        return self.wins + self.draws + self.losses

    @property
    def win_rate(self) -> float:
        return self.wins / self.games if self.games else 0.0

    @property
    def score(self) -> float:
        return (self.wins + 0.5 * self.draws) / self.games if self.games else 0.0

    def to_dict(self) -> dict[str, Any]:
        return {**asdict(self), "games": self.games, "win_rate": self.win_rate,
                "score": self.score, "win_wilson_lower": wilson_lower(self.wins, self.games)}


def summarize_outcomes(outcomes: list[int]) -> MatchCount:
    return MatchCount(outcomes.count(1), outcomes.count(0), outcomes.count(-1))


def judge_phase_five(candidate: dict[str, MatchCount], baseline: dict[str, MatchCount],
                     mixed: dict[str, MatchCount], settings: dict[str, Any]) -> dict[str, Any]:
    """Check held-out Godot retention and mixed-god play against phase 4."""
    failures: list[str] = []
    stages = [stage.name for stage in DEFAULT_STAGES]
    gods = GODS
    for stage in stages:
        key = f"stage:{stage}"
        if key not in candidate or key not in baseline or not candidate[key].games:
            failures.append(f"evaluation Godot absente: {key}")
            continue
        gap = baseline[key].win_rate - candidate[key].win_rate
        if gap > float(settings["maximum_stage_regression"]):
            failures.append(f"regression Godot {stage}: {gap:.3f}")
    for god in gods:
        key = f"god:{god}"
        if key not in baseline or not candidate[key].games:
            failures.append(f"evaluation Godot absente: {key}")
        elif baseline[key].win_rate - candidate[key].win_rate > float(
                settings["maximum_god_regression"]):
            failures.append(f"regression Godot {god}")
        for stage in stages:
            for player in (1, 2):
                for first in (1, 2):
                    slice_key = f"slice:{stage}:{god}:{player}:{first}"
                    expected_games = int(settings["godot_games_per_slice"])
                    if (candidate.get(slice_key, MatchCount()).games != expected_games
                            or baseline.get(slice_key, MatchCount()).games != expected_games):
                        failures.append(f"tranche Godot incomplete: {slice_key}")
    total = mixed.get("overall", MatchCount())
    if not total.games:
        failures.append("tournoi mixte absent")
    else:
        if total.score < float(settings["minimum_head_to_head_score"]):
            failures.append(f"score contre phase 4 trop faible: {total.score:.3f}")
        if wilson_lower(total.wins, total.games) < float(
                settings["minimum_head_to_head_wilson"]):
            failures.append("borne Wilson des victoires contre phase 4 trop faible")
    for god in gods:
        key = f"god:{god}"
        outcome = mixed.get(key, MatchCount())
        if not outcome.games or outcome.score < float(settings["minimum_god_score"]):
            failures.append(f"score mixte insuffisant pour {god}")
        for opposing_god in gods:
            matchup = mixed.get(f"matchup:{god}:{opposing_god}", MatchCount())
            if (not matchup.games
                    or matchup.score < float(settings["minimum_matchup_score"])):
                failures.append(f"matchup insuffisant: {god} contre {opposing_god}")
            for player in (1, 2):
                for first in (1, 2):
                    slice_key = f"slice:{god}:{opposing_god}:{player}:{first}"
                    if mixed.get(slice_key, MatchCount()).games != int(
                            settings["mixed_games_per_slice"]):
                        failures.append(f"tranche mixte incomplete: {slice_key}")
    return {"schema_version": 1, "passed": not failures, "failures": failures,
            "criteria": settings,
            "godot_candidate": {key: value.to_dict() for key, value in candidate.items()},
            "godot_phase4": {key: value.to_dict() for key, value in baseline.items()},
            "mixed_vs_phase4": {key: value.to_dict() for key, value in mixed.items()}}


class PhaseFiveValidator:
    """Run the final held-out tournament in the authoritative Godot engine."""

    def __init__(self, config_path: str | Path, checkpoint_path: str | Path,
                 godot_path: str | None = None) -> None:
        self.config_path = Path(config_path).resolve()
        self.checkpoint_path = Path(checkpoint_path).resolve()
        self.config = yaml.safe_load(self.config_path.read_text(encoding="utf-8"))
        self.output = (self.config_path.parent.parent / self.config["output_dir"]).resolve()
        manifest = self.output / "run_manifest.json"
        if manifest.is_file():
            expected_catalog = json.loads(manifest.read_text(encoding="utf-8")).get(
                "checksums", {}).get("catalog")
            if expected_catalog and expected_catalog != StoneCatalog().checksum:
                raise ValueError("les cartes ont change depuis le run de phase 5")
        if not self.checkpoint_path.is_relative_to(self.output):
            raise ValueError("checkpoint de phase 5 hors du dossier de run")
        self.phase4_baseline = self.output / "phase4_baseline.pt"
        if not self.phase4_baseline.is_file():
            raise FileNotFoundError(self.phase4_baseline)
        self._verify_checksum(self.checkpoint_path)
        self.checkpoint = torch.load(self.checkpoint_path, map_location="cpu", weights_only=False)
        if self.checkpoint.get("config") != self.config:
            raise ValueError("la configuration ne correspond pas au checkpoint de phase 5")
        expected = self.checkpoint.get("phase5", {}).get("initial_policy_checksum")
        if not expected or expected != self._checksum(self.phase4_baseline):
            raise ValueError("le checkpoint ne correspond pas a la politique initiale")
        baseline = torch.load(self.phase4_baseline, map_location="cpu", weights_only=False)
        if not baseline.get("curriculum", {}).get("completed"):
            raise ValueError("la politique initiale n'a pas valide la phase 4")
        self.scenarios = self.config["environment"]["scenarios"]
        if {item["god"] for item in self.scenarios} != set(GODS):
            raise ValueError("la garde de phase 5 exige six dieux")
        settings = self.config["phase5"]["validation"]
        if int(self.checkpoint.get("update", 0)) < int(settings.get("minimum_updates", 0)):
            raise ValueError("phase 5 trop courte pour la validation finale")
        if min(int(settings["godot_games_per_slice"]),
               int(settings["mixed_games_per_slice"])) <= 0:
            raise ValueError("nombre de matchs de validation invalide")
        self.settings = settings
        self.models = {
            "candidate": self._model(self.checkpoint),
            "phase4": self._model(baseline),
        }
        reward = self.config["environment"]["reward"]
        self.env = SamStoneEnv(
            godot_path=godot_path or self.config["environment"].get("godot_path"),
            reward_scheme=RewardScheme(**reward), backend="godot")

    @staticmethod
    def _model(checkpoint: dict) -> ActorCritic:
        dimension = int(checkpoint["config"]["model"]["hidden_dim"])
        model = ActorCritic(ObservationEncoder().get_obs_size(),
                            ActionCodec().n_actions, dimension)
        model.load_state_dict(checkpoint["model"])
        model.eval()
        return model

    @staticmethod
    def _checksum(path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        return digest.hexdigest()

    @classmethod
    def _verify_checksum(cls, path: Path) -> None:
        sidecar = path.with_suffix(path.suffix + ".sha256")
        if sidecar.is_file() and sidecar.read_text(encoding="ascii").split()[0] != cls._checksum(path):
            raise ValueError(f"checksum invalide: {path}")

    @staticmethod
    def _options(own: dict, other: dict, player: int, first: int) -> dict:
        if player == 1:
            config = {"human_god": own["god"], "human_deck": list(own["deck"]),
                      "ai_god": other["god"], "ai_deck": list(other["deck"])}
        else:
            config = {"human_god": other["god"], "human_deck": list(other["deck"]),
                      "ai_god": own["god"], "ai_deck": list(own["deck"])}
        config["first_player"] = first
        return {"config": config}

    def _play(self, model: ActorCritic, opponent: Any, own: dict, other: dict,
              player: int, first: int, seed: int) -> int:
        self.env.opponent = opponent
        self.env.agent_player = player
        observation, info = self.env.reset(
            seed=seed, options=self._options(own, other, player, first))
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
        godot: dict[str, dict[str, list[int]]] = {
            "candidate": defaultdict(list), "phase4": defaultdict(list)}
        mixed: dict[str, list[int]] = defaultdict(list)
        try:
            games = int(self.settings["godot_games_per_slice"])
            base_seed = int(self.settings["godot_seed_base"])
            for stage_index, stage in enumerate(DEFAULT_STAGES):
                for god_index, scenario in enumerate(self.scenarios):
                    for player in (1, 2):
                        for first in (1, 2):
                            for offset in range(games):
                                seed = (base_seed + stage_index * 1000000
                                        + god_index * 10000 + player * 1000 + first * 100
                                        + offset)
                                for name in ("candidate", "phase4"):
                                    result = self._play(
                                        self.models[name], stage.opponent(), scenario,
                                        scenario, player, first, seed)
                                    godot[name][f"stage:{stage.name}"].append(result)
                                    godot[name][f"god:{scenario['god']}"].append(result)
                                    godot[name][
                                        f"slice:{stage.name}:{scenario['god']}:{player}:{first}"
                                    ].append(result)
                print(f"Godot: {stage.name} termine contre six dieux (candidat et phase 4)", flush=True)
            games = int(self.settings["mixed_games_per_slice"])
            base_seed = int(self.settings["mixed_seed_base"])
            opponent = CheckpointOpponent(self.phase4_baseline, deterministic=True)
            for own_index, own in enumerate(self.scenarios):
                for opposing_index, other in enumerate(self.scenarios):
                    for player in (1, 2):
                        for first in (1, 2):
                            for offset in range(games):
                                seed = (base_seed + own_index * 1000000
                                        + opposing_index * 10000 + player * 1000
                                        + first * 100 + offset)
                                result = self._play(
                                    self.models["candidate"], opponent, own, other,
                                    player, first, seed)
                                mixed["overall"].append(result)
                                mixed[f"god:{own['god']}"].append(result)
                                mixed[f"matchup:{own['god']}:{other['god']}"].append(result)
                                mixed[f"slice:{own['god']}:{other['god']}:{player}:{first}"].append(result)
                print(f"Tournoi mixte: {own['god']} contre six dieux", flush=True)
        finally:
            self.env.close()
        return judge_phase_five(
            {key: summarize_outcomes(value) for key, value in godot["candidate"].items()},
            {key: summarize_outcomes(value) for key, value in godot["phase4"].items()},
            {key: summarize_outcomes(value) for key, value in mixed.items()},
            self.settings)

    def write_result(self, report: dict[str, Any]) -> Path:
        path = self.output / "phase5_gate.json"
        temporary = path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(report, indent=2), encoding="utf-8")
        temporary.replace(path)
        if report["passed"]:
            target = self.output / "phase5_validated.pt"
            payload = dict(self.checkpoint)
            payload["phase5"] = {**payload["phase5"], "completed": True,
                                 "gate_report": str(path)}
            temporary_checkpoint = target.with_suffix(".pt.tmp")
            torch.save(payload, temporary_checkpoint)
            temporary_checkpoint.replace(target)
            checksum = self._checksum(target)
            checksum_path = target.with_suffix(".pt.sha256")
            checksum_temp = checksum_path.with_suffix(".sha256.tmp")
            checksum_temp.write_text(f"{checksum}  {target.name}\n", encoding="ascii")
            checksum_temp.replace(checksum_path)
        return path
