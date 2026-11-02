from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from samstone_rl.training.deck_evolution import RankedCandidate


@dataclass(frozen=True, slots=True)
class PhaseSixGate:
    minimum_win_rate: float
    minimum_worst_matchup: float

    def validate(self) -> None:
        for name, value in (("minimum_win_rate", self.minimum_win_rate),
                            ("minimum_worst_matchup", self.minimum_worst_matchup)):
            if not 0.0 <= value <= 1.0:
                raise ValueError(f"{name} doit etre compris entre 0 et 1")

    def passes(self, ranking: tuple[RankedCandidate, ...]) -> bool:
        self.validate()
        return bool(ranking) and all(
            item.evaluation.win_rate >= self.minimum_win_rate
            and item.evaluation.worst_matchup_win_rate >= self.minimum_worst_matchup
            for item in ranking
        )


def write_gate_result(path: str | Path, god_id: str, ranking: tuple[RankedCandidate, ...],
                      gate: PhaseSixGate, engine_checksum: str, catalog_checksum: str,
                      policy_checksum: str, official: bool = True) -> dict:
    gate.validate()
    thresholds_passed = gate.passes(ranking)
    payload = {
        "version": 1,
        "god_id": god_id,
        "official": official,
        "thresholds_passed": thresholds_passed,
        "passed": official and thresholds_passed,
        "thresholds": {
            "minimum_win_rate": gate.minimum_win_rate,
            "minimum_worst_matchup": gate.minimum_worst_matchup,
        },
        "engine_checksum": engine_checksum,
        "catalog_checksum": catalog_checksum,
        "policy_checksum": policy_checksum,
        "finalists": [
            {
                "deck_hash": item.candidate.deck_hash,
                "stone_ids": list(item.candidate.stone_ids),
                "games": item.evaluation.games,
                "win_rate": item.evaluation.win_rate,
                "wilson_lower": item.evaluation.wilson_lower,
                "worst_matchup_win_rate": item.evaluation.worst_matchup_win_rate,
                "fitness": item.evaluation.fitness,
            }
            for item in ranking
        ],
    }
    target = Path(path).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    temporary.replace(target)
    return payload
