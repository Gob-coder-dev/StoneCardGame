#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

GODS = ("veskar", "nerava", "kharun", "ilyr", "sylkha", "enigma")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Valide les six artefacts finaux produits par la phase 6.")
    parser.add_argument("reports", type=Path, help="dossier contenant phase6_gate_<dieu>.json")
    args = parser.parse_args()
    reports = args.reports.resolve()
    failures: list[str] = []
    payloads: list[dict] = []
    for god_id in GODS:
        path = reports / f"phase6_gate_{god_id}.json"
        if not path.is_file():
            failures.append(f"{god_id}: artefact absent ({path})")
            continue
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            failures.append(f"{god_id}: artefact illisible ({exc})")
            continue
        if payload.get("version") != 1 or payload.get("god_id") != god_id:
            failures.append(f"{god_id}: identite ou version invalide")
        elif not payload.get("official", False):
            failures.append(f"{god_id}: artefact pilote non officiel")
        elif not payload.get("passed", False):
            failures.append(f"{god_id}: seuil final non atteint")
        elif not payload.get("finalists"):
            failures.append(f"{god_id}: aucun finaliste")
        payloads.append(payload)
    for key in ("engine_checksum", "catalog_checksum", "policy_checksum"):
        values = {str(payload.get(key, "")) for payload in payloads}
        if len(values) > 1:
            failures.append(f"les six artefacts n'utilisent pas le meme {key}")
        elif values == {""}:
            failures.append(f"{key} absent")
    if failures:
        print("Phase 6 NON VALIDEE")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print("Phase 6 VALIDEE: six dieux, meme moteur, meme catalogue et meme politique.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
