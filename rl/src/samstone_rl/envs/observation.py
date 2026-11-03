from __future__ import annotations

from collections.abc import Mapping
from typing import Any

import numpy as np


class ObservationEncoder:
    SCHEMA_VERSION = 1
    SIDES = ("top", "bottom", "left", "right")
    EFFECTS = ("weaken_adjacent", "weaken_on_failed_attack", "swarm", "shield_theft")
    GODS = ("veskar", "nerava", "kharun", "ilyr", "sylkha", "enigma")
    AFFINITIES = ("neutral",) + GODS
    COIN_AXES = ("", "horizontal", "vertical")
    BOARD_FEATURES = 42
    CARD_FEATURES = 29
    GLOBAL_FEATURES = 25

    def __init__(self, board_size: int = 4, max_hand_size: int = 8) -> None:
        self.board_size = board_size
        self.max_hand_size = max_hand_size

    def encode(self, observation: Mapping[str, Any]) -> np.ndarray:
        if int(observation.get("schema_version", -1)) != self.SCHEMA_VERSION:
            raise ValueError("version d'observation incompatible")
        observer = int(observation["observer"])
        opponent = 2 if observer == 1 else 1
        features: list[float] = []
        board = list(observation.get("board", []))
        if len(board) != self.board_size**2:
            raise ValueError(f"plateau incomplet: {len(board)} cases")
        for cell in board:
            features.extend(self._board_cell(cell, observer, opponent))
        hand = list(observation.get("hand", []))
        if len(hand) > self.max_hand_size:
            raise ValueError("main trop grande")
        for index in range(self.max_hand_size):
            features.extend(self._card(hand[index]) if index < len(hand)
                            else [0.0] * self.CARD_FEATURES)
        features.extend(self._global(observation, observer, opponent, len(hand)))
        encoded = np.asarray(features, dtype=np.float32)
        if encoded.shape != (self.get_obs_size(),):
            raise AssertionError(f"taille encodee {encoded.shape}, attendue {self.get_obs_size()}")
        return encoded

    def get_obs_size(self) -> int:
        return self.board_size**2 * self.BOARD_FEATURES + self.max_hand_size * self.CARD_FEATURES + self.GLOBAL_FEATURES

    def _board_cell(self, cell: Mapping[str, Any], observer: int, opponent: int) -> list[float]:
        owner, placed_by = int(cell.get("owner", 0)), int(cell.get("placed_by", 0))
        stone = cell.get("stone")
        values = [float(int(cell.get("cell_type", 0)) == -1), float(stone is None and int(cell.get("cell_type", 0)) == 0),
                  float(owner == observer), float(owner == opponent), float(placed_by == observer), float(placed_by == opponent)]
        if not isinstance(stone, Mapping):
            return values + [0.0] * (self.BOARD_FEATURES - len(values))
        for key in ("base_blades", "random_blade_sides", "long_blade_sides", "shield_sides", "swarm_blades"):
            values.extend(float(stone.get(key, {}).get(side, 0)) / 4.0 for side in self.SIDES)
        values.extend([float(stone.get("miasma_weakness", 0)) / 4.0,
                       float(stone.get("temporary_weakness", 0)) / 4.0])
        weakness_owner = int(stone.get("temporary_weakness_owner", 0))
        values.extend([float(weakness_owner == observer), float(weakness_owner == opponent)])
        effects = stone.get("effects", [])
        values.extend(float(effect in effects) for effect in self.EFFECTS)
        values.extend(float(stone.get("affinity") == affinity) for affinity in self.AFFINITIES)
        values.append(float(bool(stone.get("coin_flipped", False))))
        return values

    def _card(self, card: Mapping[str, Any]) -> list[float]:
        values = [1.0, float(card.get("level", 1)) / 4.0]
        for key in ("blades", "long_blades", "shields"):
            values.extend(float(card.get(key, {}).get(side, 0)) / 4.0 for side in self.SIDES)
        values.append(min(float(card.get("random_blades", 0)) / 8.0, 1.0))
        effects = card.get("effects", [])
        values.extend(float(effect in effects) for effect in self.EFFECTS)
        values.extend(float(card.get("affinity") == affinity) for affinity in self.AFFINITIES)
        values.extend(float(card.get("coin_flip", "") == axis) for axis in self.COIN_AXES)
        return values

    def _global(self, obs: Mapping[str, Any], observer: int, opponent: int, hand_size: int) -> list[float]:
        current, winner = int(obs["current_player"]), int(obs.get("winner", 0))
        own_score = int(obs["score_human"] if observer == 1 else obs["score_ai"])
        opp_score = int(obs["score_ai"] if observer == 1 else obs["score_human"])
        own_god = obs["human_god"] if observer == 1 else obs["ai_god"]
        opp_god = obs["ai_god"] if observer == 1 else obs["human_god"]
        values = [float(current == observer), float(current == opponent), own_score / 16.0, opp_score / 16.0,
                  hand_size / 8.0, float(obs["opponent_hand_size"]) / 8.0,
                  float(obs["empty_playable_cells"]) / 16.0, float(bool(obs["is_game_over"])),
                  float(winner == observer), float(winner == opponent), float(bool(obs["is_game_over"]) and winner == 0)]
        values.extend(float(own_god == god) for god in self.GODS)
        values.extend(float(opp_god == god) for god in self.GODS)
        values.extend([float(observer == 1), float(observer == 2)])
        return values
