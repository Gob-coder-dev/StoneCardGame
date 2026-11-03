from __future__ import annotations

import random

import numpy as np

from samstone_rl.fast_engine.core import BattleStone, FastState, _stable_seed

from .catalog import PREVIEW_SAMPLES, VectorStoneCatalog
from .geometry import (
    ACTION_CELLS,
    ADJACENCY,
    OPPOSITE_SIDES,
    ORIGIN_RAY_TARGETS,
    SIDES,
)


class VectorEffectResolver:
    """Exact no-clone handling of Swarm and Shield Theft previews."""

    def __init__(self, catalog: VectorStoneCatalog) -> None:
        self.catalog = catalog

    def add_source_swarm(
            self, states: list[FastState], observers: list[int],
            board_stones: np.ndarray, owners: np.ndarray,
            instance_ids: np.ndarray, source_indices: np.ndarray,
            legal: np.ndarray, source_attack: np.ndarray,
            source_defense: np.ndarray) -> np.ndarray:
        """Apply the pre-attack Swarm bonus to hypothetical source stones."""
        changed = np.zeros_like(legal)
        source_effects = self.catalog.effect_flags[source_indices, 2]
        source_affinities = self.catalog.affinity_indices[source_indices]
        for batch, (state, player) in enumerate(zip(states, observers, strict=True)):
            god = state.catalog.gods.index(state.gods[player]) + 1
            active_board = self._active_swarm_mask(
                state, owners[batch], board_stones[batch])
            for action in np.flatnonzero(legal[batch] & source_effects[batch]):
                if source_affinities[batch, action] not in (0, god):
                    continue
                origin = int(ACTION_CELLS[action])
                if not np.any(active_board[ADJACENCY[origin]]
                              & (owners[batch, ADJACENCY[origin]] == player)):
                    continue
                active = active_board.copy()
                active[origin] = True
                hypothetical_owners = owners[batch].copy()
                hypothetical_owners[origin] = player
                component = self._component(
                    active, hypothetical_owners, origin, player)
                if len(component) <= 1:
                    continue
                changed[batch, action] = True
                source_instance = int(state.next_instance_id)
                component_instances = instance_ids[batch].copy()
                component_instances[origin] = source_instance
                stone_index = int(source_indices[batch, action])
                sample_count = (PREVIEW_SAMPLES
                                if self.catalog.stochastic[stone_index] else 1)
                for sample in range(sample_count):
                    self._apply_member_bonus(
                        source_attack[batch, action, sample],
                        source_defense[batch, action, sample], component,
                        origin, component_instances)
                if sample_count == 1:
                    source_attack[batch, action, 1:] = source_attack[batch, action, 0]
                    source_defense[batch, action, 1:] = source_defense[batch, action, 0]
        return changed

    def apply_post_move_effects(
            self, states: list[FastState], observers: list[int],
            board_stones: np.ndarray, base_raw_attacks: np.ndarray,
            instance_ids: np.ndarray, source_indices: np.ndarray,
            captures: np.ndarray, legal: np.ndarray,
            source_swarm_changed: np.ndarray,
            owners_after: np.ndarray, raw_after: np.ndarray,
            board_shields: np.ndarray, source_shields: np.ndarray) -> None:
        """Apply post-capture Pillage and recompute changed Swarm components."""
        self._apply_shield_theft(
            states, board_stones, source_indices, captures, legal,
            raw_after, source_shields)
        self._recalculate_changed_swarm(
            states, observers, board_stones, base_raw_attacks, instance_ids,
            source_indices, captures, legal, source_swarm_changed,
            owners_after, raw_after, board_shields, source_shields)

    def _apply_shield_theft(
            self, states: list[FastState], board_stones: np.ndarray,
            source_indices: np.ndarray, captures: np.ndarray,
            legal: np.ndarray, raw_after: np.ndarray,
            source_shields: np.ndarray) -> None:
        pillage = self.catalog.effect_flags[source_indices, 3]
        candidates = legal & pillage & captures.any(axis=(2, 3))
        for batch, state in enumerate(states):
            for action in np.flatnonzero(candidates[batch]):
                origin = int(ACTION_CELLS[action])
                stone_index = int(source_indices[batch, action])
                stone_id = self.catalog.numeric.stone_ids[stone_index]
                definition = self.catalog.numeric.source.definition(stone_id)
                sample_count = (PREVIEW_SAMPLES
                                if self.catalog.stochastic[stone_index] else 1)
                resolved: list[np.ndarray] = []
                for sample in range(sample_count):
                    shields = source_shields[batch, action, sample].copy()
                    marker_counts = (
                        raw_after[batch, action, sample, origin] + shields).astype(np.int8)
                    rng = self._placement_rng(stone_id, definition, origin, sample)
                    for side in range(SIDES):
                        for target in ORIGIN_RAY_TARGETS[origin, side]:
                            if target < 0:
                                break
                            target = int(target)
                            if not captures[batch, action, sample, target]:
                                continue
                            cell = state.board[target]
                            if cell.stone is None or board_stones[batch, target] < 0:
                                continue
                            marker_total = len(cell.stone.defending_marker_indices(
                                int(OPPOSITE_SIDES[side])))
                            for _ in range(marker_total):
                                destinations = [
                                    destination for destination in range(SIDES)
                                    if destination != side and marker_counts[destination] < 4
                                ]
                                if not destinations:
                                    continue
                                destination = destinations[rng.randrange(len(destinations))]
                                shields[destination] += 1
                                marker_counts[destination] += 1
                    resolved.append(shields)
                for sample in range(PREVIEW_SAMPLES):
                    chosen = resolved[sample if sample < sample_count else 0]
                    source_shields[batch, action, sample] = chosen

    def _recalculate_changed_swarm(
            self, states: list[FastState], observers: list[int],
            board_stones: np.ndarray, base_raw_attacks: np.ndarray,
            instance_ids: np.ndarray, source_indices: np.ndarray,
            captures: np.ndarray, legal: np.ndarray,
            source_swarm_changed: np.ndarray,
            owners_after: np.ndarray, raw_after: np.ndarray,
            board_shields: np.ndarray, source_shields: np.ndarray) -> None:
        valid_board = board_stones >= 0
        board_swarm = valid_board & self.catalog.effect_flags[
            np.maximum(board_stones, 0), 2]
        captured_swarm = (
            captures & board_swarm[:, None, None, :]).any(axis=(2, 3))
        changed = legal & (source_swarm_changed | captured_swarm)
        for batch, (state, player) in enumerate(zip(states, observers, strict=True)):
            god_indices = np.asarray([
                0,
                state.catalog.gods.index(state.gods[1]) + 1,
                state.catalog.gods.index(state.gods[2]) + 1,
            ], dtype=np.int8)
            for action in np.flatnonzero(changed[batch]):
                origin = int(ACTION_CELLS[action])
                source_index = int(source_indices[batch, action])
                sample_count = (PREVIEW_SAMPLES
                                if self.catalog.stochastic[source_index] else 1)
                for sample in range(sample_count):
                    stones = board_stones[batch].copy()
                    stones[origin] = source_index
                    instances = instance_ids[batch].copy()
                    instances[origin] = int(state.next_instance_id)
                    owners = owners_after[batch, action, sample]
                    valid = stones >= 0
                    safe = np.maximum(stones, 0)
                    swarm = valid & self.catalog.effect_flags[safe, 2]
                    affinities = self.catalog.affinity_indices[safe]
                    owner_gods = god_indices[owners]
                    active = swarm & ((affinities == 0) | (affinities == owner_gods))

                    # Reset every Swarm card to its non-aura attack before
                    # rebuilding connected components, exactly like Godot.
                    for cell in np.flatnonzero(swarm):
                        if cell == origin:
                            raw_after[batch, action, sample, cell] = (
                                self.catalog.attacks[source_index, origin, sample])
                        else:
                            raw_after[batch, action, sample, cell] = (
                                base_raw_attacks[batch, cell])
                    visited: set[int] = set()
                    for start in np.flatnonzero(active):
                        start = int(start)
                        if start in visited:
                            continue
                        component = self._component(
                            active, owners, start, int(owners[start]))
                        visited.update(component)
                        if len(component) <= 1:
                            continue
                        for member in component:
                            member_shields = (source_shields[batch, action, sample]
                                              if member == origin
                                              else board_shields[batch, member])
                            self._apply_member_bonus(
                                raw_after[batch, action, sample, member],
                                raw_after[batch, action, sample, member]
                                + member_shields,
                                component, member, instances)
                if sample_count == 1:
                    raw_after[batch, action, 1:] = raw_after[batch, action, 0]

    @staticmethod
    def _component(active: np.ndarray, owners: np.ndarray,
                   origin: int, owner: int) -> list[int]:
        reachable = {int(origin)}
        pending = [int(origin)]
        while pending:
            current = pending.pop()
            for neighbor in VectorEffectResolver._ordered_neighbors(current):
                if (neighbor not in reachable and active[neighbor]
                        and int(owners[neighbor]) == int(owner)):
                    reachable.add(neighbor)
                    pending.append(neighbor)
        # Re-run from the same lowest start and neighbor order as the scalar
        # engine because contribution order influences saturated faces.
        start = min(reachable)
        ordered: list[int] = []
        visited = {start}
        pending = [start]
        while pending:
            current = pending.pop()
            ordered.append(current)
            for neighbor in VectorEffectResolver._ordered_neighbors(current):
                if neighbor in reachable and neighbor not in visited:
                    visited.add(neighbor)
                    pending.append(neighbor)
        return ordered

    def _active_swarm_mask(self, state: FastState, owners: np.ndarray,
                           stones: np.ndarray) -> np.ndarray:
        valid = stones >= 0
        safe = np.maximum(stones, 0)
        swarm = valid & self.catalog.effect_flags[safe, 2]
        affinities = self.catalog.affinity_indices[safe]
        god_indices = np.asarray([
            0,
            state.catalog.gods.index(state.gods[1]) + 1,
            state.catalog.gods.index(state.gods[2]) + 1,
        ], dtype=np.int8)
        return swarm & ((affinities == 0) | (affinities == god_indices[owners]))

    @staticmethod
    def _apply_member_bonus(
            attacks: np.ndarray, defenses: np.ndarray, component: list[int],
            member: int, instance_ids: np.ndarray) -> None:
        bonus = min(4, (len(component) - 1) * 2)
        contributed = 0
        member_instance = int(instance_ids[member])
        for other in component:
            if other == member or contributed >= bonus:
                continue
            other_instance = int(instance_ids[other])
            first, second = sorted((member_instance, other_instance))
            start = _stable_seed(first, second, member_instance) % SIDES
            for blade in range(2):
                if contributed >= bonus:
                    break
                for offset in range(SIDES):
                    side = int((start + blade + offset) % SIDES)
                    if defenses[side] < 4:
                        attacks[side] += 1
                        defenses[side] += 1
                        contributed += 1
                        break

    @staticmethod
    def _ordered_neighbors(origin: int) -> list[int]:
        return [int(target) for target in ORIGIN_RAY_TARGETS[origin, :, 0]
                if target >= 0]

    @staticmethod
    def _placement_rng(stone_id: str, definition: dict,
                       origin: int, sample: int) -> random.Random:
        rng = random.Random(_stable_seed(stone_id, origin // 4, origin % 4, sample))
        stone = BattleStone.from_definition(stone_id, definition)
        for _ in range(int(definition.get("random_blades", 0))):
            candidates = [side for side in range(SIDES) if stone.free_slots(side) > 0]
            if not candidates:
                break
            stone.random_blades[candidates[rng.randrange(len(candidates))]] += 1
        if definition.get("coin_flip", ""):
            rng.randrange(2)
        return rng

