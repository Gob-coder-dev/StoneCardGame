from __future__ import annotations

import csv
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from samstone_rl.decks import DeckCandidate, DeckCatalog

from .deck_evaluator import BatchedDeckEvaluator
from .schedule import MatchSpec
from .store import MatchRecord


@dataclass(frozen=True, slots=True)
class AblationVariant:
    removed: str
    replacement: str
    candidate: DeckCandidate
    cost_delta: float


def replacement_variants(catalog: DeckCatalog, baseline: DeckCandidate,
                         alternatives_per_card: int = 4,
                         maximum_cost_delta: float = 8.0) -> tuple[AblationVariant, ...]:
    catalog.require_valid(baseline)
    if alternatives_per_card <= 0 or maximum_cost_delta < 0:
        raise ValueError("parametres de remplacement invalides")
    variants: list[AblationVariant] = []
    for removed in baseline.stone_ids:
        current = catalog.variants[removed]
        remaining = [item for item in baseline.stone_ids if item != removed]
        remaining_lineages = {catalog.variants[item].lineage_id for item in remaining}
        candidates = []
        for replacement in catalog.variants.values():
            if replacement.stone_id == removed:
                continue
            if replacement.affinity not in {"neutral", baseline.god_id}:
                continue
            if replacement.lineage_id in remaining_lineages:
                continue
            delta = replacement.cost - current.cost
            if abs(delta) > maximum_cost_delta:
                continue
            try:
                candidate = catalog.candidate(
                    baseline.god_id, [*remaining, replacement.stone_id])
            except ValueError:
                continue
            candidates.append(AblationVariant(
                removed, replacement.stone_id, candidate, delta))
        candidates.sort(key=lambda item: (abs(item.cost_delta), item.replacement))
        variants.extend(candidates[:alternatives_per_card])
    unique = {item.candidate.deck_hash: item for item in variants}
    return tuple(sorted(unique.values(), key=lambda item: (item.removed, item.replacement)))


def _score(record: MatchRecord) -> float:
    return 1.0 if record.won else (0.5 if record.draw else 0.0)


def _two_sided_sign_p_value(better: int, worse: int) -> float:
    decisive = better + worse
    if decisive == 0:
        return 1.0
    tail = sum(math.comb(decisive, index) for index in range(min(better, worse) + 1))
    return min(1.0, 2.0 * tail / (2**decisive))


def paired_ablation(baseline: tuple[MatchRecord, ...],
                    candidate: tuple[MatchRecord, ...]) -> dict[str, Any]:
    def key(item: MatchRecord) -> tuple[Any, ...]:
        return (item.opponent_id, item.seed, item.agent_player, item.first_player)
    first = {key(item): item for item in baseline}
    second = {key(item): item for item in candidate}
    if first.keys() != second.keys():
        raise ValueError("les comparaisons n'utilisent pas les memes matchs")
    deltas = [_score(second[item]) - _score(first[item]) for item in sorted(first)]
    better = sum(value > 0 for value in deltas)
    worse = sum(value < 0 for value in deltas)
    return {"games": len(deltas), "replacement_better": better,
            "same": len(deltas) - better - worse, "replacement_worse": worse,
            "mean_score_delta": sum(deltas) / len(deltas) if deltas else 0.0,
            "two_sided_sign_p_value": _two_sided_sign_p_value(better, worse)}


def run_card_ablation(evaluator: BatchedDeckEvaluator, catalog: DeckCatalog,
                      baseline: DeckCandidate, schedule: tuple[MatchSpec, ...],
                      alternatives_per_card: int, maximum_cost_delta: float,
                      minimum_effect: float = 0.02) -> dict[str, Any]:
    variants = replacement_variants(
        catalog, baseline, alternatives_per_card, maximum_cost_delta)
    evaluator.evaluate(baseline, schedule)
    baseline_records = _records_for_schedule(evaluator, baseline, schedule)
    rows = []
    for item in variants:
        evaluation = evaluator.evaluate(item.candidate, schedule)
        comparison = paired_ablation(
            baseline_records, _records_for_schedule(evaluator, item.candidate, schedule))
        rows.append({"removed": item.removed, "replacement": item.replacement,
                     "deck_hash": item.candidate.deck_hash, "cost_delta": item.cost_delta,
                     "win_rate": evaluation.win_rate,
                     "worst_matchup_win_rate": evaluation.worst_matchup_win_rate,
                     **comparison})
    by_card: dict[str, list[dict[str, Any]]] = {}
    for card in baseline.stone_ids:
        candidates = sorted((row for row in rows if row["removed"] == card),
                            key=lambda row: (-row["mean_score_delta"],
                                             row["two_sided_sign_p_value"], row["replacement"]))
        by_card[card] = candidates
    conclusions = []
    for card, candidates in by_card.items():
        best = candidates[0] if candidates else None
        signal = "no_legal_comparison"
        if best is not None:
            if (best["mean_score_delta"] >= minimum_effect
                    and best["two_sided_sign_p_value"] <= 0.05):
                signal = "weak_relative_to_replacement"
            elif (best["mean_score_delta"] <= -minimum_effect
                  and best["two_sided_sign_p_value"] <= 0.05):
                signal = "strong_against_tested_replacements"
            else:
                signal = "inconclusive"
        conclusions.append({"stone_id": card, "signal": signal,
                            "best_replacement": best})
    return {"schema_version": 1, "god_id": baseline.god_id,
            "baseline": baseline.to_dict(), "games_per_deck": len(schedule),
            "alternatives_per_card": alternatives_per_card,
            "maximum_cost_delta": maximum_cost_delta,
            "minimum_effect": minimum_effect, "comparisons": rows,
            "cards": conclusions}


def _records_for_schedule(evaluator: BatchedDeckEvaluator, candidate: DeckCandidate,
                          schedule: tuple[MatchSpec, ...]) -> tuple[MatchRecord, ...]:
    expected = {(item.opponent_id, item.seed, item.agent_player, item.first_player)
                for item in schedule}
    return tuple(item for item in evaluator.store.records_for(
        evaluator.engine_checksum, evaluator.catalog_checksum,
        evaluator.policy_checksum, candidate.deck_hash)
        if (item.opponent_id, item.seed, item.agent_player, item.first_player) in expected)


def write_ablation_report(report: dict[str, Any], output_directory: str | Path) -> Path:
    output = Path(output_directory).resolve()
    output.mkdir(parents=True, exist_ok=True)
    target = output / f"card_ablation_{report['god_id']}.json"
    temporary = target.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(report, indent=2), encoding="utf-8")
    temporary.replace(target)
    csv_target = output / f"card_ablation_{report['god_id']}.csv"
    csv_temp = csv_target.with_suffix(".csv.tmp")
    fields = ["stone_id", "signal", "replacement", "mean_score_delta",
              "two_sided_sign_p_value", "replacement_better", "replacement_worse", "games"]
    with csv_temp.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for item in report["cards"]:
            best = item["best_replacement"] or {}
            writer.writerow({"stone_id": item["stone_id"], "signal": item["signal"],
                             "replacement": best.get("replacement", ""),
                             **{key: best.get(key, "") for key in fields[3:]}})
    csv_temp.replace(csv_target)
    return target
