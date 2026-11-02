#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import time
from pathlib import Path

import numpy as np

from samstone_rl.bridge.process_pool import GodotProcessPool
from samstone_rl.envs.samstone_env import DEFAULT_CONFIG


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Mesure le debit du simulateur Godot batche et multi-processus.")
    parser.add_argument("--games", type=int, default=1000)
    parser.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--seed", type=int, default=424242)
    parser.add_argument("--godot", type=Path)
    args = parser.parse_args()
    if args.games <= 0 or args.workers <= 0 or args.batch_size <= 0:
        parser.error("games, workers et batch-size doivent etre strictement positifs")

    rng = np.random.default_rng(args.seed)
    completed = 0
    next_game = 0
    active: dict[str, dict] = {}
    started = time.perf_counter()
    with GodotProcessPool(args.workers, godot_path=args.godot) as pool:
        while completed < args.games:
            capacity = min(args.batch_size - len(active), args.games - next_game)
            if capacity > 0:
                resets = []
                for _ in range(capacity):
                    match_id = f"benchmark-{next_game}"
                    config = dict(DEFAULT_CONFIG)
                    config.update({"seed": args.seed + next_game,
                                   "first_player": 1 + next_game % 2, "blocked": []})
                    resets.append({"match_id": match_id, "observer": 1, "config": config})
                    next_game += 1
                for item in pool.batch_reset(resets):
                    if not item["ok"]:
                        raise RuntimeError(f"reset refuse: {item}")
                    active[str(item["match_id"])] = item["result"]
            steps = []
            for match_id, state in active.items():
                legal = state["legal_actions"]
                if not legal:
                    raise RuntimeError(f"aucune action legale pour {match_id}")
                steps.append({"match_id": match_id, "observer": 1,
                              "action": legal[int(rng.integers(len(legal)))]})
            finished: list[str] = []
            for item in pool.batch_step(steps):
                if not item["ok"]:
                    raise RuntimeError(f"action refusee: {item}")
                match_id = str(item["match_id"])
                state = item["result"]
                if state["observation"]["is_game_over"]:
                    finished.append(match_id)
                else:
                    active[match_id] = state
            if finished:
                pool.release_matches(finished)
                for match_id in finished:
                    del active[match_id]
                completed += len(finished)
    elapsed = time.perf_counter() - started
    print(f"{completed} parties en {elapsed:.2f} s: {completed / elapsed:.2f} parties/s "
          f"({args.workers} workers, batch {args.batch_size})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
