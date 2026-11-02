from __future__ import annotations

import os

import numpy as np
import pytest

from samstone_rl.bridge.godot_process import GodotProcess
from samstone_rl.envs.samstone_env import DEFAULT_CONFIG, SamStoneEnv
from samstone_rl.fast_engine import FastEngineBridge, FastSimulator, StoneCatalog
from samstone_rl.fast_engine.core import _other, _stable_seed
from samstone_rl.fast_engine.geometry import BOARD_SIZE, DELTAS, RAYS

ALL_SCENARIOS = (
    ("inari", ["f01_n3", "f02_n3", "f04_n3", "f05_n2",
               "f07_n2", "f08_n2", "n01_n2", "n21_n1"]),
    ("izanami", ["d01_n2", "d02_n2", "d03_n2", "d04_n2",
                 "d05_n1", "d07_n1", "n12_n1", "n16_n1"]),
    ("hachiman", ["r01_n2", "r02_n2", "r03_n2", "r04_n2",
                  "r05_n1", "r06_n1", "n01_n2", "n24_n2"]),
    ("tsukuyomi", ["h01_n4", "h04_n3", "h05_n3", "h06_n2",
                   "h09_n1", "h12_n1", "n01_n3", "n21_n1"]),
    ("okuninushi", ["e01_n3", "e04_n3", "e05_n2", "e06_n2",
                    "e07_n2", "e09_n1", "n01_n2", "n16_n2"]),
    ("susanoo", ["p01_n4", "p04_n4", "p05_n3", "p08_n2",
                 "p09_n2", "p12_n1", "n01_n3", "n21_n1"]),
)


def _definition_sides(values):
    return [int(values.get(side, 0)) for side in ("top", "bottom", "left", "right")]


def _reference_reply_profile(simulator, state, player):
    played = {
        simulator.catalog.lineage(cell.stone_id) for cell in state.board
        if cell.placed_by == player and cell.stone_id
    }
    possible = [stone_id for stone_id in simulator.catalog.stones_for_god(
        state.gods[player]) if simulator.catalog.lineage(stone_id) not in played]
    adjacent = [0] * 4
    ranged = [0] * 4
    for stone_id in possible:
        definition = simulator.catalog.definition(stone_id)
        normal = _definition_sides(definition.get("blades", {}))
        long = _definition_sides(definition.get("long_blades", {}))
        random_bonus = int(definition.get("random_blades", 0))
        variants = [(normal, long)]
        axis = str(definition.get("coin_flip", ""))
        if axis:
            flipped_normal, flipped_long = normal.copy(), long.copy()
            first, second = ((2, 3) if axis == "horizontal" else (0, 1))
            flipped_normal[first], flipped_normal[second] = (
                flipped_normal[second], flipped_normal[first])
            flipped_long[first], flipped_long[second] = (
                flipped_long[second], flipped_long[first])
            variants.append((flipped_normal, flipped_long))
        for variant_normal, variant_long in variants:
            for side in range(4):
                ranged[side] = max(ranged[side], variant_long[side])
                adjacent[side] = max(
                    adjacent[side],
                    variant_normal[side] + variant_long[side] + random_bonus)
    return tuple(adjacent), tuple(ranged), bool(state.hands[player]) and bool(possible)


def _reference_reply_threat(simulator, state, player):
    adjacent, ranged, has_cards = _reference_reply_profile(simulator, state, player)
    if not has_cards:
        return 0.0
    best = 0
    for index, cell in enumerate(state.board):
        if cell.cell_type == -1 or cell.owner != 0:
            continue
        row, col = divmod(index, 4)
        captures = sum(_legacy_directional_reply_captures(
            state, row, col, player, side, adjacent[side], ranged[side])
            for side in range(4))
        best = max(best, captures)
    return float(best)


def _legacy_directional_reply_captures(state, row, col, player, side, adjacent, ranged_):
    if adjacent <= 0:
        return 0
    delta_row, delta_col = DELTAS[side]
    captures = 0
    for distance in range(1, BOARD_SIZE + 1):
        target_row = row + delta_row * distance
        target_col = col + delta_col * distance
        if not (0 <= target_row < BOARD_SIZE and 0 <= target_col < BOARD_SIZE):
            break
        if distance > 1 and ranged_ <= 0:
            break
        cell = state.board[target_row * BOARD_SIZE + target_col]
        if cell.cell_type == -1:
            break
        if cell.owner in (0, player) or cell.stone is None:
            continue
        strength = adjacent if distance == 1 else ranged_
        success = strength > cell.stone.defense((1, 0, 3, 2)[side])
        captures += int(success)
        if not success or ranged_ <= 0:
            break
    return captures


