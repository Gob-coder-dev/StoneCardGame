#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from samstone_rl.training.phase_five_gate import PhaseFiveValidator


def main() -> int:
    parser = argparse.ArgumentParser(description="Valide la phase 5 sur des matchs Godot reserves.")
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--config", type=Path,
                        default=Path(__file__).resolve().parents[1]
                        / "configs" / "ppo_self_play_v2.yaml")
    parser.add_argument("--godot", help="chemin de l'executable Godot")
    args = parser.parse_args()
    validator = PhaseFiveValidator(args.config, args.checkpoint, args.godot)
    report = validator.run()
    result_path = validator.write_result(report)
    print(json.dumps({"passed": report["passed"], "failures": report["failures"],
                      "report": str(result_path)}, indent=2, ensure_ascii=False))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
