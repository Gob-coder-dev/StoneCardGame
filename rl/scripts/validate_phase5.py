#!/usr/bin/env python3
"""Inspect the certificate produced by the automatic phase-5 final holdout."""

import argparse
import json
from pathlib import Path

import yaml

from samstone_rl.utils.certification import require_certified
from samstone_rl.utils.checkpoints import load_checkpoint, state_checksum
from samstone_rl.utils.provenance import provenance


def main():
    parser = argparse.ArgumentParser(description="Verifie la certification automatique de phase 5.")
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "configs/ppo_self_play_v2.yaml",
    )
    args = parser.parse_args()
    source = load_checkpoint(args.checkpoint)
    requested = yaml.safe_load(args.config.read_text(encoding="utf-8"))
    if source.get("config") != requested:
        raise ValueError("la configuration ne correspond pas au checkpoint")
    path = args.checkpoint.parent / "phase5_validated.pt"
    if not path.exists():
        state = source.get("phase5", {}).get("champion_curriculum", {})
        print(
            json.dumps(
                dict(
                    passed=False,
                    status=state.get("status", "legacy"),
                    promotions=state.get("promotions", 0),
                    message="reprendre ppo_self_play avec latest.pt pour poursuivre le cycle automatique",
                ),
                indent=2,
            )
        )
        return 1
    certified = load_checkpoint(path)
    require_certified(certified, "phase5", provenance())
    if state_checksum(certified["model"]) != state_checksum(source["model"]):
        raise ValueError("ce checkpoint differe du champion certifie")
    print(
        json.dumps(
            dict(passed=True, checkpoint=str(path), report=certified["certification"]["report"]),
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
