from __future__ import annotations

import json
import math
from collections import Counter, defaultdict
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from samstone_rl.decks import DeckCatalog
from samstone_rl.evaluation import MatchAction, MatchRecord, MatchStore

from .balance_render import render_html, write_actions_csv, write_table_csv, write_usage_csv


@dataclass(frozen=True, slots=True)
class BalanceRow:
    key: str
    games: int
    wins: int
    draws: int
    losses: int
    win_rate: float
    confidence_low: float
    confidence_high: float
    mean_margin: float
    mean_captures: float
    mean_capture_delta: float

    def to_dict(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "games": self.games,
            "wins": self.wins,
            "draws": self.draws,
            "losses": self.losses,
            "win_rate": self.win_rate,
            "confidence_low": self.confidence_low,
            "confidence_high": self.confidence_high,
            "mean_margin": self.mean_margin,
            "mean_captures": self.mean_captures,
            "mean_capture_delta": self.mean_capture_delta,
        }


def generate_balance_report(
    database: str | Path,
    output_directory: str | Path,
    minimum_samples: int = 100,
    catalog_snapshot: str | Path | None = None,
) -> dict[str, Any]:
    output = Path(output_directory).resolve()
    output.mkdir(parents=True, exist_ok=True)
    with MatchStore(database) as store:
        records = store.all_records()
        if not records:
            raise ValueError("la base ne contient aucun match")
        grouped_actions: dict[tuple[Any, ...], list[MatchAction]] = defaultdict(list)
        for action in store.all_actions():
            grouped_actions[action_key(action)].append(action)
        actions = {
            record_key(record): tuple(grouped_actions.get(record_key(record), ()))
            for record in records
        }
    catalog_cards: dict[str, set[str]] = {}
    if catalog_snapshot is not None:
        snapshot = json.loads(Path(catalog_snapshot).read_text(encoding="utf-8"))
        catalog = DeckCatalog(snapshot)
        record_checksums = {item.catalog_checksum for item in records}
        if record_checksums != {catalog.checksum}:
            raise ValueError("le catalogue fourni differe des matchs")
        catalog_cards = {
            god_id: {
                item.stone_id
                for item in catalog.variants.values()
                if item.affinity in {"neutral", god_id}
            }
            for god_id in catalog.gods
        }
    tables = {
        "candidate_god": group_records(records, lambda item: item.candidate_god),
        "opponent_god": group_records(records, lambda item: item.opponent_god),
        "god_matchup": group_records(
            records, lambda item: f"{item.candidate_god} vs {item.opponent_god}"
        ),
        "agent_side": group_records(records, lambda item: f"player_{item.agent_player}"),
        "start_order": group_records(
            records,
            lambda item: (
                "candidate_first" if item.agent_player == item.first_player else "opponent_first"
            ),
        ),
        "blocked_cells": group_records(records, lambda item: str(len(item.blocked))),
        "blocked_layout": group_records(
            records,
            lambda item: ";".join(f"{row},{col}" for row, col in sorted(item.blocked)) or "none",
        ),
        "candidate_deck": group_records(records, lambda item: item.candidate_hash),
        "opponent": group_records(records, lambda item: item.opponent_id),
        "policy": group_records(records, lambda item: item.policy_checksum[:12]),
        "card_in_deck": _group_memberships(records, lambda item: item.candidate_deck),
        "card_in_deck_context": _group_card_context(records),
        "card_played": _group_played_cards(records, actions),
        "board_position": _group_positions(records, actions),
        "triggered_effect": _group_effects(records, actions),
    }
    overall = _row("all", records)
    action_statistics = _action_statistics(records, actions, minimum_samples)
    usage_statistics = _card_usage_statistics(records, actions, minimum_samples, catalog_cards)
    table_payload = {
        name: [_with_signal(row, overall, minimum_samples) for row in rows]
        for name, rows in tables.items()
    }
    god_ranking = sorted(
        table_payload["candidate_god"],
        key=lambda item: (-item["confidence_low"], -item["win_rate"], item["key"]),
    )
    findings = {
        "god_strength_ranking": god_ranking,
        "never_selected_cards": [
            item
            for item in usage_statistics
            if "never_selected_in_explored_decks" in item["signals"]
        ],
        "underused_cards": [
            item for item in usage_statistics if "underused_when_available" in item["signals"]
        ],
        "negative_association_cards": [
            item for item in usage_statistics if "negative_result_association" in item["signals"]
        ],
    }
    payload = {
        "schema_version": 2,
        "matches": len(records),
        "action_sampled_matches": sum(item.actions_sampled for item in records),
        "minimum_samples": int(minimum_samples),
        "engine_checksums": sorted({item.engine_checksum for item in records}),
        "catalog_checksums": sorted({item.catalog_checksum for item in records}),
        "policy_checksums": sorted({item.policy_checksum for item in records}),
        "overall": overall.to_dict(),
        "tables": table_payload,
        "card_action_statistics": action_statistics,
        "card_usage_statistics": usage_statistics,
        "findings": findings,
        "warnings": [
            "Les statistiques de cartes indiquent une association, pas une causalité.",
            "Une conclusion d'équilibrage exige assez d'échantillons et des matchups contrôlés.",
            "Les cartes jouées, positions et effets utilisent uniquement les matchs marqués actions_sampled.",
        ],
    }
    _atomic_json(output / "balance_report.json", payload)
    for name, rows in payload["tables"].items():
        write_table_csv(output / f"balance_{name}.csv", rows)
    write_actions_csv(output / "balance_card_actions.csv", action_statistics)
    write_usage_csv(output / "balance_card_usage.csv", usage_statistics)
    _atomic_text(output / "balance_report.html", render_html(payload))
    return payload


