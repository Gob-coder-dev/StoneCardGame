from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from typing import Any

from .anticipation import ReplyThreatProfile
from .catalog import StoneCatalog
from .geometry import BOARD_SIZE, DELTAS, OPPOSITE, RAYS, SIDE_INDEX, SIDES

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
    def from_definition(cls, stone_id: str, definition: dict[str, Any],
                        instance_id: int = 0) -> BattleStone:
        return cls(stone_id, instance_id, _sides(definition.get("blades", {})), [0] * 4,
                   _sides(definition.get("long_blades", {})),
                   _sides(definition.get("shields", {})), [0] * 4)

    def clone(self) -> BattleStone:
        return BattleStone(self.stone_id, self.instance_id, self.base.copy(),
                           self.random_blades.copy(), self.long.copy(), self.shields.copy(),
                           self.swarm.copy(), self.miasma_weakness,
                           self.temporary_weakness, self.temporary_weakness_owner,
                           self.coin_flipped)

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
        for count, always in ((self.base[side], False), (self.random_blades[side], False),
                              (self.swarm[side], False), (self.long[side], False),
                              (self.shields[side], True)):
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
        return Cell(self.cell_type, self.stone_id,
                    self.stone.clone() if self.stone else None, self.owner, self.placed_by)


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
    rng: random.Random = field(default_factory=random.Random)
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
        result.rng.setstate(self.rng.getstate())
        result.random_draws = self.random_draws
        return result

    def draw_index(self, count: int) -> int:
        if count <= 1:
            return 0
        self.random_draws += 1
        return self.rng.randrange(count)


