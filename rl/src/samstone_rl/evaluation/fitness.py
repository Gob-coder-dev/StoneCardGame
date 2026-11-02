from __future__ import annotations

from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass

import numpy as np

from samstone_rl.training.validation import wilson_lower

from .store import MatchRecord


@dataclass(frozen=True, slots=True)
class CandidateEvaluation:
    candidate_hash: str
    games: int
    wins: int
    draws: int
    losses: int
    win_rate: float
    wilson_lower: float
    worst_matchup_win_rate: float
    mean_margin: float
    fitness: float


def compute_fitness(records: Iterable[MatchRecord]) -> CandidateEvaluation:
    records = tuple(records)
    if not records:
        raise ValueError("aucun match pour calculer la fitness")
    hashes = {record.candidate_hash for record in records}
    if len(hashes) != 1:
        raise ValueError("les matchs appartiennent à plusieurs candidats")
    games = len(records)
    wins = sum(record.won for record in records)
    draws = sum(record.draw for record in records)
    losses = games - wins - draws
    win_rate = wins / games
    by_opponent: dict[str, list[bool]] = defaultdict(list)
    for record in records:
        by_opponent[record.opponent_id].append(record.won)
    worst = min(sum(outcomes) / len(outcomes) for outcomes in by_opponent.values())
    mean_margin = float(np.mean([
        (record.score_candidate - record.score_opponent) / 16.0 for record in records]))
    margin_component = min(1.0, max(0.0, (mean_margin + 1.0) / 2.0))
    lower = wilson_lower(wins, games)
    fitness = 0.70 * lower + 0.25 * worst + 0.05 * margin_component
    return CandidateEvaluation(next(iter(hashes)), games, wins, draws, losses,
                               win_rate, lower, worst, mean_margin, fitness)
