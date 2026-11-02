#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import yaml

from samstone_rl.bridge import GodotProcess, GodotProcessPool
from samstone_rl.decks import DeckCatalog, GodotDeckValidator
from samstone_rl.evaluation import (
    BatchedDeckEvaluator,
    EvaluationOpponent,
    MatchStore,
    common_schedule,
    run_card_ablation,
    write_ablation_report,
)
from samstone_rl.specialization import BOSS_GODS, BossRoster


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare chaque carte d'un deck final a des remplacements legaux.")
    parser.add_argument("god_id", choices=BOSS_GODS)
    parser.add_argument("checkpoint", type=Path,
                        help="politique universelle ou boss valide a evaluer")
    parser.add_argument("--roster", type=Path,
                        default=Path("runs/boss_specialists/boss_roster.json"))
    parser.add_argument("--config", type=Path,
                        default=Path(__file__).resolve().parents[1]
                        / "configs" / "card_ablation.yaml")
    parser.add_argument("--godot")
    args = parser.parse_args()
    config_path = args.config.resolve()
    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    roster = BossRoster.load(args.roster)
    output = Path(config["output_dir"])
    if not output.is_absolute():
        output = config_path.parent.parent / output
    output.mkdir(parents=True, exist_ok=True)
    bridge = GodotProcess(godot_path=args.godot)
    parallel = config["parallel"]
    pool = GodotProcessPool(int(parallel["workers"]), godot_path=args.godot)
    store = MatchStore(output / "matches.sqlite3")
    try:
        bridge.start()
        pool.start()
        catalog_snapshot = bridge.deck_catalog()
        catalog = DeckCatalog(catalog_snapshot)
        catalog_path = output / "catalog_snapshot.json"
        catalog_temp = catalog_path.with_suffix(".json.tmp")
        catalog_temp.write_text(json.dumps(catalog_snapshot, indent=2), encoding="utf-8")
        catalog_temp.replace(catalog_path)
        if catalog.checksum != roster.catalog_checksum:
            raise ValueError("catalogue Godot different du registre des boss")
        validator = GodotDeckValidator(bridge, catalog)
        baseline_data = roster.deck(args.god_id)
        baseline = catalog.candidate(args.god_id, baseline_data.stone_ids)
        opponents = tuple(EvaluationOpponent(
            f"boss_{item.god_id}", item.god_id, item.stone_ids) for item in roster.decks)
        validator.require_all_valid(
            catalog.candidate(item.god_id, item.stone_ids) for item in roster.decks)
        manifest = bridge.engine_manifest()
        engine_checksum = hashlib.sha256(json.dumps(
            manifest, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        evaluator = BatchedDeckEvaluator(
            pool, args.checkpoint, opponents, store, engine_checksum, catalog.checksum,
            int(parallel["batch_size"]), config.get("device", "cpu"),
            float(config["telemetry"]["action_sample_rate"]))
        settings = config["ablation"]
        schedule = common_schedule(
            tuple(item.opponent_id for item in opponents),
            int(settings["games_per_side_order"]), int(settings["seed_base"]))
        report = run_card_ablation(
            evaluator, catalog, baseline, schedule,
            int(settings["alternatives_per_card"]),
            float(settings["maximum_cost_delta"]),
            float(settings["minimum_effect"]))
        path = write_ablation_report(report, output / "reports")
        print(f"Ablation {args.god_id} terminee: {path}")
        return 0
    finally:
        store.close()
        pool.close()
        bridge.close()


if __name__ == "__main__":
    raise SystemExit(main())