def test_precomputed_board_rays_match_the_board_geometry():
    assert RAYS[0] == ((), (4, 8, 12), (), (1, 2, 3))
    assert RAYS[5] == ((1,), (9, 13), (4,), (6, 7))
    assert all(len(cell_rays) == 4 for cell_rays in RAYS)


def _reference_move_value(simulator, state, move):
    definition = simulator.catalog.definition(str(move["stone_id"]))
    stochastic = bool(definition.get("random_blades", 0) or definition.get("coin_flip", ""))
    samples = 4 if stochastic else 1
    total = 0.0
    for sample in range(samples):
        simulation = state.clone()
        simulation.rng.seed(_stable_seed(
            str(move["stone_id"]), int(move["row"]), int(move["col"]), sample))
        result = simulator.apply_move(
            simulation, int(move["row"]), int(move["col"]),
            str(move["stone_id"]), state.current_player)
        total += len(result["captures"])
        total -= _reference_reply_threat(simulator, simulation, _other(state.current_player))
    return total / samples


def test_catalog_flattens_all_variants_and_preserves_training_cards():
    catalog = StoneCatalog()
    assert len(catalog.definitions) > 100
    assert set(catalog.gods) == {
        "inari", "izanami", "hachiman", "tsukuyomi", "okuninushi", "susanoo"}
    assert catalog.definition("f01_n3")["lineage_id"] == "f01"
    assert catalog.definition("f01_n3")["level"] == 3
    assert catalog.affinity("f01_n3") == "inari"


@pytest.mark.parametrize("agent_player", [1, 2])
def test_fast_gym_environment_completes_seeded_matches(agent_player):
    env = SamStoneEnv(backend="python", agent_player=agent_player)
    rng = np.random.default_rng(19 + agent_player)
    try:
        for seed in range(10):
            _observation, info = env.reset(seed=seed + 1)
            terminated = False
            while not terminated:
                legal = np.flatnonzero(info["action_mask"])
                assert legal.size > 0
                _observation, _reward, terminated, truncated, info = env.step(
                    int(rng.choice(legal)))
                assert not truncated
            assert info["episode"]["turns"] in (14, 15, 16)
            assert info["episode"]["score"] + info["episode"]["opponent_score"] in (
                14, 15, 16)
    finally:
        env.close()


def test_fast_profile_opponent_is_seeded_and_legal():
    first = SamStoneEnv(backend="python")
    second = SamStoneEnv(backend="python")
    try:
        options = {"config": {"blocked": [[0, 0]], "first_player": 2}}
        observation_a, info_a = first.reset(seed=991, options=options)
        observation_b, info_b = second.reset(seed=991, options=options)
        assert np.array_equal(observation_a, observation_b)
        assert np.array_equal(info_a["action_mask"], info_b["action_mask"])
    finally:
        first.close()
        second.close()


def test_optimized_profile_scores_match_full_swarm_simulation():
    deck = ["e01_n3", "e04_n3", "e05_n2", "e06_n2",
            "e07_n2", "e09_n1", "n01_n2", "n16_n2"]
    simulator = FastSimulator()
    simulator.reset({"seed": 83, "first_player": 1, "blocked": [],
                     "human_god": "okuninushi", "ai_god": "okuninushi",
                     "human_deck": deck, "ai_deck": deck})
    state = simulator.state
    assert state is not None
    for turn in range(8):
        moves = simulator.legal_actions()
        for move in moves[:24]:
            optimized = simulator._move_value(state, move, False)
            child = state.clone()
            full = simulator.apply_move(child, move["row"], move["col"],
                                        move["stone_id"], state.current_player)
            assert optimized == len(full["captures"])
        simulator.step(moves[turn % len(moves)])


def test_anticipation_does_not_read_the_opponents_hidden_cards():
    simulator = FastSimulator()
    simulator.reset({**DEFAULT_CONFIG, "seed": 337, "first_player": 1,
                     "blocked": [[0, 0]]})
    state = simulator.state
    assert state is not None
    move = simulator.legal_actions()[0]
    baseline = simulator._move_value(state, move, True)
    replacement = [stone_id for stone_id in simulator.catalog.stones_for_god("inari")
                   if stone_id not in state.hands[2]][:len(state.hands[2])]
    assert len(replacement) == len(state.hands[2])
    state.hands[2] = replacement
    assert simulator._move_value(state, move, True) == baseline


