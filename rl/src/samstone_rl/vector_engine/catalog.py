from __future__ import annotations

import random
from dataclasses import dataclass

import numpy as np

from samstone_rl.batch_engine.catalog import NumericStoneCatalog
from samstone_rl.fast_engine.core import BattleStone, _stable_seed

from .geometry import BOARD_CELLS, SIDES

PREVIEW_SAMPLES = 4
UNSAFE_EFFECTS: frozenset[str] = frozenset()


@dataclass(frozen=True, slots=True)
class VectorStoneCatalog:
    """Precomputed source variants used by counterfactual move evaluation."""

    numeric: NumericStoneCatalog
    attacks: np.ndarray
    ranged: np.ndarray
    defenses: np.ndarray
    stochastic: np.ndarray
    simple_source: np.ndarray
    effect_flags: np.ndarray
    affinity_indices: np.ndarray

    @classmethod
    def from_numeric(cls, numeric: NumericStoneCatalog) -> VectorStoneCatalog:
        count = len(numeric.stone_ids)
        shape = (count, BOARD_CELLS, PREVIEW_SAMPLES, SIDES)
        attacks = np.zeros(shape, dtype=np.int8)
        ranged = np.zeros(shape, dtype=np.int8)
        defenses = np.zeros(shape, dtype=np.int8)
        stochastic = np.zeros(count, dtype=np.bool_)
        simple_source = np.ones(count, dtype=np.bool_)
        for stone_index, stone_id in enumerate(numeric.stone_ids):
            definition = numeric.source.definition(stone_id)
            stochastic[stone_index] = bool(
                definition.get("random_blades", 0) or definition.get("coin_flip", ""))
            simple_source[stone_index] = not bool(
                UNSAFE_EFFECTS.intersection(definition.get("effects", ())))
            for cell in range(BOARD_CELLS):
                for sample in range(PREVIEW_SAMPLES):
                    stone = _preview_stone(stone_id, definition, cell, sample)
                    for side in range(SIDES):
                        attacks[stone_index, cell, sample, side] = stone.attack(side)
                        ranged[stone_index, cell, sample, side] = stone.ranged_attack(side)
                        defenses[stone_index, cell, sample, side] = stone.defense(side)
        for table in (attacks, ranged, defenses, stochastic, simple_source):
            table.setflags(write=False)
        return cls(numeric, attacks, ranged, defenses, stochastic, simple_source,
                   numeric.effect_flags, numeric.affinity_indices)


def _preview_stone(stone_id: str, definition: dict, cell: int,
                   sample: int) -> BattleStone:
    stone = BattleStone.from_definition(stone_id, definition)
    seed = _stable_seed(stone_id, cell // 4, cell % 4, sample)
    rng = random.Random(seed)
    for _ in range(int(definition.get("random_blades", 0))):
        candidates = [side for side in range(SIDES) if stone.free_slots(side) > 0]
        if not candidates:
            break
        stone.random_blades[candidates[rng.randrange(len(candidates))]] += 1
    axis = str(definition.get("coin_flip", ""))
    if axis:
        stone.coin_flipped = rng.randrange(2) == 1
        if stone.coin_flipped:
            first, second = ((2, 3) if axis == "horizontal" else (0, 1))
            for values in (stone.base, stone.random_blades, stone.long, stone.shields):
                values[first], values[second] = values[second], values[first]
    return stone
