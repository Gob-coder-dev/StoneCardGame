#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from samstone_rl.training.ppo_cleanrl import PPOTrainer


def main() -> int:
    parser = argparse.ArgumentParser(description="Execute la garde finale phase 4 -> phase 5.")
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--config", type=Path,
                        default=Path(__file__).resolve().parents[1]
                        / "configs" / "ppo_phase4_tactical.yaml")
    args = parser.parse_args()
    trainer = PPOTrainer(args.config)
    try:
        checkpoint = trainer.load_checkpoint(args.checkpoint, load_optimizer=False)
        report = trainer.run_final_gate()
        if report.passed:
            trainer._save("phase4_validated.pt", int(checkpoint.get("global_step", 0)),
                          report.to_dict(), int(checkpoint.get("update", 0)))
        print(json.dumps(report.to_dict(), indent=2))
        return 0 if report.passed else 1
    finally:
        trainer.tracker.close()
        trainer.env.close()


if __name__ == "__main__":
    raise SystemExit(main())
