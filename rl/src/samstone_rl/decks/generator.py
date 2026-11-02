from __future__ import annotations

import numpy as np

from .candidate import DeckCandidate
from .catalog import DeckCatalog


class DeckGenerator:
    def __init__(self, catalog: DeckCatalog, max_attempts: int = 256) -> None:
        self.catalog = catalog
        self.max_attempts = max_attempts

    def random_candidate(self, god_id: str, rng: np.random.Generator) -> DeckCandidate:
        lineages = self.catalog.compatible_lineages(god_id)
        if len(lineages) < self.catalog.deck_size:
            raise RuntimeError(f"pas assez de lignées compatibles pour {god_id}")
        for _attempt in range(self.max_attempts):
            chosen = rng.choice(lineages, size=self.catalog.deck_size, replace=False)
            stone_ids = [self._random_variant(str(lineage), god_id, rng).stone_id for lineage in chosen]
            candidate = DeckCandidate.build(god_id, stone_ids, self.catalog)
            if not self.catalog.problems(candidate):
                return candidate
        return self._cheap_candidate(god_id, rng)

    def _cheap_candidate(self, god_id: str, rng: np.random.Generator) -> DeckCandidate:
        lineages = list(self.catalog.compatible_lineages(god_id))
        rng.shuffle(lineages)
        cheapest = sorted(
            (min(self.catalog.variants_for(lineage, god_id), key=lambda item: (item.cost, item.level))
             for lineage in lineages), key=lambda item: (item.cost, item.lineage_id))
        for start in range(max(1, len(cheapest) - self.catalog.deck_size + 1)):
            selection = cheapest[start:start + self.catalog.deck_size]
            if len(selection) == self.catalog.deck_size:
                candidate = DeckCandidate.build(god_id, (item.stone_id for item in selection), self.catalog)
                if not self.catalog.problems(candidate):
                    return candidate
        raise RuntimeError(f"impossible de construire un deck légal pour {god_id}")

    def _random_variant(self, lineage: str, god_id: str, rng: np.random.Generator):
        variants = self.catalog.variants_for(lineage, god_id)
        return variants[int(rng.integers(len(variants)))]
