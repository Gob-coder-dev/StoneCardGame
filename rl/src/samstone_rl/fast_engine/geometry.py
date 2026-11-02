"""Immutable geometry tables for the 4 x 4 battle board."""

from __future__ import annotations

BOARD_SIZE = 4
SIDES = ("top", "bottom", "left", "right")
SIDE_INDEX = {side: index for index, side in enumerate(SIDES)}
DELTAS = ((-1, 0), (1, 0), (0, -1), (0, 1))
OPPOSITE = (1, 0, 3, 2)


def _build_rays() -> tuple[tuple[tuple[int, ...], ...], ...]:
    rays: list[tuple[tuple[int, ...], ...]] = []
    for origin in range(BOARD_SIZE * BOARD_SIZE):
        row, col = divmod(origin, BOARD_SIZE)
        cell_rays: list[tuple[int, ...]] = []
        for delta_row, delta_col in DELTAS:
            ray: list[int] = []
            target_row, target_col = row + delta_row, col + delta_col
            while 0 <= target_row < BOARD_SIZE and 0 <= target_col < BOARD_SIZE:
                ray.append(target_row * BOARD_SIZE + target_col)
                target_row += delta_row
                target_col += delta_col
            cell_rays.append(tuple(ray))
        rays.append(tuple(cell_rays))
    return tuple(rays)


# RAYS[origin][side] lists board indices from nearest to farthest.
RAYS = _build_rays()

