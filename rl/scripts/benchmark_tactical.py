"""Profile tactical kernels on six gods and early/middle/late game positions."""

from __future__ import annotations

import argparse
import cProfile
import json
import pstats
import statistics
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import yaml

from samstone_rl.batch_engine.catalog import NumericStoneCatalog
from samstone_rl.batch_engine.encoding import DirectStateEncoder
from samstone_rl.fast_engine import FastSimulator, StoneCatalog
from samstone_rl.vector_engine.tactical import VectorTacticalEvaluator


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument("--iterations", type=int, default=20)
    parser.add_argument("--workers", type=int, nargs="+", default=[1, 2, 4])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if min(args.batch_size, args.iterations, *args.workers) < 1:
        parser.error("dimensions positives requises")
    config = yaml.safe_load(
        (Path(__file__).resolve().parents[1] / "configs/ppo_phase4_vectorized.yaml").read_text(
            encoding="utf-8"
        )
    )
    catalog = StoneCatalog()
    numeric = NumericStoneCatalog.from_catalog(catalog)
    encoder = DirectStateEncoder(numeric)
    rng = np.random.default_rng(50183)
    positions = []
    for scenario in config["environment"]["scenarios"]:
        sim = FastSimulator(catalog)
        sim.reset(
            {
                "seed": 50183,
                "first_player": 1,
                "blocked": [],
                "human_god": scenario["god"],
                "ai_god": scenario["god"],
                "human_deck": scenario["deck"],
                "ai_deck": scenario["deck"],
            }
        )
        for turn in range(13):
            if turn in (0, 6, 12):
                frozen = FastSimulator(catalog)
                frozen.state = sim.state.clone()
                positions.append(frozen)
            moves = sim.legal_actions()
            if not moves:
                break
            sim.step(moves[int(rng.integers(len(moves)))])
    simulators = [positions[i % len(positions)] for i in range(args.batch_size)]
    observers = [s.state.current_player for s in simulators]
    masks = np.zeros((args.batch_size, 128), dtype=bool)
    for i, (sim, observer) in enumerate(zip(simulators, observers, strict=True)):
        encoder.action_mask(sim.state, observer, masks[i])
    reference = VectorTacticalEvaluator(numeric)
    expected = reference.evaluate(simulators, observers, masks).copy()
    profile = cProfile.Profile()
    profile.enable()
    reference.evaluate(simulators, observers, masks)
    profile.disable()
    stats = pstats.Stats(profile)
    functions = sorted(
        [
            {
                "function": f"{key[0]}:{key[1]}:{key[2]}",
                "self_seconds": value[2],
                "cumulative_seconds": value[3],
            }
            for key, value in stats.stats.items()
        ],
        key=lambda x: x["cumulative_seconds"],
        reverse=True,
    )[:25]
    results = []
    for workers in args.workers:
        chunks = [
            chunk for chunk in np.array_split(np.arange(args.batch_size), workers) if len(chunk)
        ]
        evaluators = [VectorTacticalEvaluator(numeric) for _ in chunks]

        def evaluate(pair):
            evaluator, indices = pair
            return evaluator.evaluate(
                [simulators[i] for i in indices], [observers[i] for i in indices], masks[indices]
            ).copy()

        pairs = list(zip(evaluators, chunks, strict=True))
        samples = []
        with ThreadPoolExecutor(max_workers=workers) as pool:
            for iteration in range(args.iterations + 3):
                started = time.perf_counter()
                actual = np.concatenate(list(pool.map(evaluate, pairs)))
                elapsed = time.perf_counter() - started
                if not np.array_equal(expected, actual):
                    raise AssertionError("parallel tactical results differ")
                if iteration >= 3:
                    samples.append(elapsed)
        results.append(
            {"workers": workers, "median_seconds": statistics.median(samples), "samples": samples}
        )
    report = {
        "seed": 50183,
        "positions": len(positions),
        "batch_size": args.batch_size,
        "iterations": args.iterations,
        "results": results,
        "profile": functions,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
