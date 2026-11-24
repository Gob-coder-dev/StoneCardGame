"""Check frozen-policy batching against independent per-game inference."""

from types import SimpleNamespace

import numpy as np
import pytest
import torch
from test_batch_engine import SCENARIOS, _config

from samstone_rl.batch_engine import BatchSamStoneEnv
from samstone_rl.envs.samstone_env import RewardScheme
from samstone_rl.models.policy import build_policy
from samstone_rl.opponents import GodotProfileOpponent, RandomOpponent
from samstone_rl.opponents.checkpoint import CheckpointOpponent
from samstone_rl.training.league import LeagueOpponent


@pytest.mark.parametrize("architecture", ["actor_critic", "tactical_actor_critic"])
@pytest.mark.parametrize("deterministic", [False, True])
def test_batched_champions_match_scalar_games(tmp_path, monkeypatch, architecture, deterministic):
    config = {"model": {"architecture": architecture, "hidden_dim": 32, "action_hidden_dim": 16}}
    opponents, references, calls, tactical_batches = [], [], [], []
    for generation in range(2):
        torch.manual_seed(30 + generation)
        path = tmp_path / f"champion_{generation}.pt"
        torch.save({"model": build_policy(config).state_dict(), "config": config}, path)
        opponent = CheckpointOpponent(path, deterministic=deterministic)
        reference = CheckpointOpponent(path, deterministic=deterministic)
        batch_method = opponent.choose_many
        scalar_method = reference.choose_many

        def scalar_reference(requests, *, evaluate_tactics=None, method=scalar_method):
            return [
                method([(bridge, bridge.legal_actions(), rng, player)])[0]
                for bridge, _, rng, player in requests
            ]

        def check_vectorization(requests, *, evaluate_tactics, method=batch_method):
            def check_scores(masks):
                tactical_batches.append(len(requests))
                scores = evaluate_tactics(masks)
                for row, (bridge, _, _, player) in enumerate(requests):
                    reference_scores = bridge.tactical_action_scores(player)
                    actions = np.flatnonzero(masks[row])
                    expected = np.asarray(
                        [reference_scores[action] for action in actions], dtype=np.float32
                    )
                    np.testing.assert_array_equal(scores[row, actions], expected)
                return scores

            return method(requests, evaluate_tactics=check_scores)

        monkeypatch.setattr(reference, "choose_many", scalar_reference)
        monkeypatch.setattr(opponent, "choose_many", check_vectorization)
        original = opponent.model.distribution_and_value

        def record(*args, original=original, **kwargs):
            calls.append(args[0].shape[0])
            distribution, value = original(*args, **kwargs)
            # Scalar and batched BLAS can differ by float32 rounding.
            scalar_probs = torch.cat(
                [
                    original(*(arg[i : i + 1] for arg in args), **kwargs)[0].probs
                    for i in range(args[0].shape[0])
                ]
            )
            torch.testing.assert_close(distribution.probs, scalar_probs, atol=2e-6, rtol=2e-5)
            return distribution, value

        monkeypatch.setattr(opponent.model, "distribution_and_value", record)
        opponents.append(opponent)
        references.append(reference)

    def lineup(champions):
        wrapped = LeagueOpponent(
            SimpleNamespace(sample_with_metadata=lambda rng: (champions[0], "current", "current"))
        )
        return [
            champions[0],
            wrapped,
            champions[1],
            champions[0],
            champions[1],
            champions[0],
            GodotProfileOpponent(0.5),
            RandomOpponent(),
        ]

    batch = BatchSamStoneEnv(8, RewardScheme(), tactical_features=True)
    scalar = BatchSamStoneEnv(8, RewardScheme(), tactical_features=True)
    try:
        for first_player in (1, 2):
            options = [
                {
                    "config": {
                        **_config(*SCENARIOS[i % 6]),
                        "first_player": first_player,
                        "blocked": [],
                    }
                }
                for i in range(8)
            ]
            kwargs = dict(
                indices=list(range(8)),
                seeds=list(range(150, 158)),
                agent_players=[1, 2] * 4,
                options=options,
            )
            batch.reset_many(opponents=lineup(opponents), **kwargs)
            scalar.reset_many(opponents=lineup(references), **kwargs)
            while True:
                np.testing.assert_array_equal(batch.observations, scalar.observations)
                np.testing.assert_array_equal(batch.action_masks, scalar.action_masks)
                if not batch.action_masks.any():
                    break
                assert batch.action_masks.any(axis=1).all()
                actions = [int(np.flatnonzero(mask)[0]) for mask in batch.action_masks]
                actual, expected = batch.step(actions), scalar.step(actions)
                for left, right in zip(actual, expected, strict=True):
                    assert left[1:4] == right[1:4]
                    for key in ("episode", "winner", "agent_captures", "opponent_captures"):
                        assert left[4].get(key) == right[4].get(key)
            for left, right in zip(batch.slots, scalar.slots, strict=True):
                assert left.simulator.state.is_game_over
                assert left.rng.bit_generator.state == right.rng.bit_generator.state
        assert max(calls) >= 3
        if architecture == "tactical_actor_critic":
            assert max(tactical_batches) >= 3
        else:
            assert not tactical_batches
        assert opponents[0].choose_many([], evaluate_tactics=None) == []
    finally:
        batch.close()
        scalar.close()


@pytest.mark.parametrize("repeated", [False, True])
@pytest.mark.parametrize(("god", "deck"), SCENARIOS)
def test_direct_opponent_mask_matches_legal_move_codec(god, deck, repeated):
    deck = list(deck)
    if repeated:
        deck[-1] = deck[0]
    env = BatchSamStoneEnv(1, RewardScheme())
    try:
        env.reset_one(
            0,
            seed=392,
            opponent=RandomOpponent(),
            agent_player=1,
            options={
                "config": {**_config(god, deck), "first_player": 1, "blocked": [[0, 0], [3, 3]]}
            },
        )
        slot = env.slots[0]
        while not slot.simulator.state.is_game_over:
            player = slot.simulator.state.current_player
            legal = slot.simulator.legal_actions()
            hand = slot.bridge.get_state(player)["observation"]["hand"]
            expected = env.codec.legal_mask(legal, hand)
            np.testing.assert_array_equal(slot.bridge.action_mask(player), expected)
            assert not slot.bridge.action_mask(3 - player).any()
            slot.simulator.step(legal[-1])
        assert not slot.bridge.action_mask(1).any()
        assert not slot.bridge.action_mask(2).any()
    finally:
        env.close()
