import json
import os

import pytest
import yaml

from samstone_rl.bridge.godot_process import GodotProcess
from samstone_rl.bridge.profile_oracle import ProfileOracle
from samstone_rl.bridge.protocol import Protocol
from samstone_rl.envs import ActionCodec
from samstone_rl.fast_engine import FastSimulator
from samstone_rl.fast_engine.profile_teacher import expected_variants
from samstone_rl.observability import HealthMonitor


def test_variant_expectation_matches_enumerated_hidden_hands():
    from itertools import combinations, product
    from statistics import mean

    groups = ("a", "a", "b", "b", "b", "c")
    values = (0.0, 3.0, 1.0, 2.0, 4.0, 1.5)
    by_group = {
        group: [values[i] for i, name in enumerate(groups) if name == group]
        for group in dict.fromkeys(groups)
    }
    for held in (1, 2, 3):
        for high in (False, True):
            select = max if high else min
            expected = mean(
                mean(select(hand) for hand in product(*(by_group[g] for g in chosen)))
                for chosen in combinations(by_group, held)
            )
            assert expected_variants(groups, values, held, high) == pytest.approx(
                expected, abs=1e-10
            )


def test_native_teacher_cannot_read_hidden_hand_or_start_godot(monkeypatch):
    from pathlib import Path

    from samstone_rl.batch_engine import BatchSamStoneEnv
    from samstone_rl.envs.samstone_env import RewardScheme
    from samstone_rl.opponents import GodotProfileOpponent

    def forbidden(*args, **kwargs):
        raise AssertionError("Godot entered the Python collection path")

    monkeypatch.setattr(GodotProcess, "start", forbidden)
    scenario = yaml.safe_load(
        (Path(__file__).parents[1] / "configs/ppo_phase4_vectorized.yaml").read_text(
            encoding="utf-8"
        )
    )["environment"]["scenarios"][0]
    match = dict(
        human_god=scenario["god"],
        ai_god=scenario["god"],
        human_deck=scenario["deck"],
        ai_deck=scenario["deck"],
        blocked=[],
        first_player=2,
    )
    env = BatchSamStoneEnv(1, RewardScheme(), tactical_features=True, profile_backend="python")
    try:
        env.reset_many(
            [0],
            seeds=[10],
            opponents=[GodotProfileOpponent(1.0, True)],
            agent_players=[1],
            options=[{"config": match}],
        )
        assert env.profile_oracle is None
        env.step([int(env.action_masks[0].nonzero()[0][0])])
        sim = env.slots[0].simulator
        previous = sim.state.hands[3 - sim.state.current_player]
        expected = sim.profile_action_scores(True)
        sim.state.hands[3 - sim.state.current_player] = ["hidden"] * len(previous)
        assert sim.profile_action_scores(True) == expected
        sim.state.hands[3 - sim.state.current_player] = previous
    finally:
        env.close()


def test_python_worker_scores_are_identical_to_serial_and_close():
    from pathlib import Path

    from samstone_rl.fast_engine import StoneCatalog
    from samstone_rl.fast_engine.profile_pool import PythonProfilePool

    scenario = yaml.safe_load(
        (Path(__file__).parents[1] / "configs/ppo_phase4_vectorized.yaml").read_text(
            encoding="utf-8"
        )
    )["environment"]["scenarios"][0]
    catalog = StoneCatalog()
    simulators = []
    for index in range(4):
        sim = FastSimulator(catalog)
        sim.reset(
            dict(
                seed=index + 1,
                human_god=scenario["god"],
                ai_god=scenario["god"],
                human_deck=scenario["deck"],
                ai_deck=scenario["deck"],
                blocked=[[0, 0]],
                first_player=index % 2 + 1,
            )
        )
        for _ in range(index + 1):
            sim.step(sim.legal_actions()[0])
        simulators.append(sim)
    flags = [False, True, True, False]
    expected = [
        sim.profile_action_scores(flag) for sim, flag in zip(simulators, flags, strict=True)
    ]
    pool = PythonProfilePool(catalog, 2)
    try:
        assert pool.scores(simulators, flags) == expected
    finally:
        pool.close()
        pool.close()
    with pytest.raises(RuntimeError, match="ferme"):
        pool.scores(simulators, flags)


def test_monster_wire_keys_preserve_legacy_internal_names():
    wire = Protocol.encode_request("step", 1, action={"stone_id": "test"})
    assert json.loads(wire)["action"] == {"monster_id": "test"}
    response = Protocol.decode_response('{"board":[{"monster":{"monster_id":"test"}}]}')
    assert response == {"board": [{"stone": {"stone_id": "test"}}]}


def test_health_tracks_each_stage_across_restart(tmp_path):
    monitor = HealthMonitor(tmp_path, {"plateau_evaluations": 2})

    def evaluate(stage, score):
        return monitor.check(1, {"evaluation_win_rate": score, "evaluation_stage": stage})

    assert not evaluate("easy", 0.98)
    assert not evaluate("hard", 0.72)
    assert not evaluate("hard", 0.73)
    monitor = HealthMonitor(tmp_path, {"plateau_evaluations": 2})
    assert not evaluate("hard", 0.72)
    assert any(a.code == "evaluation_plateau" for a in evaluate("hard", 0.72))
    assert monitor.evaluation_groups["easy"]["best_eval"] == 0.98


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="requires Godot")
@pytest.mark.parametrize("blocked_count", [0, 1, 2])
def test_public_teacher_scores_match_profile_ai_through_full_games(blocked_count):
    from pathlib import Path

    config = yaml.safe_load(
        (Path(__file__).parents[1] / "configs/ppo_phase4_vectorized.yaml").read_text(
            encoding="utf-8"
        )
    )
    oracle = ProfileOracle(2)
    simulator = FastSimulator()
    codec = ActionCodec()
    try:
        with GodotProcess() as bridge:
            for scenario in config["environment"]["scenarios"]:
                match = dict(
                    human_deck=scenario["deck"],
                    ai_deck=scenario["deck"],
                    human_god=scenario["god"],
                    ai_god=scenario["god"],
                    seed=9041,
                    blocked=[[0, 0], [3, 3]][:blocked_count],
                    first_player=1,
                    portable_rng=True,
                )
                bridge.reset(match, 1)
                simulator.reset(match)
                for turn in range(16 - blocked_count):
                    observer = 1 + turn % 2
                    snapshot = bridge.get_state(observer)["observation"]
                    assert snapshot["current_player"] == observer
                    requests = [
                        {"snapshot": snapshot, "anticipation": flag} for flag in (False, True)
                    ]
                    scores = oracle.scores(requests)
                    for flag, values in zip((False, True), scores, strict=True):
                        before = simulator.serialize_for_player(observer)
                        rng = simulator.state.rng.getstate()
                        opponent_rng = simulator.opponent_rng.getstate()
                        actual = simulator.profile_action_scores(flag)
                        assert before == simulator.serialize_for_player(observer)
                        assert rng == simulator.state.rng.getstate()
                        assert opponent_rng == simulator.opponent_rng.getstate()
                        assert actual == pytest.approx(values, abs=1e-8), (
                            scenario["god"],
                            turn,
                            flag,
                        )
                        move = bridge.choose_profile_action(1.0, flag)
                        action = codec.move_to_action(move, snapshot["hand"])
                        assert values[action] == pytest.approx(max(values.values()), abs=1e-6)
                    bridge.step(move, observer)
                    simulator.step(move)
    finally:
        oracle.close()
