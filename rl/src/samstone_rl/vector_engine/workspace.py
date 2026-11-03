from __future__ import annotations

import numpy as np

from .catalog import PREVIEW_SAMPLES
from .geometry import ACTION_COUNT, BOARD_CELLS, HAND_SIZE, SIDES


class VectorWorkspace:
    """Reusable scratch arrays for the dense tactical kernel.

    The largest arrays are allocated only when batch capacity grows. Returned
    views are valid until the next evaluator call and must not escape the
    synchronous encode/selection path.
    """

    def __init__(self) -> None:
        self.capacity = 0

    def ensure(self, batch: int) -> VectorWorkspace:
        if batch <= self.capacity:
            return self
        self.capacity = int(batch)
        base = (self.capacity, BOARD_CELLS)
        action = (self.capacity, ACTION_COUNT)
        preview = (self.capacity, ACTION_COUNT, PREVIEW_SAMPLES)
        board_preview = (*preview, BOARD_CELLS)
        side_preview = (*board_preview, SIDES)
        self.owners = np.zeros(base, dtype=np.int8)
        self.blocked = np.zeros(base, dtype=np.bool_)
        self.defenses = np.zeros((*base, SIDES), dtype=np.int8)
        self.raw_attacks = np.zeros((*base, SIDES), dtype=np.int8)
        self.base_raw_attacks = np.zeros((*base, SIDES), dtype=np.int8)
        self.shields = np.zeros((*base, SIDES), dtype=np.int8)
        self.temporary = np.zeros(base, dtype=np.int8)
        self.temporary_owners = np.zeros(base, dtype=np.int8)
        self.board_stones = np.full(base, -1, dtype=np.int16)
        self.instance_ids = np.full(base, -1, dtype=np.int32)
        self.hands = np.full((self.capacity, HAND_SIZE), -1, dtype=np.int16)
        self.scores = np.zeros((*action, 5), dtype=np.float32)
        self.captures = np.zeros(board_preview, dtype=np.bool_)
        self.failures = np.zeros(board_preview, dtype=np.bool_)
        self.owners_after = np.zeros(board_preview, dtype=np.int8)
        self.raw_after = np.zeros(side_preview, dtype=np.int8)
        self.defense_after = np.zeros(side_preview, dtype=np.int8)
        self.temp_after = np.zeros(board_preview, dtype=np.int8)
        self.stone_after = np.full(board_preview, -1, dtype=np.int16)
        self.miasma = np.zeros(board_preview, dtype=np.int8)
        self.reply_best = np.zeros(preview, dtype=np.int8)
        self.reply_count = np.zeros(preview, dtype=np.int8)
        return self

    def view(self, name: str, batch: int) -> np.ndarray:
        return getattr(self, name)[:batch]

    @property
    def allocated_bytes(self) -> int:
        return sum(value.nbytes for value in vars(self).values()
                   if isinstance(value, np.ndarray))