def group_records(
    records: Iterable[MatchRecord], key: Callable[[MatchRecord], str]
) -> list[BalanceRow]:
    groups: dict[str, list[MatchRecord]] = defaultdict(list)
    for record in records:
        groups[str(key(record))].append(record)
    return sorted(
        (_row(name, items) for name, items in groups.items()),
        key=lambda item: (-item.games, item.key),
    )


def record_key(record: MatchRecord) -> tuple[Any, ...]:
    return (
        record.engine_checksum,
        record.catalog_checksum,
        record.policy_checksum,
        record.candidate_hash,
        record.opponent_id,
        record.seed,
        record.agent_player,
        record.first_player,
    )


def action_key(action: MatchAction) -> tuple[Any, ...]:
    return (
        action.engine_checksum,
        action.catalog_checksum,
        action.policy_checksum,
        action.candidate_hash,
        action.opponent_id,
        action.seed,
        action.agent_player,
        action.first_player,
    )


def _group_memberships(
    records: tuple[MatchRecord, ...], members: Callable[[MatchRecord], Iterable[str]]
) -> list[BalanceRow]:
    groups: dict[str, list[MatchRecord]] = defaultdict(list)
    for record in records:
        for member in set(members(record)):
            groups[str(member)].append(record)
    return sorted(
        (_row(name, items) for name, items in groups.items()),
        key=lambda item: (-item.games, item.key),
    )


def _group_played_cards(
    records: tuple[MatchRecord, ...], actions: dict[tuple[Any, ...], tuple[MatchAction, ...]]
) -> list[BalanceRow]:
    groups: dict[str, list[MatchRecord]] = defaultdict(list)
    for record in records:
        cards = {
            action.stone_id
            for action in actions[record_key(record)]
            if action.player == record.agent_player
        }
        for card in cards:
            groups[card].append(record)
    return sorted(
        (_row(name, items) for name, items in groups.items()),
        key=lambda item: (-item.games, item.key),
    )


def _group_card_context(records: tuple[MatchRecord, ...]) -> list[BalanceRow]:
    groups: dict[str, list[MatchRecord]] = defaultdict(list)
    for record in records:
        order = "first" if record.agent_player == record.first_player else "second"
        for card in set(record.candidate_deck):
            key = (
                f"{card} | {record.candidate_god} vs {record.opponent_god} | "
                f"player_{record.agent_player} | {order}"
            )
            groups[key].append(record)
    return sorted(
        (_row(name, items) for name, items in groups.items()),
        key=lambda item: (-item.games, item.key),
    )


def _group_positions(
    records: tuple[MatchRecord, ...], actions: dict[tuple[Any, ...], tuple[MatchAction, ...]]
) -> list[BalanceRow]:
    groups: dict[str, list[MatchRecord]] = defaultdict(list)
    for record in records:
        positions = {
            f"{action.row},{action.col}"
            for action in actions[record_key(record)]
            if action.player == record.agent_player
        }
        for position in positions:
            groups[position].append(record)
    return sorted(
        (_row(name, items) for name, items in groups.items()),
        key=lambda item: (-item.games, item.key),
    )


