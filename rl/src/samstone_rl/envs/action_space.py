from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import numpy as np


class ActionCodec:
    """Stable 8 hand slots x 16 board cells action codec."""

    def __init__(self, board_size: int = 4, max_hand_size: int = 8) -> None:
        self.board_size = board_size
        self.max_hand_size = max_hand_size
        self.total_cells = board_size * board_size
        self.n_actions = max_hand_size * self.total_cells

    def action_to_move(self, action: int, hand: Sequence[dict[str, Any]]) -> dict[str, Any]:
        if action < 0 or action >= self.n_actions:
            raise ValueError(f"action hors espace: {action}")
        card_index, cell_index = divmod(int(action), self.total_cells)
        if card_index >= len(hand):
            raise ValueError(f"emplacement de main vide: {card_index}")
        return {"row": cell_index // self.board_size, "col": cell_index % self.board_size,
                "stone_id": str(hand[card_index]["stone_id"])}

    def move_to_action(self, move: dict[str, Any], hand: Sequence[dict[str, Any]]) -> int:
        stone_id = str(move["stone_id"])
        card_index = next((index for index, card in enumerate(hand)
                           if card.get("stone_id") == stone_id), -1)
        if card_index < 0:
            raise ValueError(f"pierre absente de la main: {stone_id}")
        row, col = int(move["row"]), int(move["col"])
        if not (0 <= row < self.board_size and 0 <= col < self.board_size):
            raise ValueError(f"case hors plateau: ({row}, {col})")
        return card_index * self.total_cells + row * self.board_size + col

    def legal_mask(self, legal_moves: Sequence[dict[str, Any]],
                   hand: Sequence[dict[str, Any]]) -> np.ndarray:
        mask = np.zeros(self.n_actions, dtype=np.bool_)
        for move in legal_moves:
            mask[self.move_to_action(move, hand)] = True
        return mask
