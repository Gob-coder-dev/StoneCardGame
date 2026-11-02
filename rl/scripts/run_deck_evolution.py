#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import torch
import yaml

from samstone_rl.bridge.godot_process import GodotProcess
from samstone_rl.bridge.process_pool import GodotProcessPool
from samstone_rl.decks import DeckCatalog, GodotDeckValidator
from samstone_rl.evaluation import (
    BatchedDeckEvaluator,
    EvaluationOpponent,
    MatchStore,
    common_schedule,
)
from samstone_rl.evaluation.phase_six_gate import PhaseSixGate, write_gate_result
from samstone_rl.evaluation.reporting import write_phase_six_report
from samstone_rl.observability import RunTracker, build_run_manifest
from samstone_rl.training.deck_evolution import (
    DeckEvolution,
    EvolutionConfig,
    EvolutionStateStore,
    RankedCandidate,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Recherche évolutionnaire de decks SamStone.")
    parser.add_argument("god_id")
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--config", type=Path,
                        default=Path(__file__).resolve().parents[1] / "configs" / "deck_evolution.yaml")
    parser.add_argument("--godot")
    parser.add_argument("--output", type=Path,
                        help="dossier de run; utiliser un dossier distinct pour chaque politique")
    parser.add_argument("--pilot", action="store_true",
                        help="autorise un essai technique avant validation complète de la phase 5")
    args = parser.parse_args()
    config_path = args.config.resolve()
    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    phase_five_completed = bool(checkpoint.get("phase5", {}).get("completed", False))
    if not args.pilot and not phase_five_completed:
        raise RuntimeError("la phase 6 exige un checkpoint ayant validé la phase 5; utiliser --pilot uniquement pour les tests")
    output = args.output or Path(config["output_dir"])
    if not output.is_absolute():
        output = config_path.parent.parent / output
    output.mkdir(parents=True, exist_ok=True)

    bridge = GodotProcess(godot_path=args.godot)
    store = MatchStore(output / "matches.sqlite3")
    parallel = config.get("parallel", {})
    pool = GodotProcessPool(int(parallel.get("workers", 1)), godot_path=args.godot)
    tracker: RunTracker | None = None
    try:
        bridge.start()
        pool.start()
        catalog_snapshot = bridge.deck_catalog()
        catalog = DeckCatalog(catalog_snapshot)
        catalog_path = output / "catalog_snapshot.json"
        catalog_temp = catalog_path.with_suffix(".json.tmp")
        catalog_temp.write_text(json.dumps(catalog_snapshot, indent=2), encoding="utf-8")
        catalog_temp.replace(catalog_path)
        if args.god_id not in catalog.gods:
            raise ValueError(f"dieu inconnu: {args.god_id}")
        validator = GodotDeckValidator(bridge, catalog)
        opponents = tuple(EvaluationOpponent(
            str(item["id"]), str(item["god"]), tuple(item["deck"]))
            for item in config["opponents"])
        validator.require_all_valid(
            catalog.candidate(item.god_id, item.deck) for item in opponents)
        manifest = bridge.engine_manifest()
        engine_checksum = hashlib.sha256(
            json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        evaluator = BatchedDeckEvaluator(
            pool, args.checkpoint, opponents, store, engine_checksum, catalog.checksum,
            int(parallel.get("batch_size", 64)), config.get("device", "cpu"),
            action_sample_rate=float(config.get("telemetry", {}).get(
                "action_sample_rate", 0.10)))
        tracker = RunTracker(
            output / "monitoring" / args.god_id, "deck_evolution",
            tensorboard=bool(config.get("monitoring", {}).get("tensorboard", True)))
        tracker.initialize_manifest(build_run_manifest(
            "deck_evolution", config, config_path, int(config["seed"]),
            checksums={
                "engine": engine_checksum,
                "catalog": catalog.checksum,
                "policy": evaluator.policy_checksum,
            },
            extra={
                "god_id": args.god_id,
                "checkpoint": str(args.checkpoint.resolve()),
                "pilot": bool(args.pilot),
                "engine_manifest": manifest,
            }))
        opponent_ids = tuple(item.opponent_id for item in opponents)
        evaluation = config["evaluation"]
        short_schedule = common_schedule(opponent_ids, int(evaluation["short_games_per_side_order"]),
                                         int(evaluation["short_seed_base"]))
        evolution_config = EvolutionConfig(**config["evolution"])

        def record_generation(generation: int, metrics: dict[str, float]) -> None:
            assert tracker is not None
            tracker.log("deck_evolution/generation", generation,
                        {**metrics, **evaluator.metrics_snapshot(reset=True)},
                        {"god_id": args.god_id})

        evolution = DeckEvolution(
            catalog, validator, lambda candidate: evaluator.evaluate(candidate, short_schedule),
            evaluator.policy_checksum, evolution_config,
            EvolutionStateStore(output / f"state_{args.god_id}.json"), int(config["seed"]),
            on_generation=record_generation)
        baseline_data = next((item for item in config["opponents"] if item["god"] == args.god_id), None)
        baselines = () if baseline_data is None else (
            catalog.candidate(args.god_id, baseline_data["deck"]),)
        ranking = evolution.run(args.god_id, baselines)

        medium_schedule = common_schedule(opponent_ids, int(evaluation["medium_games_per_side_order"]),
                                          int(evaluation["medium_seed_base"]))
        medium = _rerank(ranking[:int(evaluation["medium_finalists"])], evaluator, medium_schedule)
        tracker.log("deck_evolution/medium", evolution_config.generations + 1,
                    {**_ranking_metrics(medium), **evaluator.metrics_snapshot(reset=True)},
                    {"god_id": args.god_id})
        final_schedule = common_schedule(opponent_ids, int(evaluation["final_games_per_side_order"]),
                                         int(evaluation["final_seed_base"]))
        final = _rerank(medium[:int(evaluation["final_finalists"])], evaluator, final_schedule)
        tracker.log("deck_evolution/final", evolution_config.generations + 2,
                    {**_ranking_metrics(final), **evaluator.metrics_snapshot(reset=True)},
                    {"god_id": args.god_id})
        final_keys = {(item.opponent_id, item.seed, item.agent_player, item.first_player)
                      for item in final_schedule}
        records = tuple(record for item in final for record in store.records_for(
            evaluator.engine_checksum, evaluator.catalog_checksum,
            evaluator.policy_checksum, item.candidate.deck_hash)
            if (record.opponent_id, record.seed, record.agent_player,
                record.first_player) in final_keys)
        write_phase_six_report(output / "reports", args.god_id, final, records)
        gate_config = config["final_gate"]
        gate = PhaseSixGate(float(gate_config["minimum_win_rate"]),
                            float(gate_config["minimum_worst_matchup"]))
        gate_result = write_gate_result(
            output / "reports" / f"phase6_gate_{args.god_id}.json",
            args.god_id, final, gate, evaluator.engine_checksum,
            evaluator.catalog_checksum, evaluator.policy_checksum,
            official=phase_five_completed and not args.pilot)
        passed = bool(gate_result["passed"])
        if args.pilot:
            threshold_status = "atteints" if gate_result["thresholds_passed"] else "non atteints"
            print(f"Pilote phase 6 {args.god_id} termine; seuils {threshold_status}; "
                  f"rapport non officiel: {output / 'reports'}")
            return 0
        print(f"Phase 6 {args.god_id}: {'VALIDEE' if passed else 'NON VALIDEE'}; "
              f"rapport: {output / 'reports'}")
        return 0 if passed else 1
    finally:
        if tracker is not None:
            tracker.close()
        store.close()
        pool.close()
        bridge.close()


def _rerank(ranking, evaluator: BatchedDeckEvaluator, schedule) -> tuple[RankedCandidate, ...]:
    return tuple(sorted(
        (RankedCandidate(item.candidate, evaluator.evaluate(item.candidate, schedule)) for item in ranking),
        key=lambda item: item.evaluation.fitness, reverse=True))


def _ranking_metrics(ranking: tuple[RankedCandidate, ...]) -> dict[str, float]:
    if not ranking:
        raise ValueError("classement vide")
    fitness = [item.evaluation.fitness for item in ranking]
    best = ranking[0].evaluation
    return {
        "candidates": float(len(ranking)),
        "fitness_best": max(fitness),
        "fitness_mean": sum(fitness) / len(fitness),
        "fitness_worst": min(fitness),
        "best_win_rate": best.win_rate,
        "best_wilson_lower": best.wilson_lower,
        "best_worst_matchup_win_rate": best.worst_matchup_win_rate,
        "best_mean_margin": best.mean_margin,
    }


if __name__ == "__main__":
    raise SystemExit(main())
