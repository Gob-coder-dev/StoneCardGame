#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from samstone_rl.training.ppo_cleanrl import PPOTrainer


def main() -> int:
    parser = argparse.ArgumentParser(description="Execute la garde finale phase 4 -> phase 5.")
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "configs" / "ppo_phase4_vectorized.yaml",
    )
    parser.add_argument(
        "--reevaluate",
        action="store_true",
        help="importe les poids pour une nouvelle certification complete",
    )
    args = parser.parse_args()
    trainer = PPOTrainer(args.config, mode="evaluate")
    try:
        checkpoint = trainer.load_checkpoint(
            args.checkpoint, load_optimizer=False, load_training_state=not args.reevaluate
        )
        if args.reevaluate:
            trainer.curriculum.stage_index = len(trainer.curriculum.stages) - 1
            trainer.curriculum.awaiting_final_validation = True
        report = trainer.run_final_gate()
        if report.passed:
            trainer._save(
                "phase4_validated.pt",
                0 if args.reevaluate else int(checkpoint.get("global_step", 0)),
                report.to_dict(),
                0 if args.reevaluate else int(checkpoint.get("update", 0)),
            )
        print(json.dumps(report.to_dict(), indent=2))
        return 0 if report.passed else 1
    finally:
        trainer.close()


if __name__ == "__main__":
    raise SystemExit(main())
