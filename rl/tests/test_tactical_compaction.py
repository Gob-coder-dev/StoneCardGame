"""Dense pre-optimization oracle versus compact legal/sample evaluation."""

import numpy as np
from test_contracts import SCENARIOS

from samstone_rl.batch_engine.catalog import NumericStoneCatalog
from samstone_rl.fast_engine import FastSimulator, StoneCatalog
from samstone_rl.fast_engine.core import FastState
from samstone_rl.vector_engine.geometry import (
    BOARD_CELLS,
    MAX_DISTANCE,
    OPPOSITE_SIDES,
    ORIGIN_RAY_TARGETS,
    SIDES,
)
from samstone_rl.vector_engine.tactical import VectorTacticalEvaluator


def dense_reference(
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
    best = self.workspace.view("reply_best", batch)
    count = self.workspace.view("reply_count", batch)
    best.fill(0)
    blocked_expanded = blocked[:, None, None, :]
    reply_players = (3 - np.asarray(observers, dtype=np.int8))[:, None, None]
    for origin in range(BOARD_CELLS):
        origin_free = (owners[..., origin] == 0) & ~blocked_expanded[..., origin]
        count.fill(0)
        for side in range(SIDES):
            active = origin_free & legal[..., None] & (adjacent[:, side, None, None] > 0)
            for distance in range(MAX_DISTANCE):
                target = int(ORIGIN_RAY_TARGETS[origin, side, distance])
                if target < 0:
                    active[:] = False
                    break
                if distance > 0:
                    active &= ranged[:, side, None, None] > 0
                active &= ~blocked_expanded[..., target]
                target_owner = owners[..., target]
                enemy = (target_owner != 0) & (target_owner != reply_players)
                strength = (
                    adjacent[:, side, None, None] if distance == 0 else ranged[:, side, None, None]
                )
                defense = defenses[..., target, int(OPPOSITE_SIDES[side])]
                success = active & enemy & (strength > defense)
                count += success
                active &= ~(enemy & (~success | (ranged[:, side, None, None] <= 0)))
        best = np.maximum(best, count)
    return best


def test_compact_replies_match_dense_oracle_with_duplicate_and_random_samples():
    rng = np.random.default_rng(1627)
    catalog = StoneCatalog()
    evaluator = VectorTacticalEvaluator(NumericStoneCatalog.from_catalog(catalog))
    evaluator.workspace.ensure(2)
    for scenario in SCENARIOS:
        simulator = FastSimulator(catalog)
        simulator.reset(
            {
                "seed": 42,
                "human_god": scenario["god"],
                "ai_god": scenario["god"],
                "human_deck": scenario["deck"],
                "ai_deck": scenario["deck"],
            }
        )
        owners = rng.integers(0, 3, (2, 128, 4, 16), dtype=np.int8)
        defenses = rng.integers(0, 9, (2, 128, 4, 16, 4), dtype=np.int8)
        owners[:, ::2] = owners[:, ::2, :1]
        defenses[:, ::2] = defenses[:, ::2, :1]
        blocked = rng.random((2, 16)) < 0.2
        for legal in (rng.random((2, 128)) < 0.25, np.zeros((2, 128), dtype=bool)):
            args = ([simulator.state] * 2, [1, 2], owners, blocked, defenses, legal)
            expected = dense_reference(evaluator, *args).copy()
            actual = evaluator._reply_threats(*args)
            assert np.array_equal(actual, expected)


def test_parallel_tactical_matches_serial_and_closes():
    import pytest

    from samstone_rl.vector_engine.parallel import ParallelTacticalEvaluator

    catalog = StoneCatalog()
    numeric = NumericStoneCatalog.from_catalog(catalog)
    scenario = SCENARIOS[4]
    simulator = FastSimulator(catalog)
    simulator.reset(
        {
            "seed": 914,
            "human_god": scenario["god"],
            "ai_god": scenario["god"],
            "human_deck": scenario["deck"],
            "ai_deck": scenario["deck"],
            "blocked": [],
        }
    )
    serial = VectorTacticalEvaluator(numeric)
    parallel = ParallelTacticalEvaluator(numeric, workers=2)
    try:
        for batch in (128, 3, 192, 0):
            sims, observers = [simulator] * batch, [1] * batch
            masks = np.ones((batch, 128), dtype=bool)
            expected = serial.evaluate(sims, observers, masks).copy()
            actual = parallel.evaluate(sims, observers, masks)
            assert np.array_equal(expected, actual)
        assert parallel.metrics()["coverage"] == 1.0
    finally:
        parallel.close()
        parallel.close()
    with pytest.raises(RuntimeError, match="closed"):
        parallel.evaluate([], [], np.zeros((0, 128), dtype=bool))


def test_vector_package_can_be_imported_before_batch_environment():
    import subprocess
    import sys

    subprocess.run(
        [
            sys.executable,
            "-c",
            "from samstone_rl.vector_engine import VectorTacticalEvaluator; from samstone_rl.batch_engine import BatchSamStoneEnv",
        ],
        check=True,
    )
