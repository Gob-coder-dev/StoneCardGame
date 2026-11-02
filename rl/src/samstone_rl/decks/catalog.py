from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from .candidate import DeckCandidate


@dataclass(frozen=True, slots=True)
class StoneVariant:
    stone_id: str
    lineage_id: str
    level: int
    max_level: int
    affinity: str
    cost: float


class DeckCatalog:
    def __init__(self, snapshot: dict) -> None:
        self.schema_version = int(snapshot["schema_version"])
        if self.schema_version != 1:
            raise ValueError(f"schema de catalogue incompatible: {self.schema_version}")
        self.deck_size = int(snapshot["deck_size"])
        self.deck_budget = float(snapshot["deck_budget"])
        self.checksum = str(snapshot["checksum"])
        self.gods = tuple(str(item["id"]) for item in snapshot["gods"])
        self.variants = {
            str(item["stone_id"]): StoneVariant(
                str(item["stone_id"]), str(item["lineage_id"]), int(item["level"]),
                int(item["max_level"]), str(item["affinity"]), float(item["cost"]))
            for item in snapshot["variants"]
        }
        self.by_lineage: dict[str, tuple[StoneVariant, ...]] = {}
        for lineage in sorted({item.lineage_id for item in self.variants.values()}):
            self.by_lineage[lineage] = tuple(sorted(
                (item for item in self.variants.values() if item.lineage_id == lineage),
                key=lambda item: (item.level, item.stone_id)))

    def compatible_lineages(self, god_id: str) -> tuple[str, ...]:
        self._require_god(god_id)
        return tuple(lineage for lineage, variants in self.by_lineage.items()
                     if variants[0].affinity in {"neutral", god_id})

    def variants_for(self, lineage_id: str, god_id: str) -> tuple[StoneVariant, ...]:
        variants = self.by_lineage.get(lineage_id, ())
        return tuple(item for item in variants if item.affinity in {"neutral", god_id})

    def canonicalize(self, stone_ids: Iterable[str]) -> tuple[str, ...]:
        ids = tuple(str(item) for item in stone_ids)
        unknown = [item for item in ids if item not in self.variants]
        if unknown:
            raise ValueError(f"pierres inconnues: {unknown}")
        return tuple(sorted(ids, key=lambda item: (self.variants[item].lineage_id,
                                                   self.variants[item].level, item)))

    def cost(self, stone_ids: Iterable[str]) -> float:
        return sum(self.variants[item].cost for item in stone_ids)

    def problems(self, candidate: DeckCandidate) -> tuple[str, ...]:
        problems: list[str] = []
        if candidate.god_id not in self.gods:
            problems.append(f"dieu inconnu: {candidate.god_id}")
        if len(candidate.stone_ids) != self.deck_size:
            problems.append(f"le deck doit contenir {self.deck_size} pierres")
        unknown = [item for item in candidate.stone_ids if item not in self.variants]
        if unknown:
            problems.append(f"pierres inconnues: {unknown}")
            return tuple(problems)
        lineages = [self.variants[item].lineage_id for item in candidate.stone_ids]
        if len(lineages) != len(set(lineages)):
            problems.append("les lignées doivent être uniques")
        wrong = [item for item in candidate.stone_ids
                 if self.variants[item].affinity not in {"neutral", candidate.god_id}]
        if wrong:
            problems.append(f"pierres incompatibles avec le dieu: {wrong}")
        if self.cost(candidate.stone_ids) > self.deck_budget + 1e-9:
            problems.append(f"budget de {self.deck_budget:g} dépassé")
        if candidate.stone_ids != self.canonicalize(candidate.stone_ids):
            problems.append("ordre non canonique")
        return tuple(problems)

    def require_valid(self, candidate: DeckCandidate) -> None:
        problems = self.problems(candidate)
        if problems:
            raise ValueError("; ".join(problems))

    def candidate(self, god_id: str, stone_ids: Iterable[str]) -> DeckCandidate:
        candidate = DeckCandidate.build(god_id, stone_ids, self)
        self.require_valid(candidate)
        return candidate

    def _require_god(self, god_id: str) -> None:
        if god_id not in self.gods:
            raise ValueError(f"dieu inconnu: {god_id}")
