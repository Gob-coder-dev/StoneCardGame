"""Faithful Python counterpart of MoveEvaluator, RiposteModel and EndgameSearch.

Teacher scores are deliberately separate from RL action features. Hidden hands
are replaced by their sizes; hypothetical variants follow public lineage rules.
"""

from __future__ import annotations

import math
from collections import Counter
from functools import lru_cache
from typing import TYPE_CHECKING

import numpy as np

from .geometry import RAYS
from .godot_rng import GodotRandom, string_hash
from .state import BattleStone, FastState

RAY_TARGETS = np.full((16, 4, 3), -1, dtype=np.intp)
for _origin in range(16):
    for _side in range(4):
        _ray = RAYS[_origin][_side]
        RAY_TARGETS[_origin, _side, : len(_ray)] = _ray

if TYPE_CHECKING:
    from .core import FastSimulator


@lru_cache(maxsize=8192)
def expected_variants(
    groups: tuple[str, ...], values: tuple[float, ...], held: int, prefer_high: bool = True
) -> float:
    """Exact uniform-lineage, then uniform-form hidden-hand order statistic."""
    counts = Counter(groups)
    held = min(held, len(counts))
    if held <= 0:
        return 0.0
    coefficients = [1.0] + [0.0] * held
    fractions: dict[str, float] = {}
    previous_probability = expected = 0.0
    denominator = math.comb(len(counts), held)
    for index in sorted(range(len(values)), key=values.__getitem__, reverse=not prefer_high):
        group = groups[index]
        previous_fraction = fractions.get(group, 0.0)
        fraction = previous_fraction + 1.0 / counts[group]
        quotient_previous = 1.0
        for degree in range(1, held + 1):
            quotient = coefficients[degree] - previous_fraction * quotient_previous
            coefficients[degree] = quotient + fraction * quotient_previous
            quotient_previous = quotient
        fractions[group] = fraction
        probability = min(1.0, max(previous_probability, coefficients[held] / denominator))
        expected += values[index] * (probability - previous_probability)
        previous_probability = probability
    return expected


def possible_cards(state: FastState, player: int) -> tuple[str, ...]:
    excluded = {
        state.catalog.lineage(cell.stone_id)
        for cell in state.board
        if cell.placed_by == player and cell.stone_id
    }
    allowed = state.catalog.stones_for_god(state.gods[player]) or tuple(state.catalog.definitions)
    return tuple(card for card in allowed if state.catalog.lineage(card) not in excluded)


def aura(state: FastState, player: int) -> int:
    return sum(
        sum(cell.stone.swarm)
        for cell in state.board
        if cell.owner == player and cell.stone is not None
    )


def free_cells(state: FastState) -> list[int]:
    return [
        index for index, cell in enumerate(state.board) if cell.cell_type != -1 and cell.owner == 0
    ]


class ReplyModel:
    """Exact directional-shot model, evaluated over all candidate boards at once."""

    def __init__(self, state: FastState, player: int):
        self.player = player
        self.cards = possible_cards(state, player)
        self.groups = tuple(state.catalog.lineage(card) for card in self.cards)
        self.held = len(state.hands[player])
        shots: dict[tuple[int, int, int], int] = {}
        variants = []
        for card in self.cards:
            definition = state.catalog.definition(card)
            orientations = [BattleStone.from_definition(card, definition)]
            axis = definition.get("coin_flip", "")
            if axis:
                flipped = orientations[0].clone()
                a, b = (2, 3) if axis == "horizontal" else (0, 1)
                flipped.base[a], flipped.base[b] = flipped.base[b], flipped.base[a]
                flipped.long[a], flipped.long[b] = flipped.long[b], flipped.long[a]
                orientations.append(flipped)
            rows = []
            for monster in orientations:
                indices = []
                for side in range(4):
                    normal, long = monster.normal(side), monster.long[side]
                    if normal + long:
                        key = side, normal + long, long
                        indices.append(shots.setdefault(key, len(shots)))
                rows.append(indices)
            variants.append(rows)
        self.shots = tuple(shots)
        self.card_shots = np.zeros((len(self.cards), len(shots)), dtype=np.float64)
        for card, rows in enumerate(variants):
            for row in rows:
                self.card_shots[card, row] += 1.0 / len(rows)

    def threat_many(self, states: list[FastState]) -> np.ndarray:
        if not states or not self.cards or not self.shots or self.held <= 0:
            return np.zeros(len(states))
        owners = np.asarray([[cell.owner for cell in state.board] for state in states])
        blocked = np.asarray([[cell.cell_type == -1 for cell in state.board] for state in states])
        defenses = np.asarray(
            [
                [
                    [cell.stone.defense(side) if cell.stone else 0 for side in range(4)]
                    for cell in state.board
                ]
                for state in states
            ]
        )
        sides, adjacent, ranged = np.asarray(self.shots).T
        targets = RAY_TARGETS[:, sides, :]
        opposite = np.asarray((1, 0, 3, 2))[sides]
        alive = np.broadcast_to(
            ((owners == 0) & ~blocked)[:, :, None], (len(states), 16, len(self.shots))
        ).copy()
        hits = np.zeros(alive.shape, dtype=np.int8)
        for distance in range(3):
            target = targets[:, :, distance]
            enemy = (owners[:, target] != 0) & (owners[:, target] != self.player)
            valid = (target >= 0) & ((distance == 0) | (ranged > 0))
            alive &= valid[None, :, :] & ~blocked[:, target]
            strength = adjacent if distance == 0 else ranged
            success = strength[None, None, :] > defenses[:, target, opposite]
            hits += alive & enemy & success
            alive &= ~(enemy & (~success | (ranged[None, None, :] == 0)))
        best = np.einsum("nos,cs->noc", hits, self.card_shots).max(axis=1)
        # Many placements yield exactly the same hidden-hand reply values.
        # Integrate each distinct vector only once, without approximating it.
        unique, inverse = np.unique(best, axis=0, return_inverse=True)
        expected = np.asarray(
            [expected_variants(self.groups, tuple(row), self.held) for row in unique]
        )
        return expected[inverse]


