from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from .catalog import StoneCatalog

SIDES = ("top", "bottom", "left", "right")
ZERO_SIDES = (0, 0, 0, 0)


def _sides(values: dict[str, Any]) -> tuple[int, int, int, int]:
    return tuple(int(values.get(side, 0)) for side in SIDES)  # type: ignore[return-value]


@dataclass(frozen=True, slots=True)
class StoneThreatSignature:
    """Public, immutable attack envelope of one catalogue variant."""

    lineage_id: str
    affinity: str
    adjacent: tuple[int, int, int, int]
    ranged: tuple[int, int, int, int]

    @classmethod
    def from_definition(cls, definition: dict[str, Any]) -> StoneThreatSignature:
        normal = _sides(definition.get("blades", {}))
        ranged = _sides(definition.get("long_blades", {}))
        random_bonus = int(definition.get("random_blades", 0))
        adjacent = tuple(normal[index] + ranged[index] + random_bonus for index in range(4))
        axis = str(definition.get("coin_flip", ""))
        if axis:
            first, second = ((2, 3) if axis == "horizontal" else (0, 1))
            flipped_adjacent = list(adjacent)
            flipped_ranged = list(ranged)
            flipped_adjacent[first], flipped_adjacent[second] = (
                flipped_adjacent[second], flipped_adjacent[first])
            flipped_ranged[first], flipped_ranged[second] = (
                flipped_ranged[second], flipped_ranged[first])
            adjacent = tuple(max(adjacent[index], flipped_adjacent[index])
                             for index in range(4))
            ranged = tuple(max(ranged[index], flipped_ranged[index])
                           for index in range(4))
        return cls(
            str(definition["lineage_id"]), str(definition["affinity"]),
            adjacent, ranged)  # type: ignore[arg-type]


@dataclass(frozen=True, slots=True)
class ReplyThreatProfile:
    """Strongest public reply by direction for one god and board history."""

    god_id: str
    played_lineages: tuple[str, ...]
    adjacent: tuple[int, int, int, int]
    ranged: tuple[int, int, int, int]
    has_cards: bool = True


class ReplyThreatCache:
    """Catalogue-wide immutable signatures plus bounded aggregate profiles.

    The cache never receives hidden card identities. A profile only depends on
    the public god and on lineages that player has already placed on the board.
    """

    def __init__(self, catalog: StoneCatalog, maximum_profiles: int = 4096) -> None:
        if maximum_profiles <= 0:
            raise ValueError("maximum_profiles doit etre positif")
        self.catalog = catalog
        self.signatures = {
            stone_id: StoneThreatSignature.from_definition(definition)
            for stone_id, definition in catalog.definitions.items()
        }
        self.by_god = {
            god_id: tuple(
                signature for signature in self.signatures.values()
                if signature.affinity in ("neutral", god_id))
            for god_id in catalog.gods
        }
        # lru_cache is created per catalogue instance: no stale entry can
        # survive a content change or leak into another run.
        self._aggregate = lru_cache(maxsize=maximum_profiles)(self._aggregate_uncached)

    def profile(self, god_id: str, played_lineages: set[str] | tuple[str, ...],
                hand_size: int) -> ReplyThreatProfile:
        lineages = tuple(sorted(set(played_lineages)))
        if hand_size <= 0:
            return ReplyThreatProfile(god_id, lineages, ZERO_SIDES, ZERO_SIDES, False)
        return self._aggregate(god_id, lineages)

    def cache_info(self):
        return self._aggregate.cache_info()

    def _aggregate_uncached(self, god_id: str,
                            played_lineages: tuple[str, ...]) -> ReplyThreatProfile:
        try:
            signatures = self.by_god[god_id]
        except KeyError as exc:
            raise ValueError(f"dieu inconnu: {god_id}") from exc
        excluded = set(played_lineages)
        possible = [item for item in signatures if item.lineage_id not in excluded]
        if not possible:
            return ReplyThreatProfile(
                god_id, played_lineages, ZERO_SIDES, ZERO_SIDES, False)
        adjacent = tuple(max(item.adjacent[index] for item in possible) for index in range(4))
        ranged = tuple(max(item.ranged[index] for item in possible) for index in range(4))
        return ReplyThreatProfile(
            god_id, played_lineages, adjacent, ranged, True)  # type: ignore[arg-type]
