"""CSV and HTML presentation for precomputed balance statistics."""

from __future__ import annotations

import csv
import html
import json
from pathlib import Path
from typing import Any


def write_table_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    fields = [
        "key",
        "games",
        "wins",
        "draws",
        "losses",
        "win_rate",
        "confidence_low",
        "confidence_high",
        "mean_margin",
        "mean_captures",
        "mean_capture_delta",
        "signal",
    ]
    with temporary.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def write_actions_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    fields = [
        "stone_id",
        "plays",
        "matches",
        "wins_when_played",
        "draws_when_played",
        "win_rate_when_played",
        "confidence_low",
        "confidence_high",
        "captures",
        "captures_per_play",
        "effect_triggers",
        "positions",
        "signal",
    ]
    with temporary.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({**row, "positions": json.dumps(row["positions"], sort_keys=True)})
    temporary.replace(path)


def write_usage_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    fields = [
        "god_id",
        "stone_id",
        "evaluated_decks",
        "decks_with_card",
        "deck_selection_rate",
        "top_decks",
        "top_decks_with_card",
        "top_deck_selection_rate",
        "top_selection_lift",
        "games_in_deck",
        "win_rate_in_deck",
        "confidence_low",
        "confidence_high",
        "sampled_matches",
        "available_matches",
        "played_matches",
        "available_decisions",
        "plays",
        "selection_rate_when_available",
        "unused_available_matches",
        "signals",
    ]
    with temporary.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({**row, "signals": "|".join(row["signals"])})
    temporary.replace(path)


def render_html(payload: dict[str, Any]) -> str:
    sections = []
    for name, rows in payload["tables"].items():
        body = "".join(
            "<tr>"
            f"<td>{html.escape(str(row['key']))}</td>"
            f"<td>{row['games']}</td><td>{row['win_rate']:.1%}</td>"
            f"<td>{row['confidence_low']:.1%} – {row['confidence_high']:.1%}</td>"
            f"<td>{row['mean_margin']:+.3f}</td><td>{row['mean_capture_delta']:+.2f}</td>"
            f"<td>{html.escape(row['signal'])}</td>"
            "</tr>"
            for row in rows
        )
        sections.append(
            f"<section><h2>{html.escape(name.replace('_', ' ').title())}</h2>"
            "<table><thead><tr><th>Élément</th><th>Matchs</th><th>Victoires</th>"
            "<th>IC 95 %</th><th>Marge</th><th>Δ captures</th><th>Signal</th></tr></thead>"
            f"<tbody>{body}</tbody></table></section>"
        )
    action_body = "".join(
        "<tr>"
        f"<td>{html.escape(row['stone_id'])}</td><td>{row['plays']}</td>"
        f"<td>{row['win_rate_when_played']:.1%}</td><td>{row['captures_per_play']:.3f}</td>"
        f"<td>{row['effect_triggers']}</td><td>{html.escape(row['signal'])}</td></tr>"
        for row in payload["card_action_statistics"]
    )
    sections.append(
        "<section><h2>Actions par carte</h2><table><thead><tr><th>Carte</th>"
        "<th>Utilisations</th><th>Victoires du propriétaire</th><th>Captures/action</th>"
        "<th>Effets</th><th>Signal</th></tr></thead>"
        f"<tbody>{action_body}</tbody></table></section>"
    )
    usage_body = "".join(
        "<tr>"
        f"<td>{html.escape(row['god_id'])}</td><td>{html.escape(row['stone_id'])}</td>"
        f"<td>{row['deck_selection_rate']:.1%}</td>"
        f"<td>{row['top_deck_selection_rate']:.1%}</td>"
        f"<td>{row['selection_rate_when_available']:.1%}</td>"
        f"<td>{row['unused_available_matches']}</td>"
        f"<td>{html.escape(', '.join(row['signals']))}</td></tr>"
        for row in payload["card_usage_statistics"]
    )
    sections.append(
        "<section><h2>Cartes peu utilisées ou faibles</h2><table><thead><tr>"
        "<th>Dieu</th><th>Carte</th><th>Decks explorés</th><th>Top decks</th>"
        "<th>Choisie quand disponible</th><th>Matchs disponible mais inutilisée</th>"
        "<th>Signaux</th></tr></thead>"
        f"<tbody>{usage_body}</tbody></table></section>"
    )
    overall = payload["overall"]
    return f"""<!doctype html><html lang="fr"><meta charset="utf-8">
<title>Rapport d'équilibrage SamStone</title>
<style>body{{font:14px system-ui;margin:32px;max-width:1400px}}table{{border-collapse:collapse;
width:100%}}th,td{{padding:7px;border-bottom:1px solid #ddd;text-align:left}}th{{position:sticky;
top:0;background:#fff}}section{{margin:36px 0}}.summary{{padding:16px;background:#f3f5f7}}</style>
<h1>Rapport d'équilibrage SamStone</h1>
<div class="summary"><b>{payload["matches"]}</b> matchs — taux de victoire candidat
<b>{overall["win_rate"]:.1%}</b> — IC 95 % {overall["confidence_low"]:.1%} à
{overall["confidence_high"]:.1%}. Traces détaillées : <b>{payload["action_sampled_matches"]}</b> matchs.</div>
<p>Les associations de cartes ne prouvent pas une causalité. Elles doivent être confirmées à
matchup, politique, camp et ordre de départ comparables.</p>{"".join(sections)}</html>"""
