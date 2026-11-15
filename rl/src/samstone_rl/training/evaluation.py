"""EvaluationMixin responsibilities for PPO trainers; no environment ownership."""

from __future__ import annotations

import json
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import numpy as np
import torch

from samstone_rl.bridge import GodotProtocolError
from samstone_rl.envs.samstone_env import SamStoneEnv
from samstone_rl.evaluation.tournament import run_tournament
from samstone_rl.training.validation import (
    EvaluationSlice,
    PhaseFourGateReport,
    wilson_lower,
)
from samstone_rl.utils.checkpoints import policy_checksum


class EvaluationMixin:
    def _evaluation_action_feature_args(self, info: dict[str, Any]) -> tuple[torch.Tensor, ...]:
        if not self.tactical_features_enabled:
            return ()
        features = np.asarray(info.get("action_features"), dtype=np.float32)
        expected = (self.env.action_space.n, self.tactical_feature_dim)
        if features.shape != expected:
            raise RuntimeError(
                f"features tactiques d'evaluation {features.shape}, attendues {expected}"
            )
        return (torch.as_tensor(features, dtype=torch.float32, device=self.device).unsqueeze(0),)

    def evaluate(self, seed_offset: int = 0) -> dict[str, Any]:
        evaluation = self.config["evaluation"]
        games, wins, draws = int(evaluation["games"]), 0, 0
        margins: list[float] = []
        turns: list[float] = []
        buckets: dict[str, dict[str, list[tuple[bool, bool, float]]]] = {
            "by_god": defaultdict(list),
            "by_agent_side": defaultdict(list),
            "by_start_order": defaultdict(list),
            "by_blocked_count": defaultdict(list),
        }
        chunks = [
            list(range(worker, games, self.evaluation_num_envs))
            for worker in range(self.evaluation_num_envs)
        ]
        if self.evaluation_num_envs == 1:
            completed = self._evaluate_offsets(
                self.evaluation_envs[0], chunks[0], int(evaluation["seed_base"]) + seed_offset
            )
        else:
            with ThreadPoolExecutor(max_workers=self.evaluation_num_envs) as executor:
                batches = executor.map(
                    lambda request: self._evaluate_offsets(*request),
                    zip(
                        self.evaluation_envs,
                        chunks,
                        [int(evaluation["seed_base"]) + seed_offset] * len(chunks),
                        strict=True,
                    ),
                )
                completed = [item for batch in batches for item in batch]
        for offset, agent_player, first_player, final_info in sorted(completed):
            winner = int(final_info["winner"])
            episode = final_info["episode"]
            margin = float(episode["margin"])
            outcome = (winner == agent_player, winner == 0, margin)
            wins += int(winner == agent_player)
            draws += int(winner == 0)
            margins.append(margin)
            turns.append(float(episode["turns"]))
            god = str(self.scenarios[offset % len(self.scenarios)]["god"])
            buckets["by_god"][god].append(outcome)
            buckets["by_agent_side"][f"player_{agent_player}"].append(outcome)
            order = "agent_first" if first_player == agent_player else "opponent_first"
            buckets["by_start_order"][order].append(outcome)
            buckets["by_blocked_count"][str(episode["blocked_count"])].append(outcome)
        result = {
            "wins": wins,
            "draws": draws,
            "losses": games - wins - draws,
            "games": games,
            "win_rate": wins / games,
            "wilson_lower": wilson_lower(wins, games),
            "loss_rate": (games - wins - draws) / games,
            "non_loss_rate": (wins + draws) / games,
            "non_loss_wilson_lower": wilson_lower(wins + draws, games),
            "mean_margin": float(np.mean(margins)),
            "mean_turns": float(np.mean(turns)),
            **{
                name: {key: self._outcome_stats(values) for key, values in group.items()}
                for name, group in buckets.items()
            },
        }
        result["anchors"] = self._evaluate_anchors(seed_offset)
        return result

    def _evaluate_offsets(
        self,
        env: SamStoneEnv,
        offsets: list[int],
        seed_base: int,
    ) -> list[tuple[int, int, int, dict[str, Any]]]:
        evaluation = self.config["evaluation"]
        max_attempts = int(evaluation.get("godot_retry_attempts", 2))
        if max_attempts <= 0:
            raise ValueError("evaluation.godot_retry_attempts doit être strictement positif")
        previous, previous_player = env.opponent, env.agent_player
        completed: list[tuple[int, int, int, dict[str, Any]]] = []
        try:
            for offset in offsets:
                cycle = (offset // max(1, len(self.scenarios))) % 4
                agent_player = 1 if cycle < 2 else 2
                first_player = 1 if cycle % 2 == 0 else 2
                info = self._evaluation_game_with_retry(
                    self.curriculum.current.opponent(),
                    offset % len(self.scenarios),
                    agent_player,
                    first_player,
                    seed_base + offset,
                    env,
                    max_attempts,
                )
                completed.append((offset, agent_player, first_player, info))
        finally:
            env.opponent, env.agent_player = previous, previous_player
        return completed

    def _evaluation_game_with_retry(
        self,
        opponent,
        scenario_index: int,
        agent_player: int,
        first_player: int,
        seed: int,
        env: SamStoneEnv,
        max_attempts: int,
    ) -> dict[str, Any]:
        """Restart one crashed Godot worker and replay its deterministic match."""
        failures: list[str] = []
        for attempt in range(1, max_attempts + 1):
            try:
                return self._evaluation_game(
                    opponent, scenario_index, agent_player, first_player, seed, env
                )
            except GodotProtocolError as exc:
                failures.append(str(exc))
                env.close()
                if attempt == max_attempts:
                    detail = "\n--- tentative suivante ---\n".join(failures)
                    raise GodotProtocolError(
                        f"évaluation Godot impossible après {max_attempts} tentatives "
                        f"(seed={seed}, scenario={scenario_index}).\n{detail}"
                    ) from exc
        raise AssertionError("boucle de reprise d'évaluation inaccessible")

    def _evaluate_anchors(self, seed_offset: int = 0) -> dict[str, dict[str, float | int]]:
        evaluation = self.config["evaluation"]
        games = int(evaluation.get("anchor_games_per_stage", 0))
        if games <= 0 or self.curriculum.stage_index <= 0:
            return {}
        base_seed = (
            int(evaluation.get("anchor_seed_base", int(evaluation["seed_base"]) + 50000000))
            + seed_offset
        )
        anchors: dict[str, dict[str, float | int]] = {}
        env = self.evaluation_env
        previous = env.opponent
        previous_player = env.agent_player
        try:
            for stage_index, stage in enumerate(
                self.curriculum.stages[: self.curriculum.stage_index]
            ):
                outcomes: list[tuple[bool, bool, float]] = []
                for offset in range(games):
                    cycle = (offset // max(1, len(self.scenarios))) % 4
                    agent_player = 1 if cycle < 2 else 2
                    first_player = 1 if cycle % 2 == 0 else 2
                    final_info = self._evaluation_game(
                        stage.opponent(),
                        offset % len(self.scenarios),
                        agent_player,
                        first_player,
                        base_seed + stage_index * 1000000 + offset,
                    )
                    episode = final_info["episode"]
                    winner = int(final_info["winner"])
                    outcomes.append((winner == agent_player, winner == 0, float(episode["margin"])))
                anchors[stage.name] = self._outcome_stats(outcomes)
        finally:
            env.opponent = previous
            env.agent_player = previous_player
        return anchors

    def run_final_gate(self) -> PhaseFourGateReport:
        if not self.curriculum.awaiting_final_validation:
            raise RuntimeError("le dernier palier doit etre battu avant la validation finale")
        settings = self.config["evaluation"]["final_gate"]
        games_per_slice = int(settings["games_per_slice"])
        seed = int(settings["seed_base"])
        if self.evaluation_backend != "godot":
            raise RuntimeError("la certification finale exige le moteur Godot")
        oracle = self._evaluation_manifest()
        cases = []
        for stage_index, stage in enumerate(self.curriculum.stages):
            for scenario_index, scenario in enumerate(self.scenarios):
                for agent_player in (1, 2):
                    for first_player in (1, 2):
                        for _game in range(games_per_slice):
                            cases.append(
                                {
                                    "stage": stage_index,
                                    "scenario": scenario_index,
                                    "agent": agent_player,
                                    "first": first_player,
                                    "seed": seed,
                                }
                            )
                            seed += 1

        def play(env, case):
            return self._evaluation_game_with_retry(
                self.curriculum.stages[case["stage"]].opponent(),
                case["scenario"],
                case["agent"],
                case["first"],
                case["seed"],
                env,
                int(self.config["evaluation"].get("godot_retry_attempts", 2)),
            )

        previous = [(env.opponent, env.agent_player) for env in self.evaluation_envs]
        try:
            outcomes = run_tournament(
                cases,
                self.evaluation_envs,
                play,
                self.output / "evaluations/phase4",
                {
                    "provenance": self.provenance,
                    "oracle": oracle,
                    "policy": policy_checksum(self.model),
                    "config": self.config,
                },
            )
        finally:
            for env, (opponent, player) in zip(self.evaluation_envs, previous, strict=True):
                env.opponent, env.agent_player = opponent, player
        groups = defaultdict(list)
        for case, info in zip(cases, outcomes, strict=True):
            groups[(case["stage"], case["scenario"], case["agent"], case["first"])].append(
                int(info["winner"])
            )
        slices = []
        for (stage_index, scenario_index, agent, first), winners in groups.items():
            wins, draws = winners.count(agent), winners.count(0)
            slices.append(
                EvaluationSlice(
                    self.curriculum.stages[stage_index].name,
                    str(self.scenarios[scenario_index]["god"]),
                    agent,
                    first,
                    wins,
                    draws,
                    len(winners) - wins - draws,
                )
            )
        report = PhaseFourGateReport.build(
            slices,
            (stage.name for stage in self.curriculum.stages),
            (str(scenario["god"]) for scenario in self.scenarios),
            overall_threshold=float(settings["overall_win_rate"]),
            confidence_floor=float(settings["confidence_floor"]),
            slice_floor=float(settings["minimum_slice_win_rate"]),
            minimum_games_per_slice=games_per_slice,
            maximum_loss_rate=self._optional_rate(settings, "maximum_loss_rate"),
            non_loss_confidence_floor=self._optional_rate(settings, "non_loss_confidence_floor"),
            maximum_slice_loss_rate=self._optional_rate(settings, "maximum_slice_loss_rate"),
        )
        self.curriculum.accept_final_validation(report.passed)
        gate_path = self.output / "phase4_gate.json"
        gate_temporary = gate_path.with_suffix(".json.tmp")
        gate_temporary.write_text(json.dumps(report.to_dict(), indent=2), encoding="utf-8")
        gate_temporary.replace(gate_path)
        return report

    @staticmethod
    def _optional_rate(settings: dict[str, Any], key: str) -> float | None:
        value = settings.get(key)
        return None if value is None else float(value)

    def _evaluation_game(
        self,
        opponent,
        scenario_index: int,
        agent_player: int,
        first_player: int,
        seed: int,
        env: SamStoneEnv | None = None,
        options_override: dict | None = None,
    ) -> dict:
        env = env or self.evaluation_env
        env.opponent = opponent
        env.agent_player = agent_player
        options = (
            options_override
            if options_override is not None
            else self._scenario_options(scenario_index, evaluation=True)
        )
        if options is not None:
            options["config"]["first_player"] = first_player
        obs, info = env.reset(seed=seed, options=options)
        done = False
        while not done:
            with torch.no_grad():
                feature_args = self._evaluation_action_feature_args(info)
                action_features = feature_args[0] if feature_args else None
                action, _, _ = self._act(
                    torch.as_tensor(obs, dtype=torch.float32, device=self.device).unsqueeze(0),
                    torch.as_tensor(
                        info["action_mask"], dtype=torch.bool, device=self.device
                    ).unsqueeze(0),
                    action_features,
                    True,
                )
            obs, _, terminated, truncated, info = env.step(int(action.item()))
            done = terminated or truncated
        return info

    def _evaluation_manifest(self) -> dict[str, Any]:
        if hasattr(self, "_oracle_manifest"):
            return self._oracle_manifest

        def inspect(env):
            env.bridge.start()
            return env.bridge.engine_manifest()

        with ThreadPoolExecutor(max_workers=self.evaluation_num_envs) as executor:
            manifests = list(executor.map(inspect, self.evaluation_envs))
        if any(item != manifests[0] for item in manifests):
            raise RuntimeError("les arbitres d'evaluation utilisent des moteurs differents")
        self._oracle_manifest = manifests[0]
        return self._oracle_manifest