class FastSimulator:
    """Pure Python implementation of the headless Godot match rules."""

    def __init__(self, catalog: StoneCatalog | None = None) -> None:
        self.catalog = catalog or StoneCatalog()
        self.state: FastState | None = None
        self.opponent_rng = random.Random()
        self._preview_sources: dict[tuple[str, int], BattleStone] = {}
        self._reply_threat_cache = self.catalog.reply_threat_cache

    def reset(self, config: dict[str, Any]) -> dict[str, Any]:
        self._validate_config(config)
        seed = int(config["seed"])
        setup_rng = random.Random(seed)
        state = FastState(self.catalog)
        state.rng.seed(seed)
        state.hands = {1: list(config["human_deck"]), 2: list(config["ai_deck"])}
        state.gods = {1: str(config["human_god"]), 2: str(config["ai_god"])}
        blocked = ([list(item) for item in config["blocked"]]
                   if "blocked" in config else self._draw_blocked(setup_rng))
        self._validate_blocked(blocked)
        for row, col in blocked:
            state.board[_index(int(row), int(col))].cell_type = CELL_BLOCKED
            state.empty_playable_cells -= 1
        first = int(config.get("first_player", 0))
        if first == 0:
            first = PLAYER_HUMAN if setup_rng.randrange(2) == 0 else PLAYER_AI
        if first not in (PLAYER_HUMAN, PLAYER_AI):
            raise ValueError("first_player doit valoir 1 ou 2")
        state.current_player = first
        self.state = state
        self.opponent_rng.seed(seed ^ 0x5A17C9)
        self._update_outcome()
        return {"success": True, "blocked": blocked, "first_player": first}

    def legal_actions(self) -> list[dict[str, Any]]:
        state = self._require_state()
        if state.is_game_over:
            return []
        result: list[dict[str, Any]] = []
        for index, cell in enumerate(state.board):
            if cell.cell_type == CELL_BLOCKED or cell.owner != PLAYER_NONE:
                continue
            row, col = divmod(index, BOARD_SIZE)
            for stone_id in state.hands[state.current_player]:
                result.append({"row": row, "col": col, "stone_id": stone_id})
        return result

    def step(self, action: dict[str, Any]) -> dict[str, Any]:
        state = self._require_state()
        if state.is_game_over:
            raise ValueError("la partie est terminee")
        player = state.current_player
        result = self.apply_move(state, int(action.get("row", -1)),
                                 int(action.get("col", -1)),
                                 str(action.get("stone_id", "")), player)
        self._update_outcome()
        if not state.is_game_over:
            state.current_player = _other(player)
        return {"success": True, "player": player, "done": state.is_game_over,
                "winner": state.winner, **result}

    def choose_profile_action(self, precision: float, anticipation: bool) -> dict[str, Any]:
        state = self._require_state()
        moves = self.legal_actions()
        if not moves:
            raise RuntimeError("aucune decision possible")
        if precision <= 0.0:
            return dict(moves[self.opponent_rng.randrange(len(moves))])
        plays_best = self.opponent_rng.random() < precision
        reply_profile = (self._reply_threat_profile(state, _other(state.current_player))
                         if anticipation else None)
        scored = [(move, self._move_value(state, move, anticipation, reply_profile))
                  for move in moves]
        best = max(value for _move, value in scored)
        temperature = (1.0 - precision) / precision
        weights = [1.0 if best - value <= 1e-6 else 0.0 for _move, value in scored]
        if not plays_best:
            weights = [math.exp(-(best - value) / temperature) if temperature > 0 else 0.0
                       for _move, value in scored]
        return dict(scored[_weighted_index(weights, self.opponent_rng)][0])

    def tactical_action_scores(self, observer: int) -> dict[int, tuple[float, ...]]:
        """Return deterministic public consequences for every legal action.

        Values use the same one-reply evaluator as the strongest profile bot,
        but they never select an action and never consume match/opponent RNG.
        """
        state = self._require_state()
        if observer not in (PLAYER_HUMAN, PLAYER_AI):
            raise ValueError("observer doit valoir 1 ou 2")
        if state.is_game_over or state.current_player != observer:
            return {}
        hand = state.hands[observer]
        reply_player = _other(observer)
        reply_profile = self._reply_threat_profile(state, reply_player)
        result: dict[int, tuple[float, ...]] = {}
        for move in self.legal_actions():
            stone_id = str(move["stone_id"])
            hand_slot = hand.index(stone_id)
            action = hand_slot * 16 + int(move["row"]) * 4 + int(move["col"])
            immediate = self._move_value(state, move, False)
            anticipated = self._move_value(state, move, True, reply_profile)
            definition = self.catalog.definition(stone_id)
            stochastic = bool(definition.get("random_blades", 0)
                              or definition.get("coin_flip", ""))
            reply_threat = max(0.0, immediate - anticipated)
            # Placement is +1 material; converting an enemy owner is +2.
            material_delta = 1.0 + 2.0 * immediate
            result[action] = (
                float(immediate), float(anticipated), float(reply_threat),
                float(stochastic), float(material_delta),
            )
        return result

    def apply_move(self, state: FastState, row: int, col: int, stone_id: str,
                   player: int) -> dict[str, Any]:
        if not self._valid_placement(state, row, col, stone_id, player):
            raise ValueError("invalid_placement")
        definition = self.catalog.definition(stone_id)
        stone = BattleStone.from_definition(stone_id, definition, state.next_instance_id)
        state.next_instance_id += 1
        placement_effects = self._placement_effects(state, stone, definition)
        cell = state.board[_index(row, col)]
        cell.stone_id, cell.stone, cell.owner, cell.placed_by = stone_id, stone, player, player
        state.empty_playable_cells -= 1
        state.hands[player].remove(stone_id)
        self._recalculate_swarm(state)
        attack_plan = self._resolve_attacks(state, row, col, player, stone)
        captures = attack_plan["captures"]
        for capture in captures:
            state.board[_index(capture["row"], capture["col"])].owner = player
        effects = self._post_attack_effects(state, stone, row, col, player, attack_plan)
        self._recalculate_swarm(state)
        return {"captures": captures, "attacks": attack_plan["attacks"], "effects": effects,
                "placement_effects": placement_effects,
                "placement": {"row": row, "col": col, "stone_id": stone_id,
                              "owner": player, "placement_effects": placement_effects}}

    def serialize_for_player(self, observer: int) -> dict[str, Any]:
        state = self._require_state()
        opponent = _other(observer)
        board: list[dict[str, Any]] = []
        for cell in state.board:
            board.append({"cell_type": cell.cell_type, "owner": cell.owner,
                          "placed_by": cell.placed_by,
                          "stone": self._serialize_stone(cell.stone) if cell.stone else None})
        return {
            "schema_version": 1,
            "observer": observer,
            "board_size": BOARD_SIZE,
            "board": board,
            "hand": [self._serialize_definition(stone_id) for stone_id in state.hands[observer]],
            "opponent_hand_size": len(state.hands[opponent]),
            "current_player": state.current_player,
            "empty_playable_cells": state.empty_playable_cells,
            "score_human": state.score_human,
            "score_ai": state.score_ai,
            "is_game_over": state.is_game_over,
            "winner": state.winner,
            "human_god": state.gods[1],
            "ai_god": state.gods[2],
        }

    def _move_value(self, state: FastState, move: dict[str, Any], anticipation: bool,
                    reply_profile: ReplyThreatProfile | None = None) -> float:
        definition = self.catalog.definition(str(move["stone_id"]))
        stochastic = bool(definition.get("random_blades", 0) or definition.get("coin_flip", ""))
        samples = 4 if stochastic else 1
        reply_player = _other(state.current_player)
        if anticipation and reply_profile is None:
            reply_profile = self._reply_threat_profile(state, reply_player)
        total = 0.0
        for sample in range(samples):
            preview_seed = _stable_seed(str(move["stone_id"]), int(move["row"]),
                                        int(move["col"]), sample)
            if not anticipation:
                if "swarm" in definition.get("effects", ()):
                    total += self._preview_swarm_capture_count(
                        state, int(move["row"]), int(move["col"]),
                        str(move["stone_id"]), state.current_player)
                else:
                    total += self._preview_capture_count(
                        state, int(move["row"]), int(move["col"]),
                        str(move["stone_id"]), state.current_player, preview_seed)
                continue
            simulation = state.clone()
            simulation.rng.seed(preview_seed)
            result = self.apply_move(simulation, int(move["row"]), int(move["col"]),
                                     str(move["stone_id"]), state.current_player)
            value = float(len(result["captures"]))
            if anticipation:
                value -= self._public_reply_threat(
                    simulation, reply_player, reply_profile)
            total += value
        return total / samples

    def _preview_capture_count(self, state: FastState, row: int, col: int, stone_id: str,
                               player: int, seed: int) -> float:
        """Score a non-swarm move without cloning or mutating the match.

        Post-attack effects cannot change captures already decided by
        AttackResolver. Avoiding them is equivalent to Godot's immediate
        capture evaluator and makes profile opponents inexpensive.
        """
        definition = self.catalog.definition(stone_id)
        key = (stone_id, seed)
        source = self._preview_sources.get(key)
        if source is None:
            source = BattleStone.from_definition(stone_id, definition)
            rng = random.Random(seed)
            for _ in range(int(definition.get("random_blades", 0))):
                candidates = [side for side in range(4) if source.free_slots(side) > 0]
                if not candidates:
                    break
                source.random_blades[candidates[rng.randrange(len(candidates))]] += 1
            axis = str(definition.get("coin_flip", ""))
            if axis:
                source.coin_flipped = rng.randrange(2) == 1
                if source.coin_flipped:
                    first, second = ((2, 3) if axis == "horizontal" else (0, 1))
                    for values in (source.base, source.random_blades, source.long, source.shields):
                        values[first], values[second] = values[second], values[first]
            self._preview_sources[key] = source
        return float(self._count_captures(state, row, col, player, source))

    def _preview_swarm_capture_count(self, state: FastState, row: int, col: int,
                                     stone_id: str, player: int) -> float:
        source = BattleStone.from_definition(
            stone_id, self.catalog.definition(stone_id), state.next_instance_id)
        if self.catalog.affinity(stone_id) not in ("neutral", state.gods[player]):
            return float(self._count_captures(state, row, col, player, source))
        source_index = _index(row, col)
        members = {source_index}
        active = {
            index for index, cell in enumerate(state.board)
            if cell.owner == player and self._active_power(state, cell, "swarm")
        }
        pending = [source_index]
        while pending:
            current = pending.pop()
            current_row, current_col = divmod(current, BOARD_SIZE)
            for neighbor in _adjacent_indices(current_row, current_col):
                if neighbor in active and neighbor not in members:
                    members.add(neighbor)
                    pending.append(neighbor)
        bonus = min(4, (len(members) - 1) * 2)
        contributed = 0
        for other_index in sorted(members):
            if other_index == source_index or contributed >= bonus:
                continue
            other = state.board[other_index].stone
            assert other is not None
            first, second = sorted((source.instance_id, other.instance_id))
            start_side = _stable_seed(first, second, source.instance_id) % 4
            for blade in range(2):
                if contributed >= bonus:
                    break
                for offset in range(4):
                    side = (start_side + blade + offset) % 4
                    if source.free_slots(side) > 0:
                        source.swarm[side] += 1
                        contributed += 1
                        break
        return float(self._count_captures(state, row, col, player, source))

    @staticmethod
    def _count_captures(state: FastState, row: int, col: int, player: int,
                        source: BattleStone) -> int:
        """Allocation-free capture count used only by the profile evaluator."""
        captures = 0
        for side, (dr, dc) in enumerate(DELTAS):
            long_count = source.long[side]
            if source.normal(side) + long_count == 0:
                continue
            adjacent_strength = source.attack(side)
            ranged_strength = source.ranged_attack(side)
            for distance in range(1, BOARD_SIZE + 1):
                target_row, target_col = row + dr * distance, col + dc * distance
                if not _inside(target_row, target_col) or (distance > 1 and long_count == 0):
                    break
                cell = state.board[_index(target_row, target_col)]
                if cell.cell_type == CELL_BLOCKED:
                    break
                if cell.owner in (PLAYER_NONE, player) or cell.stone is None:
                    continue
                strength = adjacent_strength if distance == 1 else ranged_strength
                success = strength > cell.stone.defense(OPPOSITE[side])
                captures += int(success)
                if not success or long_count == 0:
                    break
        return captures

    def _reply_threat_profile(self, state: FastState, player: int) -> ReplyThreatProfile:
        played_lineages = {
            self.catalog.lineage(cell.stone_id) for cell in state.board
            if cell.placed_by == player and cell.stone_id
        }
        return self._reply_threat_cache.profile(
            state.gods[player], played_lineages, len(state.hands[player]))

    def _public_reply_threat(self, state: FastState, player: int,
                             profile: ReplyThreatProfile | None = None) -> float:
        """Fast public-information upper bound for the immediate reply.

        Godot's authoritative bot integrates every possible hidden lineage.
        Doing that for every candidate placement is too expensive in Python.
        This training heuristic instead combines the strongest still-possible
        public attack in each direction. It never reads the real hidden cards;
        promotion remains decided by the exact Godot evaluator.
        """
        profile = profile or self._reply_threat_profile(state, player)
        if profile.god_id != state.gods[player]:
            raise ValueError("profil de riposte incompatible avec le dieu")
        if not profile.has_cards:
            return 0.0
        best = 0
        for index, cell in enumerate(state.board):
            if cell.cell_type == CELL_BLOCKED or cell.owner != PLAYER_NONE:
                continue
            captures = sum(self._directional_reply_captures(
                state, index, player, side,
                profile.adjacent[side], profile.ranged[side])
                for side in range(4))
            best = max(best, captures)
        return float(best)

    @staticmethod
    def _directional_reply_captures(state: FastState, origin: int, player: int,
                                    side: int, adjacent: int, ranged: int) -> int:
        if adjacent <= 0:
            return 0
        captures = 0
        for distance, target in enumerate(RAYS[origin][side], start=1):
            if distance > 1 and ranged <= 0:
                break
            cell = state.board[target]
            if cell.cell_type == CELL_BLOCKED:
                break
            if cell.owner in (PLAYER_NONE, player) or cell.stone is None:
                continue
            strength = adjacent if distance == 1 else ranged
            success = strength > cell.stone.defense(OPPOSITE[side])
            captures += int(success)
            if not success or ranged <= 0:
                break
        return captures

    def _resolve_attacks(self, state: FastState, row: int, col: int, player: int,
                         source: BattleStone) -> dict[str, Any]:
        captures: list[dict[str, Any]] = []
        attacks: list[dict[str, Any]] = []
        for side, (dr, dc) in enumerate(DELTAS):
            normal_count, long_count = source.normal(side), source.long[side]
            if normal_count + long_count == 0:
                continue
            hits: list[dict[str, Any]] = []
            adjacent_enemy = False
            endpoint: dict[str, Any] = {}
            for distance in range(1, BOARD_SIZE + 1):
                target_row, target_col = row + dr * distance, col + dc * distance
                endpoint = {"row": target_row, "col": target_col,
                            "distance": distance, "type": "exit"}
                if not _inside(target_row, target_col):
                    break
                if distance > 1 and long_count == 0:
                    break
                target_cell = state.board[_index(target_row, target_col)]
                if target_cell.cell_type == CELL_BLOCKED:
                    endpoint["type"] = "blocked"
                    break
                if (target_cell.owner == PLAYER_NONE or target_cell.owner == player
                        or target_cell.stone is None):
                    continue
                adjacent_enemy = adjacent_enemy or distance == 1
                target = target_cell.stone
                defense_side = OPPOSITE[side]
                strength = source.attack(side) if distance == 1 else source.ranged_attack(side)
                defense = target.defense(defense_side)
                success = strength > defense
                hit = {"row": target_row, "col": target_col, "distance": distance,
                       "attack": strength, "defense": defense, "success": success}
                hits.append(hit)
                if success:
                    captures.append({
                        "row": target_row, "col": target_col, "direction": SIDES[side],
                        "distance": distance, "defense_side": SIDES[defense_side],
                        "stolen_strength": target.attack(defense_side) + target.shields[defense_side],
                        "stolen_markers": target.defending_marker_indices(defense_side),
                    })
                if not success or long_count == 0:
                    endpoint["type"] = "enemy"
                    break
            if hits:
                attacks.append({"direction": SIDES[side], "adjacent_enemy": adjacent_enemy,
                                "normal_count": normal_count if adjacent_enemy else 0,
                                "long_count": long_count, "hits": hits, "endpoint": endpoint})
        return {"captures": captures, "attacks": attacks}

    def _placement_effects(self, state: FastState, stone: BattleStone,
                           definition: dict[str, Any]) -> list[dict[str, Any]]:
        events: list[dict[str, Any]] = []
        for _ in range(int(definition.get("random_blades", 0))):
            candidates = [side for side in range(4) if stone.free_slots(side) > 0]
            if not candidates:
                break
            chosen = candidates[state.draw_index(len(candidates))]
            stone.random_blades[chosen] += 1
            events.append({"type": "random_blade", "side": SIDES[chosen]})
        axis = str(definition.get("coin_flip", ""))
        if axis:
            flipped = state.draw_index(2) == 1
            stone.coin_flipped = flipped
            if flipped:
                first, second = ((2, 3) if axis == "horizontal" else (0, 1))
                for values in (stone.base, stone.random_blades, stone.long, stone.shields):
                    values[first], values[second] = values[second], values[first]
            events.append({"type": "coin_flip", "axis": axis, "flipped": flipped})
        return events

    def _post_attack_effects(self, state: FastState, source: BattleStone, row: int, col: int,
                             player: int, attack_plan: dict[str, Any]) -> list[dict[str, Any]]:
        events = self._update_miasma(state, row, col)
        if self.catalog.has_effect(source.stone_id, "shield_theft"):
            events.extend(self._shield_theft(state, source, row, col, attack_plan["captures"]))
        events.extend(self._expire_weakness(state, player))
        if self.catalog.has_effect(source.stone_id, "weaken_on_failed_attack"):
            events.extend(self._failed_attack_weakness(
                state, row, col, player, attack_plan["attacks"]))
        return events

    def _update_miasma(self, state: FastState, source_row: int,
                        source_col: int) -> list[dict[str, Any]]:
        active = [self._active_power(state, cell, "weaken_adjacent") for cell in state.board]
        if not any(active) and not any(cell.stone and cell.stone.miasma_weakness
                                       for cell in state.board):
            return []
        events: list[dict[str, Any]] = []
        for index, cell in enumerate(state.board):
            if cell.stone is None:
                continue
            row, col = divmod(index, BOARD_SIZE)
            aura = 0
            for neighbor in _adjacent_indices(row, col):
                if active[neighbor] and state.board[neighbor].owner != cell.owner:
                    aura += 1
            before = cell.stone.weakness
            if aura == cell.stone.miasma_weakness:
                continue
            increased = aura > cell.stone.miasma_weakness
            cell.stone.miasma_weakness = aura
            events.append({"type": "weaken" if increased else "weakness_expired",
                           "row": row, "col": col, "amount": abs(cell.stone.weakness - before),
                           "weakness_before": before, "weakness_after": cell.stone.weakness,
                           "source_row": source_row if increased else -1,
                           "source_col": source_col if increased else -1, "scope": "adjacent"})
        return events

    def _failed_attack_weakness(self, state: FastState, row: int, col: int, player: int,
                                attacks: list[dict[str, Any]]) -> list[dict[str, Any]]:
        events: list[dict[str, Any]] = []
        for attack in attacks:
            for hit in attack["hits"]:
                if hit["success"]:
                    continue
                cell = state.board[_index(hit["row"], hit["col"])]
                if cell.stone is None or cell.owner in (PLAYER_NONE, player):
                    continue
                before = cell.stone.weakness
                cell.stone.temporary_weakness += 2
                cell.stone.temporary_weakness_owner = player
                events.append({"type": "temporary_weaken", "row": hit["row"],
                               "col": hit["col"], "amount": cell.stone.weakness - before,
                               "weakness_before": before,
                               "weakness_after": cell.stone.weakness,
                               "source_row": row, "source_col": col,
                               "scope": "failed_attack"})
        return events

    @staticmethod
    def _expire_weakness(state: FastState, player: int) -> list[dict[str, Any]]:
        events: list[dict[str, Any]] = []
        for index, cell in enumerate(state.board):
            if cell.stone is None or cell.stone.temporary_weakness_owner != player:
                continue
            before = cell.stone.weakness
            cell.stone.temporary_weakness = 0
            cell.stone.temporary_weakness_owner = PLAYER_NONE
            row, col = divmod(index, BOARD_SIZE)
            events.append({"type": "weakness_expired", "row": row, "col": col,
                           "amount": before - cell.stone.weakness,
                           "weakness_before": before, "weakness_after": cell.stone.weakness,
                           "source_row": -1, "source_col": -1, "scope": ""})
        return events

    def _shield_theft(self, state: FastState, source: BattleStone, row: int, col: int,
                      captures: list[dict[str, Any]]) -> list[dict[str, Any]]:
        before = _side_dict(source.shields)
        placements: list[str] = []
        transfers: list[dict[str, Any]] = []
        for capture in captures:
            attacking = SIDE_INDEX[capture["direction"]]
            for marker_index in capture["stolen_markers"]:
                candidates = [side for side in range(4)
                              if side != attacking and source.free_slots(side) > 0]
                if not candidates:
                    continue
                destination = candidates[state.draw_index(len(candidates))]
                source.shields[destination] += 1
                placements.append(SIDES[destination])
                transfers.append({"row": capture["row"], "col": capture["col"],
                                  "direction": capture["direction"],
                                  "defense_side": capture["defense_side"],
                                  "marker_index": marker_index,
                                  "candidate_sides": [SIDES[item] for item in candidates],
                                  "destination_side": SIDES[destination]})
        if not transfers:
            return []
        return [{"type": "shield_theft", "row": row, "col": col,
                 "amount": len(transfers), "placements": placements,
                 "shields_before": before, "origins": captures, "transfers": transfers}]

    def _recalculate_swarm(self, state: FastState) -> None:
        members: set[int] = set()
        for index, cell in enumerate(state.board):
            if cell.stone is None or not self.catalog.has_effect(cell.stone.stone_id, "swarm"):
                continue
            cell.stone.swarm[:] = [0] * 4
            if self._active_power(state, cell, "swarm"):
                members.add(index)
        visited: set[int] = set()
        for start in sorted(members):
            if start in visited:
                continue
            owner = state.board[start].owner
            component: list[int] = []
            pending = [start]
            visited.add(start)
            while pending:
                current = pending.pop()
                component.append(current)
                row, col = divmod(current, BOARD_SIZE)
                for neighbor in _adjacent_indices(row, col):
                    if (neighbor not in visited and neighbor in members
                            and state.board[neighbor].owner == owner):
                        visited.add(neighbor)
                        pending.append(neighbor)
            bonus = min(4, (len(component) - 1) * 2)
            for member_index in component:
                stone = state.board[member_index].stone
                assert stone is not None
                contributed = 0
                for other_index in component:
                    if other_index == member_index or contributed >= bonus:
                        continue
                    other = state.board[other_index].stone
                    assert other is not None
                    first, second = sorted((stone.instance_id, other.instance_id))
                    start_side = _stable_seed(first, second, stone.instance_id) % 4
                    for blade in range(2):
                        if contributed >= bonus:
                            break
                        for offset in range(4):
                            side = (start_side + blade + offset) % 4
                            if stone.free_slots(side) > 0:
                                stone.swarm[side] += 1
                                contributed += 1
                                break

    def _active_power(self, state: FastState, cell: Cell, effect: str) -> bool:
        if cell.owner == PLAYER_NONE or cell.stone is None:
            return False
        if not self.catalog.has_effect(cell.stone.stone_id, effect):
            return False
        affinity = self.catalog.affinity(cell.stone.stone_id)
        return bool(affinity and affinity in ("neutral", state.gods[cell.owner]))

    def _serialize_definition(self, stone_id: str) -> dict[str, Any]:
        definition = self.catalog.definition(stone_id)
        return {"stone_id": stone_id, "affinity": definition["affinity"],
                "level": int(definition.get("level", 1)),
                "blades": dict(definition.get("blades", {})),
                "long_blades": dict(definition.get("long_blades", {})),
                "shields": dict(definition.get("shields", {})),
                "random_blades": int(definition.get("random_blades", 0)),
                "effects": list(definition.get("effects", [])),
                "coin_flip": str(definition.get("coin_flip", ""))}

    def _serialize_stone(self, stone: BattleStone) -> dict[str, Any]:
        result = self._serialize_definition(stone.stone_id)
        result.update({"instance_id": stone.instance_id, "base_blades": _side_dict(stone.base),
                       "random_blade_sides": _side_dict(stone.random_blades),
                       "long_blade_sides": _side_dict(stone.long),
                       "shield_sides": _side_dict(stone.shields),
                       "swarm_blades": _side_dict(stone.swarm),
                       "miasma_weakness": stone.miasma_weakness,
                       "temporary_weakness": stone.temporary_weakness,
                       "temporary_weakness_owner": stone.temporary_weakness_owner,
                       "coin_flipped": stone.coin_flipped})
        return result

    def _update_outcome(self) -> None:
        state = self._require_state()
        state.score_human = sum(cell.owner == PLAYER_HUMAN for cell in state.board)
        state.score_ai = sum(cell.owner == PLAYER_AI for cell in state.board)
        state.is_game_over = state.empty_playable_cells <= 0
        if state.is_game_over:
            state.winner = (PLAYER_HUMAN if state.score_human > state.score_ai else
                            PLAYER_AI if state.score_ai > state.score_human else PLAYER_NONE)

    def _valid_placement(self, state: FastState, row: int, col: int, stone_id: str,
                         player: int) -> bool:
        if player not in (1, 2) or not _inside(row, col) or stone_id not in state.hands[player]:
            return False
        cell = state.board[_index(row, col)]
        return cell.cell_type != CELL_BLOCKED and cell.owner == PLAYER_NONE and not cell.stone_id

    def _validate_config(self, config: dict[str, Any]) -> None:
        if "seed" not in config or int(config["seed"]) != config["seed"]:
            raise ValueError("seed entier obligatoire")
        for side in ("human", "ai"):
            god = str(config.get(f"{side}_god", ""))
            deck = config.get(f"{side}_deck")
            if god not in self.catalog.gods:
                raise ValueError(f"dieu inconnu pour {side}")
            if not isinstance(deck, (list, tuple)) or len(deck) != 8:
                raise ValueError(f"{side}_deck invalide")
            if any(stone_id not in self.catalog.definitions for stone_id in deck):
                raise ValueError(f"pierre inconnue dans {side}_deck")

    @staticmethod
    def _validate_blocked(blocked: list[list[int]]) -> None:
        positions = {(int(row), int(col)) for row, col in blocked}
        if len(blocked) > 2 or len(positions) != len(blocked):
            raise ValueError("terrain bloque invalide")
        if any(not _inside(row, col) for row, col in positions):
            raise ValueError("case bloquee hors plateau")

    @staticmethod
    def _draw_blocked(rng: random.Random) -> list[list[int]]:
        roll = rng.randrange(100)
        count = 0 if roll < 40 else 1 if roll < 75 else 2
        cells = [[index // 4, index % 4] for index in range(16)]
        result: list[list[int]] = []
        for _ in range(count):
            result.append(cells.pop(rng.randrange(len(cells))))
        return result

    def _require_state(self) -> FastState:
        if self.state is None:
            raise RuntimeError("aucune partie active")
        return self.state


def _sides(values: dict[str, Any]) -> list[int]:
    return [int(values.get(side, 0)) for side in SIDES]


def _side_dict(values: list[int]) -> dict[str, int]:
    return {side: int(values[index]) for index, side in enumerate(SIDES)}


def _index(row: int, col: int) -> int:
    return row * BOARD_SIZE + col


def _inside(row: int, col: int) -> bool:
    return 0 <= row < BOARD_SIZE and 0 <= col < BOARD_SIZE


def _adjacent_indices(row: int, col: int) -> list[int]:
    return [_index(row + dr, col + dc) for dr, dc in DELTAS if _inside(row + dr, col + dc)]


def _other(player: int) -> int:
    return PLAYER_AI if player == PLAYER_HUMAN else PLAYER_HUMAN


def _weighted_index(weights: list[float], rng: random.Random) -> int:
    target = rng.random() * sum(weights)
    chosen = 0
    for index, weight in enumerate(weights):
        if weight <= 0:
            continue
        chosen = index
        target -= weight
        if target < 0:
            break
    return chosen


def _stable_seed(*parts: object) -> int:
    value = 0xCBF29CE484222325
    for byte in ":".join(map(str, parts)).encode("utf-8"):
        value = ((value ^ byte) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return value
