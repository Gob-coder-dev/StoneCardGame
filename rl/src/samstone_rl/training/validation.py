from __future__ import annotations

import math
from collections.abc import Iterable
from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class EvaluationSlice:
    stage: str
    god: str
    agent_player: int
    first_player: int
    wins: int
    draws: int
    losses: int

    @property
    def games(self) -> int:
        return self.wins + self.draws + self.losses

    @property
    def win_rate(self) -> float:
        return self.wins / self.games if self.games else 0.0

    @property
    def loss_rate(self) -> float:
        return self.losses / self.games if self.games else 1.0

    @property
    def non_loss_rate(self) -> float:
        return (self.wins + self.draws) / self.games if self.games else 0.0


@dataclass(frozen=True)
class StageResult:
    stage: str
    wins: int
    draws: int
    losses: int
    win_rate: float
    wilson_lower: float
    loss_rate: float
    non_loss_rate: float
    non_loss_wilson_lower: float
    passed: bool


@dataclass(frozen=True)
class PhaseFourGateReport:
    passed: bool
    overall_threshold: float
    confidence_floor: float
    slice_floor: float
    maximum_loss_rate: float | None
    non_loss_confidence_floor: float | None
    maximum_slice_loss_rate: float | None
    minimum_games_per_slice: int
    missing_stages: tuple[str, ...]
    missing_slices: tuple[str, ...]
    failed_slices: tuple[str, ...]
    stages: tuple[StageResult, ...]
    slices: tuple[EvaluationSlice, ...]

    @classmethod
    def build(cls, slices: Iterable[EvaluationSlice], expected_stages: Iterable[str],
              expected_gods: Iterable[str],
              overall_threshold: float = 0.95, confidence_floor: float = 0.90,
              slice_floor: float = 0.90, minimum_games_per_slice: int = 100,
              maximum_loss_rate: float | None = None,
              non_loss_confidence_floor: float | None = None,
              maximum_slice_loss_rate: float | None = None) -> PhaseFourGateReport:
        collected = tuple(slices)
        expected = tuple(expected_stages)
        gods = tuple(expected_gods)
        present = {item.stage for item in collected}
        missing = tuple(stage for stage in expected if stage not in present)
        present_slices = {(item.stage, item.god, item.agent_player, item.first_player) for item in collected}
        expected_slices = ((stage, god, agent, first) for stage in expected for god in gods
                           for agent in (1, 2) for first in (1, 2))
        missing_slices = tuple(
            f"{stage}:{god}:agent{agent}:first{first}"
            for stage, god, agent, first in expected_slices
            if (stage, god, agent, first) not in present_slices
        )
        stage_results: list[StageResult] = []
        for stage in expected:
            relevant = [item for item in collected if item.stage == stage]
            wins = sum(item.wins for item in relevant)
            draws = sum(item.draws for item in relevant)
            losses = sum(item.losses for item in relevant)
            games = wins + draws + losses
            rate = wins / games if games else 0.0
            lower = wilson_lower(wins, games)
            loss_rate = losses / games if games else 1.0
            non_loss_rate = (wins + draws) / games if games else 0.0
            non_loss_lower = wilson_lower(wins + draws, games)
            win_thresholds_passed = rate >= overall_threshold and lower >= confidence_floor
            if maximum_loss_rate is None or non_loss_confidence_floor is None:
                passed = games > 0 and win_thresholds_passed
            else:
                passed = (games > 0 and rate >= overall_threshold
                          and loss_rate <= maximum_loss_rate
                          and non_loss_lower >= non_loss_confidence_floor)
            stage_results.append(StageResult(
                stage, wins, draws, losses, rate, lower, loss_rate, non_loss_rate,
                non_loss_lower, passed))
        failed_slices = tuple(
            f"{item.stage}:{item.god}:agent{item.agent_player}:first{item.first_player}"
            for item in collected
            if (item.games < minimum_games_per_slice or item.win_rate < slice_floor
                or (maximum_slice_loss_rate is not None
                    and item.loss_rate > maximum_slice_loss_rate))
        )
        passed = not missing and not missing_slices and not failed_slices and all(
            item.passed for item in stage_results)
        return cls(passed, overall_threshold, confidence_floor, slice_floor,
                   maximum_loss_rate, non_loss_confidence_floor, maximum_slice_loss_rate,
                   minimum_games_per_slice, missing, missing_slices, failed_slices,
                   tuple(stage_results), collected)

    def to_dict(self) -> dict:
        return {
            "passed": self.passed,
            "criteria": {
                "overall_threshold": self.overall_threshold,
                "confidence_floor": self.confidence_floor,
                "slice_floor": self.slice_floor,
                "maximum_loss_rate": self.maximum_loss_rate,
                "non_loss_confidence_floor": self.non_loss_confidence_floor,
                "maximum_slice_loss_rate": self.maximum_slice_loss_rate,
                "minimum_games_per_slice": self.minimum_games_per_slice,
            },
            "missing_stages": list(self.missing_stages),
            "missing_slices": list(self.missing_slices),
            "failed_slices": list(self.failed_slices),
            "stages": [asdict(item) for item in self.stages],
            "slices": [{**asdict(item), "games": item.games, "win_rate": item.win_rate,
                        "loss_rate": item.loss_rate, "non_loss_rate": item.non_loss_rate}
                       for item in self.slices],
        }


def wilson_lower(wins: int, games: int, z: float = 1.96) -> float:
    if games <= 0:
        return 0.0
    probability = wins / games
    denominator = 1.0 + z * z / games
    centre = probability + z * z / (2.0 * games)
    margin = z * math.sqrt((probability * (1.0 - probability) + z * z / (4.0 * games)) / games)
    return (centre - margin) / denominator
