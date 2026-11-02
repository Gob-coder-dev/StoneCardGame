#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from samstone_rl.envs.samstone_env import SamStoneEnv
from samstone_rl.opponents import GodotProfileOpponent


def main() -> int:
    parser = argparse.ArgumentParser(description="Termine des parties RL headless aleatoires.")
    parser.add_argument("--games", type=int, default=10)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN"))
    parser.add_argument("--profile", type=float, default=0.0, help="precision du bot Godot adverse")
    parser.add_argument("--anticipation", action="store_true")
    args = parser.parse_args()
    wins = draws = losses = 0
    env = SamStoneEnv(godot_path=args.godot, opponent=GodotProfileOpponent(args.profile, args.anticipation))
    try:
        for episode in range(args.games):
            _observation, info = env.reset(seed=1000 + episode)
            done = False
            while not done:
                action = int(env.np_random.choice(np.flatnonzero(info["action_mask"])))
                _observation, _reward, terminated, truncated, info = env.step(action)
                done = terminated or truncated
            if info["winner"] == env.agent_player:
                wins += 1
            elif info["winner"] == 0:
                draws += 1
            else:
                losses += 1
        print(f"{args.games} parties terminees: {wins} V / {draws} N / {losses} D")
        return 0
    finally:
        env.close()


if __name__ == "__main__":
    raise SystemExit(main())