class ProfileEvaluator:
    def __init__(self, simulator: FastSimulator, anticipation: bool):
        self.simulator = simulator
        self.state = simulator._require_state()
        self.player = self.state.current_player
        self.opponent = 3 - self.player
        self.anticipation = anticipation
        self.endgame = anticipation and self.state.empty_playable_cells <= 2
        self.cards = possible_cards(self.state, self.opponent) if self.endgame else ()
        self.reply = (
            ReplyModel(self.state, self.opponent) if anticipation and not self.endgame else None
        )
        self.aura_before = aura(self.state, self.player) if anticipation else 0

    def scores(self) -> dict[int, float]:
        if self.reply is not None:
            return self._scores_with_replies()
        result = {}
        hand = self.state.hands[self.player]
        for origin in free_cells(self.state):
            row, col = divmod(origin, 4)
            for slot, card in enumerate(hand):
                first, random = self._sample(card, row, col, 0)
                count = (2 if self.endgame else 4) if random else 1
                total = first
                for sample in range(1, count):
                    total += self._sample(card, row, col, sample)[0]
                result[slot * 16 + origin] = total / count
        return result

    def _preview(self, card: str, row: int, col: int, sample: int):
        state = self.state.clone()
        state.hands[self.opponent] = [""] * len(state.hands[self.opponent])
        state.rng = GodotRandom(string_hash(f"preview:{card}:{row}:{col}:{sample}"))
        before = state.rng.getstate()
        outcome = self.simulator.apply_move(state, row, col, card, self.player)
        return state, float(len(outcome["captures"])), before != state.rng.getstate()

    def _scores_with_replies(self) -> dict[int, float]:
        assert self.reply is not None
        states, captures, actions, counts = [], [], [], {}
        for origin in free_cells(self.state):
            row, col = divmod(origin, 4)
            for slot, card in enumerate(self.state.hands[self.player]):
                first = self._preview(card, row, col, 0)
                action = slot * 16 + origin
                count = 4 if first[2] else 1
                counts[action] = count
                for sample in range(count):
                    state, capture, _ = (
                        first if sample == 0 else self._preview(card, row, col, sample)
                    )
                    states.append(state)
                    captures.append(capture)
                    actions.append(action)
        values = np.asarray(captures) - self.reply.threat_many(states)
        values += 0.3 * np.asarray(
            [aura(state, self.player) - self.aura_before for state in states]
        )
        totals = np.bincount(actions, weights=values, minlength=128)
        return {action: float(totals[action] / count) for action, count in counts.items()}

    def _sample(self, card: str, row: int, col: int, sample: int) -> tuple[float, bool]:
        state, value, random = self._preview(card, row, col, sample)
        if self.endgame:
            state.hands[self.opponent] = list(self.cards)
            value = self._endgame(state, len(self.state.hands[self.opponent]))
        return value, random

    def _final(self, state: FastState) -> float:
        own = sum(cell.owner == self.player for cell in state.board)
        other = sum(cell.owner == self.opponent for cell in state.board)
        return (own - other) / 2.0

    def _endgame(self, state: FastState, held: int) -> float:
        cards = state.hands[self.opponent]
        free = free_cells(state)
        if not cards or held <= 0 or not free:
            return self._final(state)
        values = []
        groups = tuple(state.catalog.lineage(card) for card in cards)
        for card in cards:
            best = math.inf
            for origin in free:
                child = state.clone()
                self.simulator.apply_move(child, *divmod(origin, 4), card, self.opponent)
                used = state.catalog.lineage(card)
                child.hands[self.opponent] = [
                    c for c in child.hands[self.opponent] if state.catalog.lineage(c) != used
                ]
                # With the current two-cell threshold, the next AI move fills
                # the board. Keep legal enumeration and inherited RNG states.
                replies = free_cells(child)
                score = self._final(child)
                if replies and child.hands[self.player]:
                    score = -math.inf
                    for cell in replies:
                        for own in child.hands[self.player]:
                            final = child.clone()
                            self.simulator.apply_move(final, *divmod(cell, 4), own, self.player)
                            score = max(score, self._endgame(final, held - 1))
                best = min(best, score)
            values.append(best)
        return expected_variants(groups, tuple(values), held, False)
