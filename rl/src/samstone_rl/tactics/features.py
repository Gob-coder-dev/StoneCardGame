from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class TacticalScore:
    """Public, deterministic consequences of one legal placement."""

    immediate_captures: float
    anticipated_value: float
    reply_threat: float
    stochastic: bool
    material_delta: float

    @classmethod
    def from_sequence(cls, values: Sequence[float]) -> TacticalScore:
        if len(values) != 5:
            raise ValueError("un score tactique doit contenir cinq valeurs")
        return cls(float(values[0]), float(values[1]), float(values[2]),
                   bool(values[3]), float(values[4]))


class TacticalActionEncoder:
    """Build one relational feature vector for every stable action id.

    The card and target-cell slices come from the canonical public observation.
    Consequence scores are supplied by the rules engine and contain no hidden
    opponent hand information.
    """

    SCORE_FEATURES = 5
    POSITION_FEATURES = 3
    BOARD_FEATURES = 42
    CARD_FEATURES = 29
    OBSERVATION_SIZE = 929
    ACTION_COUNT = 128

    def __init__(self) -> None:
        self.feature_size = (
            self.CARD_FEATURES
            + self.BOARD_FEATURES
            + self.POSITION_FEATURES
            + self.SCORE_FEATURES
        )

    def encode(self, observation: np.ndarray, action_mask: np.ndarray,
               scores: Mapping[int, TacticalScore | Sequence[float]],
               out: np.ndarray | None = None) -> np.ndarray:
        if observation.shape != (self.OBSERVATION_SIZE,):
            raise ValueError("observation incompatible avec les features tactiques")
        if action_mask.shape != (self.ACTION_COUNT,):
            raise ValueError("masque incompatible avec les features tactiques")
        result = (np.zeros((self.ACTION_COUNT, self.feature_size), dtype=np.float32)
                  if out is None else out)
        if result.shape != (self.ACTION_COUNT, self.feature_size) or result.dtype != np.float32:
            raise ValueError("tampon de features tactiques incompatible")
        result.fill(0.0)
        board_width = self.BOARD_FEATURES
        card_width = self.CARD_FEATURES
        cards_offset = 16 * board_width
        for action in np.flatnonzero(action_mask):
            hand_slot, cell = divmod(int(action), 16)
            cursor = 0
            card_offset = cards_offset + hand_slot * card_width
            result[action, cursor:cursor + card_width] = observation[
                card_offset:card_offset + card_width]
            cursor += card_width
            cell_offset = cell * board_width
            result[action, cursor:cursor + board_width] = observation[
                cell_offset:cell_offset + board_width]
            cursor += board_width
            row, col = divmod(cell, 4)
            result[action, cursor:cursor + 3] = (
                hand_slot / 7.0, row / 3.0, col / 3.0)
            cursor += 3
            raw = scores.get(int(action))
            score = (raw if isinstance(raw, TacticalScore)
                     else TacticalScore.from_sequence(
                         (0, 0, 0, 0, 0) if raw is None else raw))
            result[action, cursor:] = (
                np.clip(score.immediate_captures / 4.0, -1.0, 1.0),
                np.clip(score.anticipated_value / 4.0, -1.0, 1.0),
                np.clip(score.reply_threat / 4.0, -1.0, 1.0),
                float(score.stochastic),
                np.clip(score.material_delta / 16.0, -1.0, 1.0),
            )
        return result