def _group_effects(
    records: tuple[MatchRecord, ...], actions: dict[tuple[Any, ...], tuple[MatchAction, ...]]
) -> list[BalanceRow]:
    groups: dict[str, list[MatchRecord]] = defaultdict(list)
    for record in records:
        effects: set[str] = set()
        for action in actions[record_key(record)]:
            if action.player != record.agent_player:
                continue
            effects.update(
                _effect_name(value) for value in (*action.effects, *action.placement_effects)
            )
        effects.discard("")
        for effect in effects:
            groups[effect].append(record)
    return sorted(
        (_row(name, items) for name, items in groups.items()),
        key=lambda item: (-item.games, item.key),
    )


def _effect_name(value: Any) -> str:
    if isinstance(value, dict):
        for key in ("effect", "type", "name", "id"):
            if key in value:
                return str(value[key])
        return json.dumps(value, sort_keys=True, ensure_ascii=False)
    return str(value)


def _action_statistics(
    records: tuple[MatchRecord, ...],
    actions: dict[tuple[Any, ...], tuple[MatchAction, ...]],
    minimum_samples: int,
) -> list[dict[str, Any]]:
    stats: dict[str, dict[str, Any]] = defaultdict(
        lambda: {
            "plays": 0,
            "captures": 0,
            "effect_triggers": 0,
            "wins": 0,
            "draws": 0,
            "matches": set(),
            "positions": Counter(),
        }
    )
    for record in records:
        key = record_key(record)
        for action in actions[key]:
            item = stats[action.stone_id]
            item["plays"] += 1
            item["captures"] += action.captures
            item["effect_triggers"] += len(action.effects) + len(action.placement_effects)
            item["wins"] += int(record.winner == action.player)
            item["draws"] += int(record.winner == 0)
            item["matches"].add(key)
            item["positions"][f"{action.row},{action.col}"] += 1
    rows = []
    for stone_id, item in stats.items():
        plays = int(item["plays"])
        wins = int(item["wins"])
        low, high = wilson_interval(wins, plays)
        rows.append(
            {
                "stone_id": stone_id,
                "plays": plays,
                "matches": len(item["matches"]),
                "wins_when_played": wins,
                "draws_when_played": int(item["draws"]),
                "win_rate_when_played": wins / plays,
                "confidence_low": low,
                "confidence_high": high,
                "captures": int(item["captures"]),
                "captures_per_play": int(item["captures"]) / plays,
                "effect_triggers": int(item["effect_triggers"]),
                "positions": dict(item["positions"].most_common()),
                "signal": "insufficient_data" if plays < minimum_samples else "descriptive_only",
            }
        )
    return sorted(rows, key=lambda item: (-item["plays"], item["stone_id"]))


