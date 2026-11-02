#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from samstone_rl.specialization.gate import BossSpecialistValidator
from samstone_rl.specialization.roster import BOSS_GODS


def main() -> int:
    parser = argparse.ArgumentParser(description="Valide un boss specialise dans Godot.")
    parser.add_argument("god_id", choices=BOSS_GODS)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--config", type=Path,
                        default=Path(__file__).resolve().parents[1]
                        / "configs" / "boss_specialization.yaml")
    parser.add_argument("--roster", type=Path,
                        default=Path("runs/boss_specialists/boss_roster.json"))
    parser.add_argument("--godot")
    args = parser.parse_args()
    validator = BossSpecialistValidator(
        args.config, args.roster, args.god_id, args.checkpoint, args.godot)
    report = validator.run()
    path = validator.write(report)
    print(json.dumps({"passed": report["passed"], "failures": report["failures"],
                      "report": str(path)}, indent=2, ensure_ascii=False))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
