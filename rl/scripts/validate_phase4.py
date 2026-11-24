#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from samstone_rl.training.phase_four_reassessment import reassess_phase_four
from samstone_rl.training.ppo_cleanrl import PPOTrainer


def main() -> int:
    parser = argparse.ArgumentParser(description="Execute la garde finale phase 4 -> phase 5.")
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument(
        "--allow-python-source-change",
        action="store_true",
        help="autorise la reprise apres correction du code Python, sans changer les regles",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "configs" / "ppo_phase4_vectorized.yaml",
    )
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument(
        "--reevaluate",
        action="store_true",
        help="importe les poids pour une nouvelle certification complete",
    )
    modes.add_argument(
        "--reuse-recorded",
        action="store_true",
        help="recalcule les seuils sur le tournoi fige complet sans rejouer les matchs",
    )
    parser.add_argument(
        "--check-only", action="store_true", help="controle sans ecrire de certificat"
    )
    args = parser.parse_args()
    if args.check_only and not args.reuse_recorded:
        parser.error("--check-only exige --reuse-recorded")
    if args.reuse_recorded:
        report = reassess_phase_four(
            args.config,
            args.checkpoint,
            allow_python_source_change=args.allow_python_source_change,
            commit=not args.check_only,
        )
        print(
            json.dumps(
                dict(
                    passed=report["passed"],
                    check_only=args.check_only,
                    recorded_games=report.get("reassessment", {}).get(
                        "recorded_games", sum(item["games"] for item in report.get("slices", []))
                    ),
                    failed_slices=report["failed_slices"],
                    failed_god_stages=report["failed_god_stages"],
                ),
                indent=2,
            )
        )
        return 0 if report["passed"] else 1
    trainer = PPOTrainer(args.config, mode="evaluate")
    try:
        checkpoint = trainer.load_checkpoint(
            args.checkpoint,
            load_optimizer=False,
            load_training_state=not args.reevaluate,
            allow_python_source_change=args.allow_python_source_change,
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
