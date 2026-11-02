#!/usr/bin/env python3
from __future__ import annotations

import argparse
import time
from pathlib import Path

import numpy as np
import yaml

from samstone_rl.envs.samstone_env import SamStoneEnv
from samstone_rl.opponents import GodotProfileOpponent


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Mesure le debit du moteur Python en conditions Gym/PPO.")
    parser.add_argument("--games", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=424242)
    parser.add_argument("--precision", type=float, default=0.25)
    parser.add_argument("--anticipation", action="store_true")
    parser.add_argument("--config", type=Path,
                        help="configuration PPO dont les scenarios sont alternes")
    parser.add_argument("--god", help="limite le benchmark a un dieu de la configuration")
    args = parser.parse_args()
    if args.games <= 0 or not 0 <= args.precision <= 1:
        parser.error("games doit etre positif et precision comprise entre 0 et 1")

    rng = np.random.default_rng(args.seed)
    env = SamStoneEnv(
        backend="python",
        opponent=GodotProfileOpponent(args.precision, args.anticipation),
    )
    decisions = 0
    scenarios = []
    if args.config:
        config = yaml.safe_load(args.config.read_text(encoding="utf-8"))
        scenarios = list(config["environment"].get("scenarios", []))
        if args.god:
            scenarios = [item for item in scenarios if str(item["god"]) == args.god]
            if not scenarios:
                parser.error(f"dieu absent de la configuration: {args.god}")
    started = time.perf_counter()
    try:
        for game in range(args.games):
            options = None
            if scenarios:
                scenario = scenarios[game % len(scenarios)]
                options = {"config": {
                    "human_deck": list(scenario["deck"]),
                    "ai_deck": list(scenario["deck"]),
                    "human_god": str(scenario["god"]),
                    "ai_god": str(scenario["god"]),
                }}
            _observation, info = env.reset(seed=args.seed + game, options=options)
            terminated = False
            while not terminated:
                legal = np.flatnonzero(info["action_mask"])
                action = int(legal[int(rng.integers(len(legal)))])
                _observation, _reward, terminated, _truncated, info = env.step(action)
                decisions += 1
    finally:
        env.close()
    elapsed = time.perf_counter() - started
    print(f"{args.games} parties en {elapsed:.3f} s: {args.games / elapsed:.2f} parties/s; "
          f"{decisions / elapsed:.2f} decisions agent/s "
          f"(precision={args.precision:g}, anticipation={args.anticipation})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
