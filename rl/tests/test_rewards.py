"""Shared reward contracts retain scalar/batch parity and god isolation."""

from pathlib import Path

import numpy as np
import pytest
import yaml

from samstone_rl.batch_engine import BatchSamStoneEnv
from samstone_rl.envs.samstone_env import RewardScheme, SamStoneEnv
from samstone_rl.opponents import RandomOpponent

ROOT = Path(__file__).parents[1]
CONFIG = ROOT / "configs/ppo_phase4_vectorized.yaml"
GODS = ("veskar", "nerava", "kharun", "ilyr", "sylkha", "enigma")


@pytest.mark.parametrize("agent", [1, 2])
@pytest.mark.parametrize("god", GODS)
def test_terminal_rewards_only_change_veskar(agent, god):
    inputs = {"veskar": {"win": 2, "draw": -0.25, "loss": -1}}
    reward = RewardScheme(terminal=2, terminal_by_god=inputs)
    inputs["veskar"]["loss"] = -99
    expected = (2, -0.25, -1) if god == "veskar" else (2, 0, -2)
    assert tuple(reward.terminal_reward(w, agent, god) for w in (agent, 0, 3 - agent)) == expected
    with pytest.raises(TypeError):
        reward.terminal_by_god["veskar"]["loss"] = -99


@pytest.mark.parametrize(
    "values",
    [{"win": 2}, {"win": 2, "draw": float("nan"), "loss": -1}, {"win": 2, "draw": -2, "loss": -1}],
)
def test_bad_reward_contract_rejected(values):
    with pytest.raises(ValueError):
        RewardScheme(terminal_by_god={"veskar": values})


@pytest.mark.parametrize("agent", [1, 2])
@pytest.mark.parametrize("god", ["veskar", "nerava"])
def test_reward_override_matches_between_scalar_and_batch(agent, god):
    scenario = next(
        s for s in yaml.safe_load(CONFIG.read_text())["environment"]["scenarios"] if s["god"] == god
    )
    options = {
        "config": dict(
            human_god=god,
            ai_god=god,
            human_deck=scenario["deck"],
            ai_deck=scenario["deck"],
            first_player=1,
            blocked=[[0, 0], [3, 3]],
        )
    }
    reward = RewardScheme(
        capture=0,
        multi_capture=0,
        terminal_by_god={"veskar": {"win": 2, "draw": -0.25, "loss": -1}},
    )
    with SamStoneEnv(
        backend="python", agent_player=agent, opponent=RandomOpponent(), reward_scheme=reward
    ) as scalar:
        batch = BatchSamStoneEnv(1, reward)
        try:
            _, info = scalar.reset(seed=343, options=options)
            batch.reset_one(
                0, seed=343, agent_player=agent, opponent=RandomOpponent(), options=options
            )
            done = False
            while not done:
                choice = int(np.flatnonzero(info["action_mask"])[0])
                obs, r, done, truncated, info = scalar.step(choice)
                other, br, bd, bt, bi = batch.step([choice])[0]
                assert np.array_equal(obs, other)
                assert (done, truncated) == (bd, bt)
                assert r == pytest.approx(br)
                assert info["terminal_reward"] == bi["terminal_reward"]
            assert info["terminal_reward"] == reward.terminal_reward(info["winner"], agent, god)
        finally:
            batch.close()


@pytest.mark.parametrize(
    "values", [{}, {"capture": 0}, {"final_margin": -1}, {"board_control_delta": float("nan")}]
)
def test_invalid_scoped_shaping_is_rejected(values):
    with pytest.raises(ValueError):
        RewardScheme(shaping_by_god={"veskar": values})


def test_shaping_scope_is_immutable_and_preserves_defaults_for_other_gods():
    settings = {"veskar": dict(final_margin=0, board_control_delta=0)}
    reward = RewardScheme(final_margin=0.1, board_control_delta=0.05, shaping_by_god=settings)
    settings["veskar"]["final_margin"] = 99
    for god in GODS:
        assert reward.control_delta(0, 2, god) == (0 if god == "veskar" else 0.1)
        assert (reward.board_margin(3, 0, god) == 0) == (god == "veskar")
        assert reward.terminal_reward(1, 1, god) == 2
        assert reward.terminal_reward(2, 1, god) == -2
    with pytest.raises(TypeError):
        reward.shaping_by_god["veskar"]["final_margin"] = 5


@pytest.mark.parametrize("agent", [1, 2])
@pytest.mark.parametrize("god", ["veskar", "nerava"])
def test_scoped_shaping_matches_scalar_and_batch_for_whole_games(agent, god):
    scenario = next(
        s
        for s in yaml.safe_load((ROOT / "configs/ppo_phase4_vectorized.yaml").read_text())[
            "environment"
        ]["scenarios"]
        if s["god"] == god
    )
    options = {
        "config": dict(
            human_god=god,
            ai_god=god,
            human_deck=scenario["deck"],
            ai_deck=scenario["deck"],
            first_player=1,
            blocked=[[0, 0]],
        )
    }
    reward = RewardScheme(
        capture=0,
        multi_capture=0,
        final_margin=0.1,
        board_control_delta=0.05,
        shaping_by_god={"veskar": dict(final_margin=0, board_control_delta=0)},
    )
    batch = BatchSamStoneEnv(1, reward)
    try:
        with SamStoneEnv(
            backend="python", agent_player=agent, opponent=RandomOpponent(), reward_scheme=reward
        ) as scalar:
            _, info = scalar.reset(seed=43, options=options)
            batch.reset_one(
                0, seed=43, agent_player=agent, opponent=RandomOpponent(), options=options
            )
            done = False
            while not done:
                action = int(np.flatnonzero(info["action_mask"])[0])
                obs, r, done, truncated, info = scalar.step(action)
                other, br, bd, bt, bi = batch.step([action])[0]
                assert np.array_equal(obs, other)
                assert r == pytest.approx(br) and (done, truncated) == (bd, bt)
                for key in ("control_delta_reward", "final_margin_reward", "terminal_reward"):
                    assert info[key] == bi[key]
                if god == "veskar":
                    assert info["control_delta_reward"] == info["final_margin_reward"] == 0
            assert info["episode"]["return"] == pytest.approx(bi["episode"]["return"])
    finally:
        batch.close()
