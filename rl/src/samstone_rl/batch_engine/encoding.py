from __future__ import annotations

import numpy as np

from samstone_rl.envs.action_space import ActionCodec
from samstone_rl.envs.observation import ObservationEncoder
from samstone_rl.fast_engine.core import CELL_BLOCKED, PLAYER_NONE, FastState

from .catalog import NumericStoneCatalog


class DirectStateEncoder:
    """Encode ``FastState`` directly into checkpoint-compatible tensors."""

    def __init__(self, catalog: NumericStoneCatalog) -> None:
        self.catalog = catalog
        self.schema = ObservationEncoder()
        self.codec = ActionCodec()
        self.observation_size = self.schema.get_obs_size()

    def encode(self, state: FastState, observer: int,
               out: np.ndarray | None = None) -> np.ndarray:
        if observer not in (1, 2):
            raise ValueError("observer doit valoir 1 ou 2")
        opponent = 2 if observer == 1 else 1
        result = (np.zeros(self.observation_size, dtype=np.float32) if out is None else out)
        if result.shape != (self.observation_size,) or result.dtype != np.float32:
            raise ValueError("tampon d'observation incompatible")
        result.fill(0.0)

        width = self.schema.BOARD_FEATURES
        for cell_index, cell in enumerate(state.board):
            offset = cell_index * width
            result[offset] = float(cell.cell_type == CELL_BLOCKED)
            result[offset + 1] = float(cell.stone is None and cell.cell_type == 0)
            result[offset + 2] = float(cell.owner == observer)
            result[offset + 3] = float(cell.owner == opponent)
            result[offset + 4] = float(cell.placed_by == observer)
            result[offset + 5] = float(cell.placed_by == opponent)
            stone = cell.stone
            if stone is None:
                continue
            cursor = offset + 6
            for values in (stone.base, stone.random_blades, stone.long,
                           stone.shields, stone.swarm):
                result[cursor:cursor + 4] = np.asarray(values, dtype=np.float32) / 4.0
                cursor += 4
            result[cursor] = stone.miasma_weakness / 4.0
            result[cursor + 1] = stone.temporary_weakness / 4.0
            result[cursor + 2] = float(stone.temporary_weakness_owner == observer)
            result[cursor + 3] = float(stone.temporary_weakness_owner == opponent)
            stone_index = self.catalog.index(stone.stone_id)
            result[cursor + 4:cursor + 8] = self.catalog.effect_flags[stone_index]
            affinity = int(self.catalog.affinity_indices[stone_index])
            result[cursor + 8 + affinity] = 1.0
            result[cursor + 15] = float(stone.coin_flipped)

        board_end = 16 * width
        card_width = self.schema.CARD_FEATURES
        hand = state.hands[observer]
        if len(hand) > self.codec.max_hand_size:
            raise ValueError("main trop grande")
        for slot, stone_id in enumerate(hand):
            offset = board_end + slot * card_width
            result[offset:offset + card_width] = self.catalog.card_features[
                self.catalog.index(stone_id)]

        global_offset = board_end + self.codec.max_hand_size * card_width
        own_score = state.score_human if observer == 1 else state.score_ai
        opponent_score = state.score_ai if observer == 1 else state.score_human
        own_god = state.gods[observer]
        opponent_god = state.gods[opponent]
        winner = state.winner
        globals_ = result[global_offset:]
        globals_[:11] = (
            float(state.current_player == observer),
            float(state.current_player == opponent),
            own_score / 16.0,
            opponent_score / 16.0,
            len(hand) / 8.0,
            len(state.hands[opponent]) / 8.0,
            state.empty_playable_cells / 16.0,
            float(state.is_game_over),
            float(winner == observer),
            float(winner == opponent),
            float(state.is_game_over and winner == PLAYER_NONE),
        )
        gods = self.schema.GODS
        globals_[11 + gods.index(own_god)] = 1.0
        globals_[17 + gods.index(opponent_god)] = 1.0
        globals_[23] = float(observer == 1)
        globals_[24] = float(observer == 2)
        return result

    def action_mask(self, state: FastState, observer: int,
                    out: np.ndarray | None = None) -> np.ndarray:
        result = (np.zeros(self.codec.n_actions, dtype=np.bool_) if out is None else out)
        if result.shape != (self.codec.n_actions,) or result.dtype != np.bool_:
            raise ValueError("tampon de masque incompatible")
        result.fill(False)
        if state.is_game_over or state.current_player != observer:
            return result
        free = np.fromiter(
            (cell.cell_type != CELL_BLOCKED and cell.owner == PLAYER_NONE
             and cell.stone is None for cell in state.board),
            dtype=np.bool_, count=16)
        for hand_slot in range(len(state.hands[observer])):
            start = hand_slot * 16
            result[start:start + 16] = free
        return result
