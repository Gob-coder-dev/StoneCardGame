from __future__ import annotations

import numpy as np

from .candidate import DeckCandidate
from .catalog import DeckCatalog
from .generator import DeckGenerator


class MutationExhausted(RuntimeError):
    pass


class DeckOperators:
    def __init__(self, catalog: DeckCatalog, max_attempts: int = 128) -> None:
        self.catalog = catalog
        self.max_attempts = max_attempts
        self.generator = DeckGenerator(catalog, max_attempts)

    def mutate(self, candidate: DeckCandidate, rng: np.random.Generator,
               mutations: int = 1) -> DeckCandidate:
        self.catalog.require_valid(candidate)
        result = candidate
        for _index in range(mutations):
            result = self._single_mutation(result, rng)
        if result == candidate:
            raise MutationExhausted("la mutation n'a produit aucun changement")
        return result

    def crossover(self, first: DeckCandidate, second: DeckCandidate,
                  rng: np.random.Generator) -> DeckCandidate:
        if first.god_id != second.god_id:
            raise ValueError("un croisement exige deux decks du même dieu")
        self.catalog.require_valid(first)
        self.catalog.require_valid(second)
        parents = {self.catalog.variants[item].lineage_id: item
                   for item in (*first.stone_ids, *second.stone_ids)}
        lineages = tuple(parents)
        for _attempt in range(self.max_attempts):
            selected = rng.choice(lineages, size=self.catalog.deck_size, replace=False)
            stones = []
            for raw_lineage in selected:
                lineage = str(raw_lineage)
                inherited = [item for item in (*first.stone_ids, *second.stone_ids)
                             if self.catalog.variants[item].lineage_id == lineage]
                stones.append(inherited[int(rng.integers(len(inherited)))])
            child = DeckCandidate.build(first.god_id, stones, self.catalog)
            if not self.catalog.problems(child) and child not in {first, second}:
                return child
        return self.mutate(first, rng, mutations=2)

    def _single_mutation(self, candidate: DeckCandidate, rng: np.random.Generator) -> DeckCandidate:
        for _attempt in range(self.max_attempts):
            operation = "level" if rng.random() < 0.40 else "lineage"
            mutated = self._change_level(candidate, rng) if operation == "level" else self._replace_lineage(candidate, rng)
            if mutated is not None and mutated != candidate and not self.catalog.problems(mutated):
                return mutated
        raise MutationExhausted(f"aucune mutation légale après {self.max_attempts} essais")

    def _change_level(self, candidate: DeckCandidate, rng: np.random.Generator) -> DeckCandidate | None:
        index = int(rng.integers(len(candidate.stone_ids)))
        current = self.catalog.variants[candidate.stone_ids[index]]
        alternatives = [item for item in self.catalog.variants_for(current.lineage_id, candidate.god_id)
                        if item.stone_id != current.stone_id]
        if not alternatives:
            return None
        replacement = alternatives[int(rng.integers(len(alternatives)))].stone_id
        stones = list(candidate.stone_ids)
        stones[index] = replacement
        return DeckCandidate.build(candidate.god_id, stones, self.catalog)

    def _replace_lineage(self, candidate: DeckCandidate, rng: np.random.Generator) -> DeckCandidate | None:
        present = {self.catalog.variants[item].lineage_id for item in candidate.stone_ids}
        available = [lineage for lineage in self.catalog.compatible_lineages(candidate.god_id)
                     if lineage not in present]
        if not available:
            return None
        index = int(rng.integers(len(candidate.stone_ids)))
        lineage = available[int(rng.integers(len(available)))]
        variants = self.catalog.variants_for(lineage, candidate.god_id)
        replacement = variants[int(rng.integers(len(variants)))].stone_id
        stones = list(candidate.stone_ids)
        stones[index] = replacement
        return DeckCandidate.build(candidate.god_id, stones, self.catalog)