def _card_usage_statistics(
    records: tuple[MatchRecord, ...],
    actions: dict[tuple[Any, ...], tuple[MatchAction, ...]],
    minimum_samples: int,
    catalog_cards: dict[str, set[str]] | None = None,
) -> list[dict[str, Any]]:
    """Separate deck selection, hand availability and actual card selection."""
    decks_by_god: dict[str, dict[str, tuple[str, ...]]] = defaultdict(dict)
    deck_records: dict[str, list[MatchRecord]] = defaultdict(list)
    for record in records:
        decks_by_god[record.candidate_god][record.candidate_hash] = record.candidate_deck
        deck_records[record.candidate_hash].append(record)
    top_by_god: dict[str, set[str]] = {}
    for god_id, decks in decks_by_god.items():
        ranked = sorted(
            decks,
            key=lambda deck_hash: (
                -sum(item.won for item in deck_records[deck_hash]) / len(deck_records[deck_hash]),
                deck_hash,
            ),
        )
        top_by_god[god_id] = set(ranked[: max(1, math.ceil(len(ranked) * 0.20))])
    rows: list[dict[str, Any]] = []
    for god_id, decks in sorted(decks_by_god.items()):
        cards = sorted(
            {card for deck in decks.values() for card in deck}
            | (catalog_cards or {}).get(god_id, set())
        )
        top = top_by_god[god_id]
        god_records = [item for item in records if item.candidate_god == god_id]
        god_overall = _row(god_id, god_records)
        for card in cards:
            selected_decks = {deck_hash for deck_hash, deck in decks.items() if card in deck}
            top_selected = selected_decks & top
            card_records = [
                item for deck_hash in selected_decks for item in deck_records[deck_hash]
            ]
            sampled_records = [item for item in card_records if item.actions_sampled]
            available_decisions = selected_plays = 0
            available_matches: set[tuple[Any, ...]] = set()
            played_matches: set[tuple[Any, ...]] = set()
            for record in sampled_records:
                key = record_key(record)
                for action in actions[key]:
                    if action.player != record.agent_player:
                        continue
                    if card in action.hand:
                        available_decisions += 1
                        available_matches.add(key)
                    if action.stone_id == card:
                        selected_plays += 1
                        played_matches.add(key)
            wins = sum(item.won for item in card_records)
            games = len(card_records)
            win_rate = wins / games if games else 0.0
            low, high = wilson_interval(wins, games)
            deck_rate = len(selected_decks) / len(decks)
            top_rate = len(top_selected) / len(top)
            selection_rate = selected_plays / available_decisions if available_decisions else 0.0
            signals: list[str] = []
            if games >= minimum_samples and high < god_overall.win_rate:
                signals.append("negative_result_association")
            if len(decks) >= 5 and not selected_decks:
                signals.append("never_selected_in_explored_decks")
            if len(decks) >= 5 and top_rate + 0.10 < deck_rate:
                signals.append("avoided_by_top_decks")
            if available_decisions >= minimum_samples and selection_rate < 0.15:
                signals.append("underused_when_available")
            if not signals:
                signals.append("insufficient_or_inconclusive")
            rows.append(
                {
                    "god_id": god_id,
                    "stone_id": card,
                    "evaluated_decks": len(decks),
                    "decks_with_card": len(selected_decks),
                    "deck_selection_rate": deck_rate,
                    "top_decks": len(top),
                    "top_decks_with_card": len(top_selected),
                    "top_deck_selection_rate": top_rate,
                    "top_selection_lift": top_rate - deck_rate,
                    "games_in_deck": games,
                    "win_rate_in_deck": win_rate,
                    "confidence_low": low,
                    "confidence_high": high,
                    "sampled_matches": len(sampled_records),
                    "available_matches": len(available_matches),
                    "played_matches": len(played_matches),
                    "available_decisions": available_decisions,
                    "plays": selected_plays,
                    "selection_rate_when_available": selection_rate,
                    "unused_available_matches": len(available_matches - played_matches),
                    "signals": signals,
                }
            )
    return sorted(
        rows,
        key=lambda item: (
            "insufficient_or_inconclusive" in item["signals"],
            item["selection_rate_when_available"],
            item["god_id"],
            item["stone_id"],
        ),
    )


def _row(key: str, records: Iterable[MatchRecord]) -> BalanceRow:
    items = tuple(records)
    games = len(items)
    wins = sum(item.won for item in items)
    draws = sum(item.draw for item in items)
    low, high = wilson_interval(wins, games)
    return BalanceRow(
        key,
        games,
        wins,
        draws,
        games - wins - draws,
        wins / games,
        low,
        high,
        float(np.mean([(item.score_candidate - item.score_opponent) / 16.0 for item in items])),
        float(np.mean([item.candidate_captures for item in items])),
        float(np.mean([item.candidate_captures - item.opponent_captures for item in items])),
    )


def wilson_interval(
    successes: int, total: int, z: float = 1.959963984540054
) -> tuple[float, float]:
    if total <= 0:
        return 0.0, 1.0
    proportion = successes / total
    denominator = 1.0 + z * z / total
    centre = proportion + z * z / (2.0 * total)
    spread = z * math.sqrt((proportion * (1.0 - proportion) + z * z / (4.0 * total)) / total)
    return max(0.0, (centre - spread) / denominator), min(1.0, (centre + spread) / denominator)


def _with_signal(row: BalanceRow, overall: BalanceRow, minimum_samples: int) -> dict[str, Any]:
    signal = "insufficient_data"
    if row.games >= minimum_samples:
        if row.confidence_low > overall.win_rate:
            signal = "positive_association"
        elif row.confidence_high < overall.win_rate:
            signal = "negative_association"
        else:
            signal = "inconclusive"
    return {**row.to_dict(), "signal": signal}


def _atomic_json(path: Path, payload: dict[str, Any]) -> None:
    _atomic_text(path, json.dumps(payload, indent=2, ensure_ascii=False))


def _atomic_text(path: Path, content: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)
