"""Paired, seed-identical checkpoint comparison utilities.

Every policy receives the exact same immutable :class:`ComparisonCase` list.
This makes differences attributable to the policy rather than a different draw,
terrain, first player, or opponent randomness.
"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Iterable
from dataclasses import asdict, dataclass
from math import comb

import numpy as np

from samstone_rl.training.validation import wilson_lower


@dataclass(frozen=True)
class ComparisonCase:
    case_id: int
    seed: int
    scenario_index: int
    god: str
    agent_player: int
    first_player: int
    blocked_count: int
    blocked_cells: tuple[tuple[int, int], ...] | None = None


@dataclass(frozen=True)
class ComparisonOutcome:
    model: str
    checkpoint: str
    case: ComparisonCase
    winner: int
    margin: int
    turns: int

    @property
    def won(self) -> bool:
        return self.winner == self.case.agent_player

    @property
    def draw(self) -> bool:
        return self.winner == 0

    @property
    def score(self) -> float:
        return 1.0 if self.won else (0.5 if self.draw else 0.0)


def outcome_summary(outcomes: Iterable[ComparisonOutcome]) -> dict[str, float | int]:
    """Summarise a homogeneous slice of outcomes."""
    values = tuple(outcomes)
    games = len(values)
    wins = sum(item.won for item in values)
    draws = sum(item.draw for item in values)
    losses = games - wins - draws
    return {
        "games": games,
        "wins": wins,
        "draws": draws,
        "losses": losses,
        "win_rate": wins / games if games else 0.0,
        "wilson_lower": wilson_lower(wins, games),
        "loss_rate": losses / games if games else 1.0,
        "non_loss_rate": (wins + draws) / games if games else 0.0,
        "mean_margin": float(np.mean([item.margin for item in values])) if values else 0.0,
        "mean_turns": float(np.mean([item.turns for item in values])) if values else 0.0,
    }


def grouped_summary(outcomes: Iterable[ComparisonOutcome]) -> dict[str, dict[str, dict[str, float | int]]]:
    """Return overall and controlled slices for one policy."""
    values = tuple(outcomes)
    groups: dict[str, dict[str, list[ComparisonOutcome]]] = {
        "by_god": defaultdict(list),
        "by_blocked_count": defaultdict(list),
        "by_start_order": defaultdict(list),
        "by_agent_side": defaultdict(list),
    }
    for item in values:
        groups["by_god"][item.case.god].append(item)
        groups["by_blocked_count"][str(item.case.blocked_count)].append(item)
        order = "agent_first" if item.case.first_player == item.case.agent_player else "opponent_first"
        groups["by_start_order"][order].append(item)
        groups["by_agent_side"][f"player_{item.case.agent_player}"].append(item)
    return {
        "overall": outcome_summary(values),
        **{name: {key: outcome_summary(bucket) for key, bucket in sorted(group.items())}
           for name, group in groups.items()},
    }


def paired_delta(reference: Iterable[ComparisonOutcome], candidate: Iterable[ComparisonOutcome]) -> dict[str, float | int]:
    """Compare two models on the same cases using outcome score differences."""
    reference_by_case = {item.case.case_id: item for item in reference}
    candidate_by_case = {item.case.case_id: item for item in candidate}
    if set(reference_by_case) != set(candidate_by_case):
        raise ValueError("les modèles ne possèdent pas le même ensemble de cas")
    deltas = [candidate_by_case[key].score - reference_by_case[key].score
              for key in sorted(reference_by_case)]
    better = sum(value > 0.0 for value in deltas)
    worse = sum(value < 0.0 for value in deltas)
    decisive = better + worse
    # Exact two-sided sign test. Ties contain no directional information and
    # are deliberately excluded, as in a standard paired sign test.
    tail = sum(comb(decisive, index) for index in range(min(better, worse) + 1))
    sign_p_value = min(1.0, 2.0 * tail / (2 ** decisive)) if decisive else 1.0
    return {
        "games": len(deltas),
        "candidate_better": better,
        "same": sum(value == 0.0 for value in deltas),
        "candidate_worse": worse,
        "decisive_games": decisive,
        "two_sided_sign_p_value": sign_p_value,
        "mean_score_delta": float(np.mean(deltas)) if deltas else 0.0,
    }


def outcome_row(outcome: ComparisonOutcome) -> dict[str, str | int | float]:
    """Flatten one outcome for CSV/JSON exports."""
    case = asdict(outcome.case)
    return {
        "model": outcome.model,
        "checkpoint": outcome.checkpoint,
        **case,
        "winner": outcome.winner,
        "won": int(outcome.won),
        "draw": int(outcome.draw),
        "score": outcome.score,
        "margin": outcome.margin,
        "turns": outcome.turns,
    }
