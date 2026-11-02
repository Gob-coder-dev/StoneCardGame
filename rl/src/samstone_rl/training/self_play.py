from __future__ import annotations

import hashlib
from pathlib import Path

import torch
import yaml

from samstone_rl.envs import RewardScheme, SamStoneEnv
from samstone_rl.observability import RunTracker, build_run_manifest
from samstone_rl.training.league import LeagueOpponent, SelfPlayLeague


class PhaseFiveNotReady(RuntimeError):
    pass


class SelfPlaySession:
    """Build the phase-5 environment only from a phase-4 validated checkpoint."""

    def __init__(self, config_path: str | Path, checkpoint_path: str | Path) -> None:
        self.config_path = Path(config_path).resolve()
        self.checkpoint_path = Path(checkpoint_path).resolve()
        with self.config_path.open(encoding="utf-8") as stream:
            self.config = yaml.safe_load(stream)
        settings = self.config["phase5"]
        checkpoint = torch.load(self.checkpoint_path, map_location="cpu", weights_only=False)
        if settings.get("require_validated_phase4", True) and not bool(
                checkpoint.get("curriculum", {}).get("completed", False)):
            raise PhaseFiveNotReady("le checkpoint n'a pas valide la garde finale de phase 4")
        self.weight_schedule = tuple(settings["weight_schedule"])
        directory = Path(settings["league_directory"])
        if not directory.is_absolute():
            directory = self.config_path.parent.parent / directory
        self.directory = directory
        self.league = SelfPlayLeague(directory, self.weight_schedule[0]["weights"],
                                     self.config.get("device", "cpu"))
        if not self.league.entries:
            step = int(checkpoint.get("global_step", 0))
            score = float(checkpoint.get("evaluation", {}).get("win_rate", 0.0))
            self.league.register(self.checkpoint_path, step, score, "current")
            self.league.register(self.checkpoint_path, step, score, "best")
        reward = self.config["environment"]["reward"]
        self.env = SamStoneEnv(
            godot_path=self.config["environment"].get("godot_path"),
            opponent=LeagueOpponent(self.league),
            reward_scheme=RewardScheme(
                capture=float(reward["capture"]),
                multi_capture=float(reward["multi_capture"]),
                terminal=float(reward["terminal"]),
                final_margin=float(reward.get("final_margin", 0.0)),
                final_margin_scale=float(reward.get("final_margin_scale", 5.0)),
                board_control_delta=float(reward.get("board_control_delta", 0.0)),
                board_control_delta_limit=int(reward.get("board_control_delta_limit", 4)),
            ),
        )
        self.tracker = RunTracker(
            directory, "self_play",
            tensorboard=bool(self.config.get("monitoring", {}).get("tensorboard", True)))
        self.tracker.initialize_manifest(build_run_manifest(
            "self_play", self.config, self.config_path, int(self.config["seed"]),
            checksums={"initial_policy": self._checksum(self.checkpoint_path)},
            extra={"checkpoint": str(self.checkpoint_path)}))

    def close(self) -> None:
        self.tracker.close()
        self.env.close()

    def set_training_update(self, update: int) -> None:
        selected = self.weight_schedule[-1]["weights"]
        for stage in self.weight_schedule:
            if update <= int(stage["until_update"]):
                selected = stage["weights"]
                break
        self.league.set_weights(selected)

    def record_episode(self, global_step: int, policy_id: str, episode: dict) -> dict:
        opponent = self.env.opponent
        if not isinstance(opponent, LeagueOpponent) or not opponent.selected_name:
            raise RuntimeError("aucun adversaire de ligue sélectionné pour cet épisode")
        score = 1.0 if bool(episode["won"]) else (0.5 if bool(episode["draw"]) else 0.0)
        rating = self.league.record_result(
            policy_id, opponent.selected_name, score, global_step,
            {"god": episode.get("god", ""), "opponent_god": episode.get("opponent_god", ""),
             "agent_player": episode.get("agent_player"),
             "first_player": episode.get("first_player")})
        metrics = {
            "score": score,
            "margin": float(episode["margin"]),
            "turns": float(episode["turns"]),
            "agent_captures": float(episode["agent_captures"]),
            "opponent_captures": float(episode["opponent_captures"]),
            **rating,
            "league": self.league.metrics_snapshot(),
        }
        self.tracker.log(
            "self_play/episode", global_step, metrics,
            {"policy_id": policy_id, "opponent_id": opponent.selected_name,
             "opponent_category": opponent.selected_category})
        return metrics

    @staticmethod
    def _checksum(path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        return digest.hexdigest()
