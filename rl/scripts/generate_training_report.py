#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from samstone_rl.observability.training_report import generate_training_report


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Génère un rapport HTML/JSON/CSV depuis les métriques d'un run.")
    parser.add_argument("run", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    summary = generate_training_report(args.run, args.output)
    target = args.output.resolve() if args.output else args.run.resolve() / "reports" / "training"
    print(f"Rapport créé: {target} ({summary['events']} événements)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
