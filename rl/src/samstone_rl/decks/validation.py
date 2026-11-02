from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from samstone_rl.bridge.godot_process import GodotProcess

from .candidate import DeckCandidate
from .catalog import DeckCatalog


@dataclass(frozen=True, slots=True)
class DeckValidationResult:
    candidate: DeckCandidate
    valid: bool
    reason: str
    cost: float


class GodotDeckValidator:
    def __init__(self, bridge: GodotProcess, catalog: DeckCatalog) -> None:
        self.bridge = bridge
        self.catalog = catalog

    def validate_many(self, candidates: Iterable[DeckCandidate]) -> tuple[DeckValidationResult, ...]:
        candidates = tuple(candidates)
        requests = [{"candidate_id": item.deck_hash, "god_id": item.god_id,
                     "stone_ids": list(item.stone_ids)} for item in candidates]
        remote = {str(item["candidate_id"]): item for item in self.bridge.validate_decks(requests)}
        results = []
        for candidate in candidates:
            local_problems = self.catalog.problems(candidate)
            result = remote[candidate.deck_hash]
            valid = not local_problems and bool(result["valid"])
            reason = "; ".join(local_problems) if local_problems else str(result["reason"])
            results.append(DeckValidationResult(candidate, valid, reason, float(result["cost"])))
        return tuple(results)

    def require_all_valid(self, candidates: Iterable[DeckCandidate]) -> None:
        invalid = [result for result in self.validate_many(candidates) if not result.valid]
        if invalid:
            details = "; ".join(f"{item.candidate.deck_hash[:8]}: {item.reason}" for item in invalid)
            raise ValueError(f"decks refusés par Godot: {details}")
