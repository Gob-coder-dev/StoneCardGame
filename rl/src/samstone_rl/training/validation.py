from __future__ import annotations

import math
from collections.abc import Iterable
from dataclasses import asdict, dataclass, field

from .god_thresholds import parse_god_thresholds, threshold_groups


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
    god_thresholds: dict = field(default_factory=dict)
    god_groups: dict = field(default_factory=dict)
    core_god_thresholds: dict | None = None
    god_stage_results: dict = field(default_factory=dict)
    failed_god_stages: tuple[str, ...] = ()

    @classmethod
    def build(
        cls,
        slices: Iterable[EvaluationSlice],
        expected_stages: Iterable[str],
        expected_gods: Iterable[str],
        overall_threshold: float = 0.95,
        confidence_floor: float = 0.90,
        slice_floor: float = 0.90,
        minimum_games_per_slice: int = 100,
        maximum_loss_rate: float | None = None,
        non_loss_confidence_floor: float | None = None,
        maximum_slice_loss_rate: float | None = None,
        god_thresholds: dict | None = None,
        core_god_thresholds: dict | None = None,
    ) -> PhaseFourGateReport:
        collected = tuple(slices)
        expected = tuple(expected_stages)
        gods = tuple(expected_gods)
        thresholds = parse_god_thresholds(god_thresholds)
        pooled = (
            parse_god_thresholds({"core": core_god_thresholds})["core"]
            if core_god_thresholds is not None
            else None
        )
        god_stage_results = {}
        if set(thresholds) - set(gods):
            raise ValueError("seuil configure pour un dieu absent de la validation")
        god_groups = {}
        present = {item.stage for item in collected}
        missing = tuple(stage for stage in expected if stage not in present)
        present_slices = {
            (item.stage, item.god, item.agent_player, item.first_player) for item in collected
        }
        expected_slices = (
            (stage, god, agent, first)
            for stage in expected
            for god in gods
            for agent in (1, 2)
            for first in (1, 2)
        )
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
                passed = (
                    games > 0
                    and rate >= overall_threshold
                    and loss_rate <= maximum_loss_rate
                    and non_loss_lower >= non_loss_confidence_floor
                )
            stage_results.append(
                StageResult(
                    stage,
                    wins,
                    draws,
                    losses,
                    rate,
                    lower,
                    loss_rate,
                    non_loss_rate,
                    non_loss_lower,
                    passed,
                )
            )
            if thresholds:
                by_god = {
                    god: dict(
                        wins=sum(s.wins for s in relevant if s.god == god),
                        draws=sum(s.draws for s in relevant if s.god == god),
                        games=sum(s.games for s in relevant if s.god == god),
                    )
                    for god in gods
                }

                def core_check(w, d, n):
                    if n <= 0:
                        return {"eligible": False, "games": n}
                    eligible = w / n >= overall_threshold
                    if maximum_loss_rate is None or non_loss_confidence_floor is None:
                        eligible &= wilson_lower(w, n) >= confidence_floor
                    else:
                        eligible &= (n - w - d) / n <= maximum_loss_rate and wilson_lower(
                            w + d, n
                        ) >= non_loss_confidence_floor
                    return dict(
                        eligible=bool(eligible),
                        wins=w,
                        draws=d,
                        games=n,
                        win_rate=w / n,
                        loss_rate=(n - w - d) / n,
                    )

                group = threshold_groups(by_god, thresholds, core_check)
                god_groups[stage] = group
                item = stage_results[-1]
                stage_results[-1] = StageResult(**{**asdict(item), "passed": group["eligible"]})
            if pooled is not None:
                god_stage_results[stage] = {}
                for god in gods:
                    if god in thresholds:
                        continue
                    entries = [item for item in relevant if item.god == god]
                    n = sum(item.games for item in entries)
                    w = sum(item.wins for item in entries)
                    loss = sum(item.losses for item in entries)
                    god_stage_results[stage][god] = dict(
                        games=n,
                        wins=w,
                        losses=loss,
                        draws=n - w - loss,
                        win_rate=w / n if n else 0.0,
                        loss_rate=loss / n if n else 1.0,
                        criteria=pooled,
                        passed=(
                            n > 0
                            and n >= 4 * minimum_games_per_slice
                            and w / n + 1e-12 >= pooled["minimum_win_rate"]
                            and loss / n <= pooled["maximum_loss_rate"] + 1e-12
                        ),
                    )
        failed_god_stages = tuple(
            f"{stage}:{god}"
            for stage, outcomes in god_stage_results.items()
            for god, outcome in outcomes.items()
            if not outcome["passed"]
        )
        failed_slices = tuple(
            f"{item.stage}:{item.god}:agent{item.agent_player}:first{item.first_player}"
            for item in collected
            if (
                item.games < minimum_games_per_slice
                or (item.god not in thresholds and item.win_rate < slice_floor)
                or (
                    item.god not in thresholds
                    and maximum_slice_loss_rate is not None
                    and item.loss_rate > maximum_slice_loss_rate
                )
            )
        )
        passed = (
            not missing
            and not missing_slices
            and not failed_slices
            and not failed_god_stages
            and all(item.passed for item in stage_results)
        )
        return cls(
            passed,
            overall_threshold,
            confidence_floor,
            slice_floor,
            maximum_loss_rate,
            non_loss_confidence_floor,
            maximum_slice_loss_rate,
            minimum_games_per_slice,
            missing,
            missing_slices,
            failed_slices,
            tuple(stage_results),
            collected,
            thresholds,
            god_groups,
            pooled,
            god_stage_results,
            failed_god_stages,
        )

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
                "god_thresholds": self.god_thresholds,
                "core_god_thresholds": self.core_god_thresholds,
            },
            "missing_stages": list(self.missing_stages),
            "missing_slices": list(self.missing_slices),
            "failed_slices": list(self.failed_slices),
            "stages": [asdict(item) for item in self.stages],
            "god_groups": self.god_groups,
            "god_stage_results": self.god_stage_results,
            "failed_god_stages": list(self.failed_god_stages),
            "slices": [
                {
                    **asdict(item),
                    "games": item.games,
                    "win_rate": item.win_rate,
                    "loss_rate": item.loss_rate,
                    "non_loss_rate": item.non_loss_rate,
                }
                for item in self.slices
            ],
        }


def wilson_lower(wins: int, games: int, z: float = 1.96) -> float:
    if games <= 0:
        return 0.0
    probability = wins / games
    denominator = 1.0 + z * z / games
    centre = probability + z * z / (2.0 * games)
    margin = z * math.sqrt((probability * (1.0 - probability) + z * z / (4.0 * games)) / games)
    return (centre - margin) / denominator
