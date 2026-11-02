#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from samstone_rl.specialization import build_boss_roster


def main() -> int:
    parser = argparse.ArgumentParser(description="Fige les six meilleurs decks valides de phase 6.")
    parser.add_argument("reports", type=Path, help="dossier des phase6_gate_<dieu>.json")
    parser.add_argument("phase5_checkpoint", type=Path)
    parser.add_argument("--output", type=Path,
                        default=Path("runs/boss_specialists/boss_roster.json"))
    args = parser.parse_args()
    roster = build_boss_roster(args.reports, args.phase5_checkpoint, args.output)
    print(f"Registre cree: {args.output.resolve()} ({len(roster.decks)} boss)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
