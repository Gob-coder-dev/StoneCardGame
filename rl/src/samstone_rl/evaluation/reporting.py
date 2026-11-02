from __future__ import annotations

import csv
import json
from collections import defaultdict
from collections.abc import Iterable
from pathlib import Path

from samstone_rl.training.deck_evolution import RankedCandidate

from .store import MatchRecord


def write_phase_six_report(output_directory: str | Path, god_id: str,
                           ranking: Iterable[RankedCandidate],
                           records: Iterable[MatchRecord]) -> None:
    output = Path(output_directory).resolve()
    output.mkdir(parents=True, exist_ok=True)
    ranking = tuple(ranking)
    records = tuple(records)
    usage: dict[str, int] = defaultdict(int)
    for ranked in ranking:
        for stone_id in ranked.candidate.stone_ids:
            usage[stone_id] += 1
    matchups: dict[str, dict[str, list[bool]]] = defaultdict(lambda: defaultdict(list))
    for record in records:
        matchups[record.candidate_hash][record.opponent_id].append(record.won)
    payload = {
        "version": 1,
        "god_id": god_id,
        "ranking": [
            {**item.candidate.to_dict(), "evaluation": {
                "games": item.evaluation.games,
                "wins": item.evaluation.wins,
                "draws": item.evaluation.draws,
                "losses": item.evaluation.losses,
                "win_rate": item.evaluation.win_rate,
                "wilson_lower": item.evaluation.wilson_lower,
                "worst_matchup_win_rate": item.evaluation.worst_matchup_win_rate,
                "mean_margin": item.evaluation.mean_margin,
                "fitness": item.evaluation.fitness,
            }, "matchups": {
                opponent: sum(outcomes) / len(outcomes)
                for opponent, outcomes in matchups[item.candidate.deck_hash].items()
            }} for item in ranking
        ],
        "card_usage": dict(sorted(usage.items(), key=lambda item: (-item[1], item[0]))),
    }
    temporary = output / f"phase6_{god_id}.json.tmp"
    target = output / f"phase6_{god_id}.json"
    temporary.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    temporary.replace(target)
    csv_target = output / f"phase6_{god_id}.csv"
    csv_temporary = csv_target.with_suffix(csv_target.suffix + ".tmp")
    with csv_temporary.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["rank", "deck_hash", "fitness", "win_rate", "wilson_lower",
                         "worst_matchup", "mean_margin", "stone_ids"])
        for index, item in enumerate(ranking, 1):
            writer.writerow([index, item.candidate.deck_hash, item.evaluation.fitness,
                             item.evaluation.win_rate, item.evaluation.wilson_lower,
                             item.evaluation.worst_matchup_win_rate, item.evaluation.mean_margin,
                             " ".join(item.candidate.stone_ids)])
    csv_temporary.replace(csv_target)
