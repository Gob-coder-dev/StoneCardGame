import numpy as np

from samstone_rl.bridge.protocol import Protocol
from samstone_rl.envs.action_space import ActionCodec
from samstone_rl.envs.observation import ObservationEncoder
from samstone_rl.envs.samstone_env import RewardScheme


def test_protocol_rejects_non_object_json():
    assert Protocol.decode_response("[]") is None
    assert Protocol.decode_response("not-json") is None


def test_action_codec_round_trip_and_boolean_mask():
    codec = ActionCodec()
    hand = [{"stone_id": "a"}, {"stone_id": "b"}]
    move = {"row": 2, "col": 3, "stone_id": "b"}
    action = codec.move_to_action(move, hand)
    assert codec.action_to_move(action, hand) == move
    mask = codec.legal_mask([move], hand)
    assert mask.dtype == np.bool_
    assert mask.sum() == 1 and mask[action]


def test_tactically_different_cards_have_different_features():
    encoder = ObservationEncoder()
    base = {"level": 1, "blades": {}, "long_blades": {}, "shields": {},
            "random_blades": 0, "effects": [], "affinity": "neutral", "coin_flip": ""}
    random_card = {**base, "random_blades": 4}
    shield_card = {**base, "shields": {"top": 4}}
    assert encoder._card(base) != encoder._card(random_card)
    assert encoder._card(random_card) != encoder._card(shield_card)


def test_capture_reward_is_small_and_symmetric():
    rewards = RewardScheme()
    assert rewards.captures(0) == 0.0
    assert np.isclose(rewards.captures(1), 0.10)
    assert np.isclose(rewards.captures(2), 0.225)
    assert np.isclose(rewards.captures(3), 0.35)
    assert rewards.captures(3) - rewards.captures(2) < rewards.terminal


def test_final_margin_reward_is_bounded_and_zero_by_default():
    assert RewardScheme().board_margin(10, 0) == 0.0
    rewards = RewardScheme(final_margin=0.10, final_margin_scale=5.0)
    assert 0.0 < rewards.board_margin(8, 2) < 0.10
    assert -0.10 < rewards.board_margin(2, 8) < 0.0
    assert np.isclose(rewards.board_margin(5, 5), 0.0)


def test_control_delta_reward_is_bounded_and_rewards_durable_control():
    assert RewardScheme().control_delta(2, 5) == 0.0
    rewards = RewardScheme(board_control_delta=0.05, board_control_delta_limit=4)
    assert np.isclose(rewards.control_delta(0, 10), 0.20)
    assert np.isclose(rewards.control_delta(3, -10), -0.20)
    assert np.isclose(rewards.control_delta(4, 4), 0.0)
