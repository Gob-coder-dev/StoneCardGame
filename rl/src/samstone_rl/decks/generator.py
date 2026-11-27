from __future__ import annotations

from collections.abc import Sequence

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
            stone_ids = [
                self._random_variant(str(lineage), god_id, rng).stone_id for lineage in chosen
            ]
            candidate = DeckCandidate.build(god_id, stone_ids, self.catalog)
            if not self.catalog.problems(candidate):
                return candidate
        return self._cheap_candidate(god_id, rng)

    def match_budget(
        self, god_id: str, template: Sequence[str], budget: float, *, family_size: int | None = None
    ) -> tuple[str, ...]:
        """Reach an exact budget, minimizing lineage swaps and then level changes."""
        original = self.catalog.candidate(god_id, template)
        quarters = round(budget * 4)
        if quarters != budget * 4 or not 0 < budget <= self.catalog.deck_budget:
            raise ValueError("budget cible invalide")
        cards = [self.catalog.variants[stone_id] for stone_id in template]
        by_lineage = {card.lineage_id: card for card in cards}
        if family_size is None:
            family_size = sum(card.affinity == god_id for card in cards)
        if not 0 <= family_size <= len(cards):
            raise ValueError("nombre de cartes de famille invalide")
        neutral_size = len(original.stone_ids) - family_size
        table = {(0, 0, 0): (0, 0, ())}
        for lineage in self.catalog.compatible_lineages(god_id):
            prior = by_lineage.get(lineage)
            for (family, neutral, cost), (swaps, moves, ids) in list(table.items()):
                for variant in self.catalog.variants_for(lineage, god_id):
                    key = (
                        family + (variant.affinity == god_id),
                        neutral + (variant.affinity == "neutral"),
                        cost + round(variant.cost * 4),
                    )
                    if key[0] > family_size or key[1] > neutral_size or key[2] > quarters:
                        continue
                    option = (
                        swaps + (prior is None),
                        moves + (abs(variant.level - prior.level) if prior else 0),
                        (*ids, variant.stone_id),
                    )
                    if key not in table or option < table[key]:
                        table[key] = option
        best = table.get((family_size, neutral_size, quarters))
        if best is None:
            raise ValueError(f"budget exact de {budget:g} indisponible pour {god_id}")
        remaining = {self.catalog.variants[card].lineage_id: card for card in best[2]}
        ordered = [remaining.pop(card.lineage_id, None) for card in cards]
        replacements = iter(remaining.values())
        return tuple(card if card is not None else next(replacements) for card in ordered)

    def _cheap_candidate(self, god_id: str, rng: np.random.Generator) -> DeckCandidate:
        lineages = list(self.catalog.compatible_lineages(god_id))
        rng.shuffle(lineages)
        cheapest = sorted(
            (
                min(
                    self.catalog.variants_for(lineage, god_id),
                    key=lambda item: (item.cost, item.level),
                )
                for lineage in lineages
            ),
            key=lambda item: (item.cost, item.lineage_id),
        )
        for start in range(max(1, len(cheapest) - self.catalog.deck_size + 1)):
            selection = cheapest[start : start + self.catalog.deck_size]
            if len(selection) == self.catalog.deck_size:
                candidate = DeckCandidate.build(
                    god_id, (item.stone_id for item in selection), self.catalog
                )
                if not self.catalog.problems(candidate):
                    return candidate
        raise RuntimeError(f"impossible de construire un deck légal pour {god_id}")

    def _random_variant(self, lineage: str, god_id: str, rng: np.random.Generator):
        variants = self.catalog.variants_for(lineage, god_id)
        return variants[int(rng.integers(len(variants)))]