@pytest.mark.parametrize(("god", "deck"), ALL_SCENARIOS)
def test_cached_reply_profiles_match_the_uncached_reference(god, deck):
    simulator = FastSimulator()
    simulator.reset({"seed": 9871, "first_player": 1, "blocked": [[0, 0], [3, 3]],
                     "human_god": god, "ai_god": god,
                     "human_deck": deck, "ai_deck": deck})
    for turn in range(6):
        state = simulator.state
        assert state is not None
        for player in (1, 2):
            expected_adjacent, expected_ranged, has_cards = _reference_reply_profile(
                simulator, state, player)
            profile = simulator._reply_threat_profile(state, player)
            assert profile.adjacent == expected_adjacent
            assert profile.ranged == expected_ranged
            assert profile.has_cards == has_cards
            assert simulator._public_reply_threat(state, player, profile) == (
                _reference_reply_threat(simulator, state, player))
        moves = simulator.legal_actions()
        simulator.step(moves[(turn * 13) % len(moves)])


@pytest.mark.parametrize(("god", "deck"), ALL_SCENARIOS)
def test_cached_anticipation_keeps_move_values_exact(god, deck):
    simulator = FastSimulator()
    simulator.reset({"seed": 3367, "first_player": 2, "blocked": [[1, 1]],
                     "human_god": god, "ai_god": god,
                     "human_deck": deck, "ai_deck": deck})
    state = simulator.state
    assert state is not None
    profile = simulator._reply_threat_profile(state, _other(state.current_player))
    for move in simulator.legal_actions()[:12]:
        assert simulator._move_value(state, move, True, profile) == (
            _reference_move_value(simulator, state, move))


def test_reply_profile_cache_is_shared_and_bounded_by_public_state():
    catalog = StoneCatalog()
    first = FastSimulator(catalog)
    second = FastSimulator(catalog)
    assert first._reply_threat_cache is second._reply_threat_cache
    first.reset({**DEFAULT_CONFIG, "seed": 17, "first_player": 1, "blocked": []})
    state = first.state
    assert state is not None
    before = first._reply_threat_cache.cache_info()
    original = first._reply_threat_profile(state, 2)
    repeated = first._reply_threat_profile(state, 2)
    after = first._reply_threat_cache.cache_info()
    assert original is repeated
    assert after.hits == before.hits + 1


DETERMINISTIC_SCENARIOS = (
    ("hachiman", ["r01_n2", "r02_n2", "r03_n2", "r04_n2",
                  "r05_n1", "r06_n1", "n01_n2", "n24_n2"]),
    ("izanami", ["d01_n2", "d02_n2", "d03_n2", "d04_n2",
                 "d05_n1", "d07_n1", "n12_n1", "n16_n1"]),
    ("tsukuyomi", ["h01_n4", "h04_n3", "h05_n3", "h06_n2",
                   "h09_n1", "h12_n1", "n01_n3", "n21_n1"]),
)


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
@pytest.mark.parametrize(("god", "deck"), DETERMINISTIC_SCENARIOS)
def test_fast_engine_matches_godot_on_deterministic_full_match(god, deck):
    config = dict(DEFAULT_CONFIG)
    config.update({"seed": 77123, "first_player": 1, "blocked": [[0, 0]],
                   "human_god": god, "ai_god": god,
                   "human_deck": deck, "ai_deck": deck})
    fast = FastEngineBridge()
    with GodotProcess() as godot:
        fast_result = fast.reset(config, 1)
        godot_result = godot.reset(config, 1)
        _assert_public_state_equal(fast_result, godot_result)
        turn = 0
        while not fast_result["observation"]["is_game_over"]:
            assert fast_result["legal_actions"] == godot_result["legal_actions"]
            action = fast_result["legal_actions"][turn % len(fast_result["legal_actions"])]
            fast_result = fast.step(action, 1)
            godot_result = godot.step(action, 1)
            _assert_public_state_equal(fast_result, godot_result)
            turn += 1
    fast.close()


def _assert_public_state_equal(fast: dict, godot: dict) -> None:
    assert fast["observation"] == godot["observation"]
    assert fast.get("captures", []) == godot.get("captures", [])
