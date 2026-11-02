#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from samstone_rl.specialization.gate import validate_boss_roster


def main() -> int:
    parser = argparse.ArgumentParser(description="Valide les six checkpoints specialises.")
    parser.add_argument("root", type=Path, nargs="?", default=Path("runs/boss_specialists"))
    parser.add_argument("--roster", type=Path,
                        default=Path("runs/boss_specialists/boss_roster.json"))
    args = parser.parse_args()
    report = validate_boss_roster(args.root, args.roster)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
