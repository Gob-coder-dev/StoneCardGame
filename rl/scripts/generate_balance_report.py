#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from samstone_rl.observability.balance_report import generate_balance_report


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Génère les statistiques d'équilibrage depuis matches.sqlite3.")
    parser.add_argument("database", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--minimum-samples", type=int, default=100)
    parser.add_argument(
        "--catalog", type=Path,
        help="catalog_snapshot.json; par defaut, celui place a cote de la base")
    args = parser.parse_args()
    if args.minimum_samples <= 0:
        parser.error("minimum-samples doit être strictement positif")
    catalog = args.catalog
    automatic = args.database.resolve().parent / "catalog_snapshot.json"
    if catalog is None and automatic.is_file():
        catalog = automatic
    report = generate_balance_report(
        args.database, args.output, args.minimum_samples, catalog)
    print(f"Rapport créé: {args.output.resolve()} ({report['matches']} matchs)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
