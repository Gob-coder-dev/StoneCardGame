#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from samstone_rl.observability.training_report import latest_status


def main() -> int:
    parser = argparse.ArgumentParser(description="Affiche l'état et les alertes d'un run SamStone.")
    parser.add_argument("run", type=Path)
    parser.add_argument("--follow", action="store_true")
    parser.add_argument("--interval", type=float, default=5.0)
    args = parser.parse_args()
    if args.interval <= 0:
        parser.error("interval doit être strictement positif")
    try:
        while True:
            status = latest_status(args.run)
            print(json.dumps(status, indent=2, ensure_ascii=False))
            if not args.follow:
                return 0
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
