from __future__ import annotations

import numpy as np
import pytest

from samstone_rl.batch_engine import (
    BatchSamStoneEnv,
    DirectStateEncoder,
    NumericStoneCatalog,
)
from samstone_rl.envs.observation import ObservationEncoder
from samstone_rl.envs.samstone_env import DEFAULT_CONFIG, RewardScheme, SamStoneEnv
from samstone_rl.fast_engine import FastSimulator, StoneCatalog
from samstone_rl.opponents import GodotProfileOpponent, RandomOpponent

SCENARIOS = (
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


def _config(god: str, deck: list[str]) -> dict:
    return {"human_god": god, "ai_god": god,
            "human_deck": deck, "ai_deck": deck}


@pytest.mark.parametrize(("god", "deck"), SCENARIOS)
def test_direct_encoder_matches_public_observation_encoder(god, deck):
    catalog = StoneCatalog()
    simulator = FastSimulator(catalog)
    simulator.reset({**_config(god, deck), "seed": 941, "first_player": 1,
                     "blocked": [[0, 0], [3, 3]]})
    direct = DirectStateEncoder(NumericStoneCatalog.from_catalog(catalog))
    reference = ObservationEncoder()
    turn = 0
    while True:
        state = simulator.state
        assert state is not None
        for observer in (1, 2):
            expected = reference.encode(simulator.serialize_for_player(observer))
            actual = direct.encode(state, observer)
            assert np.array_equal(actual, expected)
        if state.is_game_over:
            break
        legal = simulator.legal_actions()
        simulator.step(legal[(turn * 17) % len(legal)])
        turn += 1


@pytest.mark.parametrize("agent_player", [1, 2])
@pytest.mark.parametrize(("god", "deck"), SCENARIOS)
def test_batch_environment_matches_scalar_environment(god, deck, agent_player):
    config = _config(god, deck)
    reward = RewardScheme(capture=0.0, multi_capture=0.0, terminal=2.0,
                          final_margin=0.1, final_margin_scale=5.0,
                          board_control_delta=0.05, board_control_delta_limit=4)
    scalar = SamStoneEnv(backend="python", opponent=RandomOpponent(),
                         agent_player=agent_player, match_config=config,
                         reward_scheme=reward)
    batch = BatchSamStoneEnv(1, reward)
    options = {"config": {**config, "blocked": [[0, 0]], "first_player": 2}}
    try:
        scalar_observation, scalar_info = scalar.reset(seed=1237, options=options)
        batch_observation, batch_info = batch.reset_one(
            0, seed=1237, opponent=RandomOpponent(), agent_player=agent_player,
            options=options)
        while True:
            assert np.array_equal(batch_observation, scalar_observation)
            assert np.array_equal(batch_info["action_mask"], scalar_info["action_mask"])
            assert batch_info["winner"] == scalar_info["winner"]
            if "episode" in scalar_info:
                assert batch_info["episode"] == scalar_info["episode"]
                break
            action = int(np.flatnonzero(scalar_info["action_mask"])[-1])
            scalar_transition = scalar.step(action)
            batch_transition = batch.step([action])[0]
            scalar_observation, scalar_reward, scalar_done, scalar_truncated, scalar_info = (
                scalar_transition)
            batch_observation, batch_reward, batch_done, batch_truncated, batch_info = (
                batch_transition)
            assert batch_reward == pytest.approx(scalar_reward)
            assert batch_done == scalar_done
            assert batch_truncated == scalar_truncated
            for key in ("capture_reward", "terminal_reward", "final_margin_reward",
                        "control_delta_reward", "agent_captures", "opponent_captures"):
                assert batch_info[key] == pytest.approx(scalar_info[key])
    finally:
        scalar.close()
        batch.close()


def test_batch_environment_rejects_wrong_batch_and_illegal_actions():
    reward = RewardScheme()
    batch = BatchSamStoneEnv(2, reward)
    options = {"config": {**DEFAULT_CONFIG, "first_player": 1, "blocked": []}}
    try:
        batch.reset_many(
            [0, 1], seeds=[1, 2], opponents=[RandomOpponent(), RandomOpponent()],
            agent_players=[1, 1], options=[options, options])
        with pytest.raises(ValueError, match="2 actions attendues"):
            batch.step([0])
        with pytest.raises(ValueError, match="action illegale"):
            batch.step_one(0, 128)
    finally:
        batch.close()


@pytest.mark.parametrize(("precision", "anticipation", "anticipation_probability"), (
    (0.0, False, None), (0.25, False, None),
    (1.0, False, None), (1.0, True, None), (1.0, False, 0.25)))
def test_batch_environment_matches_profile_opponents(
        precision, anticipation, anticipation_probability):
    god, deck = SCENARIOS[4]
    config = _config(god, deck)
    reward = RewardScheme(terminal=2.0, board_control_delta=0.05)
    scalar_opponent = GodotProfileOpponent(
        precision, anticipation, anticipation_probability)
    batch_opponent = GodotProfileOpponent(
        precision, anticipation, anticipation_probability)
    scalar = SamStoneEnv(backend="python", opponent=scalar_opponent,
                         agent_player=1, match_config=config, reward_scheme=reward)
    batch = BatchSamStoneEnv(1, reward)
    options = {"config": {**config, "blocked": [[1, 2]], "first_player": 2}}
    try:
        scalar_observation, scalar_info = scalar.reset(seed=77291, options=options)
        batch_observation, batch_info = batch.reset_one(
            0, seed=77291, opponent=batch_opponent, agent_player=1, options=options)
        while "episode" not in scalar_info:
            assert np.array_equal(batch_observation, scalar_observation)
            assert np.array_equal(batch_info["action_mask"], scalar_info["action_mask"])
            action = int(np.flatnonzero(scalar_info["action_mask"])[0])
            scalar_observation, scalar_reward, scalar_done, _, scalar_info = scalar.step(action)
            batch_observation, batch_reward, batch_done, _, batch_info = batch.step([action])[0]
            assert batch_reward == pytest.approx(scalar_reward)
            assert batch_done == scalar_done
        assert batch_info["episode"] == scalar_info["episode"]
    finally:
        scalar.close()
        batch.close()
