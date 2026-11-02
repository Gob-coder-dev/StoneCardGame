#!/usr/bin/env python3
"""Explain where a PPO run spends its wall-clock time."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from samstone_rl.observability.profiling import (
    PROFILE_PHASES,
    summarize_run_profile,
)

DECISIONS = {
    "vectorization_recommended":
        "La simulation domine: un moteur batch/vectorisé mérite un prototype.",
    "optimize_neural_compute_first":
        "Le réseau domine: optimiser les lots/minibatches avant de réécrire les règles.",
    "mixed_profile_measure_before_rewrite":
        "Le coût est partagé: faire un micro-benchmark ciblé avant une réécriture complète.",
}


def main() -> int:
    parser = argparse.ArgumentParser(description="Profile les phases d'un run PPO SamStone.")
    parser.add_argument("run", type=Path)
    parser.add_argument("--last-updates", type=int, default=500)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    summary = summarize_run_profile(args.run, args.last_updates)
    if args.json:
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        return 0
    print(f"Updates analysées: {summary['updates_analyzed']} "
          f"(steps {summary['first_step']} a {summary['last_step']})")
    print(f"Durée moyenne d'une update: {summary['mean_update_seconds']:.3f} s")
    print("Répartition du temps:")
    for phase in PROFILE_PHASES:
        values = summary["phases"][phase]
        print(f"  {phase:16} {values['fraction']:6.1%}  "
              f"({values['mean_seconds']:.4f} s/update)")
    print(f"Évaluations dans le temps mesuré: "
          f"{summary['evaluation_fraction_of_measured_time']:.1%}")
    print(f"Conclusion: {DECISIONS[summary['decision']]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
