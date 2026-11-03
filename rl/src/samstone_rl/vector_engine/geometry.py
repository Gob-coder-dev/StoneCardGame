from __future__ import annotations

import numpy as np

from samstone_rl.fast_engine.geometry import OPPOSITE, RAYS

ACTION_COUNT = 128
BOARD_CELLS = 16
HAND_SIZE = 8
SIDES = 4
MAX_DISTANCE = 3

ACTION_SLOTS = np.repeat(np.arange(HAND_SIZE, dtype=np.int16), BOARD_CELLS)
ACTION_CELLS = np.tile(np.arange(BOARD_CELLS, dtype=np.int16), HAND_SIZE)

RAY_TARGETS = np.full(
    (ACTION_COUNT, SIDES, MAX_DISTANCE), -1, dtype=np.int16)
for action, origin in enumerate(ACTION_CELLS):
    for side in range(SIDES):
        ray = RAYS[int(origin)][side]
        RAY_TARGETS[action, side, :len(ray)] = ray

ORIGIN_RAY_TARGETS = np.full(
    (BOARD_CELLS, SIDES, MAX_DISTANCE), -1, dtype=np.int16)
for origin in range(BOARD_CELLS):
    for side in range(SIDES):
        ray = RAYS[origin][side]
        ORIGIN_RAY_TARGETS[origin, side, :len(ray)] = ray

OPPOSITE_SIDES = np.asarray(OPPOSITE, dtype=np.int16)
POSITION_FEATURES = np.asarray([
    (slot / 7.0, (cell // 4) / 3.0, (cell % 4) / 3.0)
    for slot, cell in zip(ACTION_SLOTS, ACTION_CELLS, strict=True)
], dtype=np.float32)

ADJACENCY = np.zeros((BOARD_CELLS, BOARD_CELLS), dtype=np.bool_)
for origin in range(BOARD_CELLS):
    row, col = divmod(origin, 4)
    for target in range(BOARD_CELLS):
        target_row, target_col = divmod(target, 4)
        ADJACENCY[origin, target] = abs(row - target_row) + abs(col - target_col) == 1

for table in (ACTION_SLOTS, ACTION_CELLS, RAY_TARGETS, ADJACENCY,
              ORIGIN_RAY_TARGETS, OPPOSITE_SIDES, POSITION_FEATURES):
    table.setflags(write=False)
