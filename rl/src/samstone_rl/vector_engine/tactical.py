from __future__ import annotations

from dataclasses import dataclass
from time import perf_counter

import numpy as np

from samstone_rl.batch_engine.catalog import NumericStoneCatalog
from samstone_rl.fast_engine.core import FastSimulator, FastState

from .catalog import PREVIEW_SAMPLES, VectorStoneCatalog
from .effects import VectorEffectResolver
from .geometry import (
    ACTION_CELLS,
    ACTION_COUNT,
    ACTION_SLOTS,
    ADJACENCY,
    BOARD_CELLS,
    MAX_DISTANCE,
    NEIGHBORS,
    OPPOSITE_SIDES,
    ORIGIN_RAY_TARGETS,
    RAY_TARGETS,
    SIDES,
)
from .workspace import VectorWorkspace


@dataclass(frozen=True, slots=True)
class VectorTacticalStats:
    states: int
    vectorized_states: int
    vectorized_actions: int
    fallback_actions: int
    extraction_seconds: float
    kernel_seconds: float
    fallback_seconds: float

    @property
    def coverage(self) -> float:
        total = self.vectorized_actions + self.fallback_actions
        return self.vectorized_actions / total if total else 1.0


class VectorTacticalEvaluator:
    """Evaluate legal placements in dense ``[batch, action]`` arrays.

    The default kernel includes auras, weaknesses and shield theft. Disabling
    vector effects keeps an exact scalar fallback for the corresponding actions;
    both paths are covered by parity tests and their coverage is reported.
    """

    def __init__(self, catalog: NumericStoneCatalog, vector_effects: bool = True) -> None:
        self.catalog = VectorStoneCatalog.from_numeric(catalog)
        self.effects = VectorEffectResolver(self.catalog)
        self.vector_effects = bool(vector_effects)
        self.workspace = VectorWorkspace()
        self.last_stats = VectorTacticalStats(0, 0, 0, 0, 0.0, 0.0, 0.0)
        self._totals = np.zeros(7, dtype=np.float64)

    def evaluate(
        self, simulators: list[FastSimulator], observers: list[int], action_masks: np.ndarray
    ) -> np.ndarray:
        batch = len(simulators)
        if len(observers) != batch or action_masks.shape != (batch, ACTION_COUNT):
            raise ValueError("lot tactique incompatible")
        workspace = self.workspace.ensure(batch)
        scores = workspace.view("scores", batch)
        scores.fill(0.0)
        if not batch:
            return scores
        started = perf_counter()
        states = [simulator.state for simulator in simulators]
        if any(state is None for state in states):
            raise RuntimeError("simulateur non initialise")
        concrete_states = [state for state in states if state is not None]
        (
            owners,
            blocked,
            defenses,
            raw_attacks,
            base_raw_attacks,
            shields,
            temporary,
            temporary_owners,
            board_stones,
            instance_ids,
            hands,
            safe_states,
        ) = self._extract(concrete_states, observers)
        stone_indices = hands[:, ACTION_SLOTS]
        valid_stones = stone_indices >= 0
        safe_sources = np.zeros_like(valid_stones)
        safe_sources[valid_stones] = self.catalog.simple_source[stone_indices[valid_stones]]
        vector_mask = action_masks & safe_states[:, None] & safe_sources
        extraction_seconds = perf_counter() - started

        kernel_started = perf_counter()
        if np.any(vector_mask):
            accepted = self._evaluate_dense(
                concrete_states,
                observers,
                owners,
                blocked,
                defenses,
                raw_attacks,
                base_raw_attacks,
                shields,
                temporary,
                temporary_owners,
                board_stones,
                instance_ids,
                stone_indices,
                vector_mask,
                scores,
            )
            vector_mask = accepted
        kernel_seconds = perf_counter() - kernel_started

        fallback_started = perf_counter()
        fallback_actions = 0
        for index, simulator in enumerate(simulators):
            missing = action_masks[index] & ~vector_mask[index]
            if not np.any(missing):
                continue
            missing_actions = {int(action) for action in np.flatnonzero(missing)}
            reference = simulator.tactical_action_scores(observers[index], missing_actions)
            for action in missing_actions:
                scores[index, action] = reference[int(action)]
                fallback_actions += 1
        fallback_seconds = perf_counter() - fallback_started
        vectorized_actions = int(np.count_nonzero(vector_mask))
        self.last_stats = VectorTacticalStats(
            batch,
            int(np.count_nonzero(safe_states)),
            vectorized_actions,
            fallback_actions,
            extraction_seconds,
            kernel_seconds,
            fallback_seconds,
        )
        self._totals += (
            batch,
            int(np.count_nonzero(safe_states)),
            vectorized_actions,
            fallback_actions,
            extraction_seconds,
            kernel_seconds,
            fallback_seconds,
        )
        return scores

    def metrics(self, *, reset: bool = False) -> dict[str, float]:
        values = self._totals.copy()
        vectorized, fallback = values[2], values[3]
        total = vectorized + fallback
        result = {
            "states": float(values[0]),
            "vectorized_states": float(values[1]),
            "vectorized_actions": float(vectorized),
            "fallback_actions": float(fallback),
            "coverage": float(vectorized / total if total else 1.0),
            "extraction_seconds": float(values[4]),
            "kernel_seconds": float(values[5]),
            "fallback_seconds": float(values[6]),
            "workspace_capacity": float(self.workspace.capacity),
            "workspace_mb": self.workspace.allocated_bytes / (1024.0 * 1024.0),
        }
        if reset:
            self._totals.fill(0.0)
        return result

    def close(self) -> None:
        """Serial evaluators own no external resources."""

    def _extract(self, states: list[FastState], observers: list[int]) -> tuple[np.ndarray, ...]:
        batch = len(states)
        names = (
            "owners",
            "blocked",
            "defenses",
            "raw_attacks",
            "base_raw_attacks",
            "shields",
            "temporary",
            "temporary_owners",
            "board_stones",
            "instance_ids",
            "hands",
        )
        (
            owners,
            blocked,
            defenses,
            raw_attacks,
            base_raw_attacks,
            shields,
            temporary,
            temporary_owners,
            board_stones,
            instance_ids,
            hands,
        ) = (self.workspace.view(name, batch) for name in names)
        for array in (
            owners,
            blocked,
            defenses,
            raw_attacks,
            base_raw_attacks,
            shields,
            temporary,
            temporary_owners,
        ):
            array.fill(0)
        board_stones.fill(-1)
        instance_ids.fill(-1)
        hands.fill(-1)
        safe = np.ones(batch, dtype=np.bool_)
        for batch_index, (state, observer) in enumerate(zip(states, observers, strict=True)):
            if state.current_player != observer or state.is_game_over:
                safe[batch_index] = False
            hand = state.hands[observer]
            for slot, stone_id in enumerate(hand):
                hands[batch_index, slot] = self.catalog.numeric.index(stone_id)
            for cell_index, cell in enumerate(state.board):
                blocked[batch_index, cell_index] = cell.cell_type == -1
                owners[batch_index, cell_index] = cell.owner
                stone = cell.stone
                if stone is None:
                    continue
                defenses[batch_index, cell_index] = [stone.defense(side) for side in range(SIDES)]
                raw_attacks[batch_index, cell_index] = [
                    stone.normal(side) + stone.long[side] for side in range(SIDES)
                ]
                base_raw_attacks[batch_index, cell_index] = [
                    stone.base[side] + stone.random_blades[side] + stone.long[side]
                    for side in range(SIDES)
                ]
                shields[batch_index, cell_index] = stone.shields
                temporary[batch_index, cell_index] = stone.temporary_weakness
                temporary_owners[batch_index, cell_index] = stone.temporary_weakness_owner
                board_stones[batch_index, cell_index] = self.catalog.numeric.index(stone.stone_id)
                instance_ids[batch_index, cell_index] = stone.instance_id
        return (
            owners,
            blocked,
            defenses,
            raw_attacks,
            base_raw_attacks,
            shields,
            temporary,
            temporary_owners,
            board_stones,
            instance_ids,
            hands,
            safe,
        )

    def _evaluate_dense(
        self,
        states: list[FastState],
        observers: list[int],
        owners: np.ndarray,
        blocked: np.ndarray,
        defenses: np.ndarray,
        raw_attacks: np.ndarray,
        base_raw_attacks: np.ndarray,
        shields: np.ndarray,
        temporary: np.ndarray,
        temporary_owners: np.ndarray,
        board_stones: np.ndarray,
        instance_ids: np.ndarray,
        stone_indices: np.ndarray,
        vector_mask: np.ndarray,
        scores: np.ndarray,
    ) -> np.ndarray:
        batch = len(states)
        safe_indices = np.maximum(stone_indices, 0)
        cells = np.broadcast_to(ACTION_CELLS[None, :], (batch, ACTION_COUNT))
        source_attack = self.catalog.attacks[safe_indices, cells]
        source_ranged = self.catalog.ranged[safe_indices, cells]
        source_defense = self.catalog.defenses[safe_indices, cells]
        source_swarm_changed = np.zeros_like(vector_mask)
        if self.vector_effects:
            source_swarm_changed = self.effects.add_source_swarm(
                states,
                observers,
                board_stones,
                owners,
                instance_ids,
                safe_indices,
                vector_mask,
                source_attack,
                source_defense,
            )
        captures = self.workspace.view("captures", batch)
        failures = self.workspace.view("failures", batch)
        self._candidate_captures(
            owners,
            blocked,
            defenses,
            np.asarray(observers, dtype=np.int8),
            source_attack,
            source_ranged,
            vector_mask,
            captures,
            failures,
        )
        if not self.vector_effects:
            vector_mask &= ~self._complex_effect_actions(
                states, observers, owners, board_stones, safe_indices, captures
            )
        capture_counts = captures.sum(axis=-1, dtype=np.int16)

        owners_after = self.workspace.view("owners_after", batch)
        owners_after[:] = owners[:, None, None, :]
        player_values = np.asarray(observers, dtype=np.int8)[:, None, None]
        owners_after[captures] = np.broadcast_to(player_values[..., None], owners_after.shape)[
            captures
        ]
        rows = np.arange(batch)[:, None, None]
        actions = np.arange(ACTION_COUNT)[None, :, None]
        samples = np.arange(PREVIEW_SAMPLES)[None, None, :]
        owners_after[rows, actions, samples, ACTION_CELLS[None, :, None]] = player_values

        raw_after = self.workspace.view("raw_after", batch)
        raw_after[:] = raw_attacks[:, None, None, :, :]
        raw_after[rows, actions, samples, ACTION_CELLS[None, :, None], :] = source_attack
        source_shields = source_defense - source_attack
        if self.vector_effects:
            self.effects.apply_post_move_effects(
                states,
                observers,
                board_stones,
                base_raw_attacks,
                instance_ids,
                safe_indices,
                captures,
                vector_mask,
                source_swarm_changed,
                owners_after,
                raw_after,
                shields,
                source_shields,
            )

        temp_after = self.workspace.view("temp_after", batch)
        temp_after[:] = temporary[:, None, None, :]
        temp_owner_after = np.broadcast_to(temporary_owners[:, None, None, :], owners_after.shape)
        temp_after[temp_owner_after == player_values[..., None]] = 0
        source_effects = self.catalog.effect_flags[safe_indices]
        weakens_on_failure = source_effects[..., 1][..., None, None]
        temp_after += (failures & weakens_on_failure).astype(np.int8) * 2
        temp_after[rows, actions, samples, ACTION_CELLS[None, :, None]] = 0

        stone_after = self.workspace.view("stone_after", batch)
        stone_after[:] = board_stones[:, None, None, :]
        stone_after[rows, actions, samples, ACTION_CELLS[None, :, None]] = safe_indices[..., None]
        valid_cards = stone_after >= 0
        safe_cards = np.maximum(stone_after, 0)
        has_miasma = valid_cards & self.catalog.effect_flags[safe_cards, 0]
        affinities = self.catalog.affinity_indices[safe_cards]
        god_indices = np.asarray(
            [
                [
                    0,
                    self.catalog.numeric.god_index(state.gods[1]),
                    self.catalog.numeric.god_index(state.gods[2]),
                ]
                for state in states
            ],
            dtype=np.int8,
        )
        owner_gods = god_indices[np.arange(batch)[:, None, None, None], owners_after]
        active_miasma = has_miasma & ((affinities == 0) | (affinities == owner_gods))
        miasma = self.workspace.view("miasma", batch)
        miasma.fill(0)
        for target in range(BOARD_CELLS):
            neighbors = NEIGHBORS[target]
            neighbor_active = active_miasma[..., neighbors]
            neighbor_owners = owners_after[..., neighbors]
            miasma[..., target] = np.sum(
                neighbor_active & (neighbor_owners != owners_after[..., target, None]),
                axis=-1,
                dtype=np.int8,
            )
        miasma[~valid_cards] = 0
        defense_after = self.workspace.view("defense_after", batch)
        np.subtract(raw_after, temp_after[..., None], out=defense_after)
        np.subtract(defense_after, miasma[..., None], out=defense_after)
        np.maximum(defense_after, 0, out=defense_after)
        np.add(defense_after, shields[:, None, None, :, :], out=defense_after)
        defense_after[rows, actions, samples, ACTION_CELLS[None, :, None], :] += source_shields
        threats = self._reply_threats(
            states, observers, owners_after, blocked, defense_after, vector_mask
        )
        anticipated = capture_counts.astype(np.float32) - threats.astype(np.float32)
        immediate_mean = capture_counts.mean(axis=2)
        anticipated_mean = anticipated.mean(axis=2)
        reply = np.maximum(0.0, immediate_mean - anticipated_mean)
        stochastic = self.catalog.stochastic[safe_indices]
        scores[..., 0] = immediate_mean
        scores[..., 1] = anticipated_mean
        scores[..., 2] = reply
        scores[..., 3] = stochastic
        scores[..., 4] = 1.0 + 2.0 * immediate_mean
        scores[~vector_mask] = 0.0
        return vector_mask

    def _complex_effect_actions(
        self,
        states: list[FastState],
        observers: list[int],
        owners: np.ndarray,
        board_stones: np.ndarray,
        source_indices: np.ndarray,
        captures: np.ndarray,
    ) -> np.ndarray:
        source_effects = self.catalog.effect_flags[source_indices]
        fallback = source_effects[..., 3] & captures.any(axis=(2, 3))
        valid_board = board_stones >= 0
        safe_board = np.maximum(board_stones, 0)
        board_swarm = valid_board & self.catalog.effect_flags[safe_board, 2]
        fallback |= (captures & board_swarm[:, None, None, :]).any(axis=(2, 3))
        god_indices = np.asarray(
            [
                [
                    0,
                    self.catalog.numeric.god_index(state.gods[1]),
                    self.catalog.numeric.god_index(state.gods[2]),
                ]
                for state in states
            ],
            dtype=np.int8,
        )
        owner_gods = god_indices[np.arange(len(states))[:, None], owners]
        board_affinities = self.catalog.affinity_indices[safe_board]
        active_board_swarm = board_swarm & (
            (board_affinities == 0) | (board_affinities == owner_gods)
        )
        own_active_swarm = active_board_swarm & (
            owners == np.asarray(observers, dtype=np.int8)[:, None]
        )
        adjacent_swarm = np.zeros_like(fallback)
        for action, cell in enumerate(ACTION_CELLS):
            adjacent_swarm[:, action] = np.any(own_active_swarm[:, ADJACENCY[int(cell)]], axis=1)
        source_affinities = self.catalog.affinity_indices[source_indices]
        observer_gods = np.asarray(
            [
                self.catalog.numeric.god_index(state.gods[observer])
                for state, observer in zip(states, observers, strict=True)
            ],
            dtype=np.int8,
        )[:, None]
        active_source_swarm = source_effects[..., 2] & (
            (source_affinities == 0) | (source_affinities == observer_gods)
        )
        fallback |= active_source_swarm & adjacent_swarm
        return fallback

    @staticmethod
    def _candidate_captures(
        owners: np.ndarray,
        blocked: np.ndarray,
        defenses: np.ndarray,
        players: np.ndarray,
        source_attack: np.ndarray,
        source_ranged: np.ndarray,
        legal: np.ndarray,
        result: np.ndarray,
        failures: np.ndarray,
    ) -> None:
        result.fill(False)
        failures.fill(False)
        same = np.all(source_attack == source_attack[:, :, :1], axis=(2, 3)) & np.all(
            source_ranged == source_ranged[:, :, :1], axis=(2, 3)
        )
        lanes = np.broadcast_to(legal[..., None], source_attack.shape[:3]).copy()
        lanes[:, :, 1:] &= ~same[..., None]
        rows, actions, samples = np.nonzero(lanes)
        if not len(rows):
            return
        attacks = source_attack[rows, actions, samples]
        ranges = source_ranged[rows, actions, samples]
        for side in range(SIDES):
            normal, ranged = attacks[:, side], ranges[:, side]
            active = normal > 0
            for distance in range(MAX_DISTANCE):
                targets = RAY_TARGETS[actions, side, distance]
                active &= targets >= 0
                targets = np.maximum(targets, 0)
                if distance:
                    active &= ranged > 0
                active &= ~blocked[rows, targets]
                target_owners = owners[rows, targets]
                enemy = (target_owners != 0) & (target_owners != players[rows])
                defense = defenses[rows, targets, int(OPPOSITE_SIDES[side])]
                strength = normal if distance == 0 else ranged
                success = active & enemy & (strength > defense)
                failed = active & enemy & ~success
                result[rows, actions, samples, targets] |= success
                failures[rows, actions, samples, targets] |= failed
                active &= ~(enemy & (~success | (ranged <= 0)))
        for values in (result, failures):
            values[:, :, 1:] = np.where(same[..., None, None], values[:, :, :1], values[:, :, 1:])

    def _reply_threats(
        self,
        states: list[FastState],
        observers: list[int],
        owners: np.ndarray,
        blocked: np.ndarray,
        defenses: np.ndarray,
        legal: np.ndarray,
    ) -> np.ndarray:
        batch = len(states)
        adjacent = np.zeros((batch, SIDES), dtype=np.int8)
        ranged = np.zeros((batch, SIDES), dtype=np.int8)
        for index, (state, observer) in enumerate(zip(states, observers, strict=True)):
            reply_player = 2 if observer == 1 else 1
            profile = state.catalog.reply_threat_cache.profile(
                state.gods[reply_player],
                {
                    state.catalog.lineage(cell.stone_id)
                    for cell in state.board
                    if cell.placed_by == reply_player and cell.stone_id
                },
                len(state.hands[reply_player]),
            )
            adjacent[index] = profile.adjacent
            ranged[index] = profile.ranged
        # Compact legal actions and identical post-move samples. Equality is
        # checked after all effects: source randomness alone is insufficient.
        same = np.all(owners == owners[:, :, :1], axis=(2, 3)) & np.all(
            defenses == defenses[:, :, :1], axis=(2, 3, 4)
        )
        lanes = np.broadcast_to(legal[..., None], owners.shape[:3]).copy()
        lanes[:, :, 1:] &= ~same[..., None]
        rows, actions, samples = np.nonzero(lanes)
        result = self.workspace.view("reply_best", batch)
        result.fill(0)
        if not len(rows):
            return result
        # Structure-of-arrays layout makes each ray's vectors contiguous.
        own = np.ascontiguousarray(owners[rows, actions, samples].T)
        defense = np.ascontiguousarray(defenses[rows, actions, samples].transpose(1, 2, 0))
        walls = np.ascontiguousarray(blocked[rows].T)
        near, far = adjacent[rows].T, ranged[rows].T
        players = 3 - np.asarray(observers, dtype=np.int8)[rows]
        best = np.zeros(len(rows), dtype=np.int8)
        count = np.empty_like(best)
        for origin in range(BOARD_CELLS):
            free = (own[origin] == 0) & ~walls[origin]
            count.fill(0)
            for side in range(SIDES):
                active = free & (near[side] > 0)
                for distance in range(MAX_DISTANCE):
                    target = int(ORIGIN_RAY_TARGETS[origin, side, distance])
                    if target < 0:
                        break
                    if distance:
                        active &= far[side] > 0
                    active &= ~walls[target]
                    enemy = (own[target] != 0) & (own[target] != players)
                    strength = near[side] if distance == 0 else far[side]
                    success = (
                        active & enemy & (strength > defense[target, int(OPPOSITE_SIDES[side])])
                    )
                    count += success
                    active &= ~(enemy & (~success | (far[side] <= 0)))
            np.maximum(best, count, out=best)
        result[rows, actions, samples] = best
        result[:, :, 1:] = np.where(same[..., None], result[:, :, :1], result[:, :, 1:])
        return result
