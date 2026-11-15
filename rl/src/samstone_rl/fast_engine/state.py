"""Mutable match data and faithful clones, independent of combat resolution."""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Any

from .catalog import StoneCatalog
from .geometry import SIDES
from .preview import PreviewRandom

PLAYER_NONE, PLAYER_HUMAN, PLAYER_AI = 0, 1, 2
CELL_EMPTY, CELL_BLOCKED = 0, -1
MAX_MARKERS = 4


@dataclass(slots=True)
class BattleStone:
    stone_id: str
    instance_id: int
    base: list[int]
    random_blades: list[int]
    long: list[int]
    shields: list[int]
    swarm: list[int]
    miasma_weakness: int = 0
    temporary_weakness: int = 0
    temporary_weakness_owner: int = 0
    coin_flipped: bool = False

    @classmethod
    def from_definition(
        cls, stone_id: str, definition: dict[str, Any], instance_id: int = 0
    ) -> BattleStone:
        return cls(
            stone_id,
            instance_id,
            _sides(definition.get("blades", {})),
            [0] * 4,
            _sides(definition.get("long_blades", {})),
            _sides(definition.get("shields", {})),
            [0] * 4,
        )

    def clone(self) -> BattleStone:
        return BattleStone(
            self.stone_id,
            self.instance_id,
            self.base.copy(),
            self.random_blades.copy(),
            self.long.copy(),
            self.shields.copy(),
            self.swarm.copy(),
            self.miasma_weakness,
            self.temporary_weakness,
            self.temporary_weakness_owner,
            self.coin_flipped,
        )

    def normal(self, side: int) -> int:
        return self.base[side] + self.random_blades[side] + self.swarm[side]

    def marker_count(self, side: int) -> int:
        return self.normal(side) + self.long[side] + self.shields[side]

    def free_slots(self, side: int) -> int:
        return max(0, MAX_MARKERS - self.marker_count(side))

    @property
    def weakness(self) -> int:
        return self.miasma_weakness + self.temporary_weakness

    def attack(self, side: int) -> int:
        return max(0, self.normal(side) + self.long[side] - self.weakness)

    def ranged_attack(self, side: int) -> int:
        return max(0, self.long[side] - self.weakness)

    def defense(self, side: int) -> int:
        return self.attack(side) + self.shields[side]

    def defending_marker_indices(self, side: int) -> list[int]:
        effective = self.attack(side)
        result: list[int] = []
        marker_index = 0
        for count, always in (
            (self.base[side], False),
            (self.random_blades[side], False),
            (self.swarm[side], False),
            (self.long[side], False),
            (self.shields[side], True),
        ):
            for _ in range(count):
                if always or marker_index < effective:
                    result.append(marker_index)
                marker_index += 1
        return result


@dataclass(slots=True)
class Cell:
    cell_type: int = CELL_EMPTY
    stone_id: str = ""
    stone: BattleStone | None = None
    owner: int = PLAYER_NONE
    placed_by: int = PLAYER_NONE

    def clone(self) -> Cell:
        return Cell(
            self.cell_type,
            self.stone_id,
            self.stone.clone() if self.stone else None,
            self.owner,
            self.placed_by,
        )


@dataclass(slots=True)
class FastState:
    catalog: StoneCatalog
    board: list[Cell] = field(default_factory=lambda: [Cell() for _ in range(16)])
    hands: dict[int, list[str]] = field(default_factory=lambda: {1: [], 2: []})
    gods: dict[int, str] = field(default_factory=lambda: {1: "", 2: ""})
    current_player: int = PLAYER_HUMAN
    empty_playable_cells: int = 16
    score_human: int = 0
    score_ai: int = 0
    is_game_over: bool = False
    winner: int = PLAYER_NONE
    next_instance_id: int = 1
    rng: random.Random | PreviewRandom = field(default_factory=random.Random)
    random_draws: int = 0

    def clone(self) -> FastState:
        result = FastState(self.catalog)
        result.board = [cell.clone() for cell in self.board]
        result.hands = {1: self.hands[1].copy(), 2: self.hands[2].copy()}
        result.gods = self.gods.copy()
        result.current_player = self.current_player
        result.empty_playable_cells = self.empty_playable_cells
        result.score_human = self.score_human
        result.score_ai = self.score_ai
        result.is_game_over = self.is_game_over
        result.winner = self.winner
        result.next_instance_id = self.next_instance_id
        result.rng = type(self.rng)()
        result.rng.setstate(self.rng.getstate())
        result.random_draws = self.random_draws
        return result

    def draw_index(self, count: int) -> int:
        if count <= 1:
            return 0
        self.random_draws += 1
        return self.rng.randrange(count)


def _sides(values: dict[str, Any]) -> list[int]:
    return [int(values.get(side, 0)) for side in SIDES]
