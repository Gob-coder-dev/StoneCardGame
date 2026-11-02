#!/usr/bin/env python3
"""Print cumulative, refresh-safe counters for one local training run."""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

from samstone_rl.observability.training_report import load_json_lines


def collect_stats(run_directory: str | Path) -> dict[str, Any]:
    run = Path(run_directory).resolve()
    events = load_json_lines(run / "metrics.jsonl")
    evaluation_games = 0
    primary_games = 0
    anchor_games = 0
    mixed_games = 0
    training_episodes = 0.0
    evaluations = 0
    games_by_god: dict[str, int] = defaultdict(int)
    latest_training: dict[str, Any] | None = None
    latest_evaluation: dict[str, Any] | None = None

    for event in events:
        stream = str(event.get("stream", ""))
        metrics = event.get("metrics", {})
        if not isinstance(metrics, dict):
            continue
        if stream == "training":
            latest_training = event
            training_episodes += float(metrics.get("episodes_completed", 0.0))
        elif stream == "evaluation":
            latest_evaluation = event
            evaluations += 1
            primary = int(metrics.get("games", 0))
            anchors = metrics.get("anchors", {})
            anchoring = (sum(int(item.get("games", 0)) for item in anchors.values()
                             if isinstance(item, dict)) if isinstance(anchors, dict) else 0)
            mixed = metrics.get("mixed_vs_phase4", {})
            mixed_count = int(mixed.get("games", 0)) if isinstance(mixed, dict) else 0
            primary_games += primary
            anchor_games += anchoring
            mixed_games += mixed_count
            evaluation_games += primary + anchoring + mixed_count
            by_god = metrics.get("by_god", {})
            if isinstance(by_god, dict):
                for god, result in by_god.items():
                    if isinstance(result, dict):
                        games_by_god[str(god)] += int(result.get("games", 0))
            if isinstance(mixed, dict):
                mixed_by_god = mixed.get("by_god", {})
                if isinstance(mixed_by_god, dict):
                    for god, result in mixed_by_god.items():
                        if isinstance(result, dict):
                            games_by_god[str(god)] += int(result.get("games", 0))

    return {
        "run": str(run),
        "events_read": len(events),
        "training": {
            "episodes_completed_estimate": round(training_episodes),
            "latest_step": int(latest_training.get("step", 0)) if latest_training else 0,
            "latest_timestamp": latest_training.get("timestamp", "") if latest_training else "",
        },
        "evaluation": {
            "evaluations": evaluations,
            "games": evaluation_games,
            "primary_games": primary_games,
            "anchor_games": anchor_games,
            "mixed_games": mixed_games,
            "latest_step": int(latest_evaluation.get("step", 0)) if latest_evaluation else 0,
            "latest_timestamp": latest_evaluation.get("timestamp", "") if latest_evaluation else "",
            "games_by_god": dict(sorted(games_by_god.items())),
        },
        "total_observed_games_estimate": round(training_episodes) + evaluation_games,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Affiche les compteurs cumules d'un run PPO.")
    parser.add_argument("run", type=Path, nargs="?",
                        default=Path("runs/ppo_phase4_tactical"))
    parser.add_argument("--json", action="store_true",
                        help="affiche les donnees brutes JSON au lieu du resume lisible")
    args = parser.parse_args()
    stats = collect_stats(args.run)
    if args.json:
        print(json.dumps(stats, indent=2, ensure_ascii=False))
        return 0
    training = stats["training"]
    evaluation = stats["evaluation"]
    print(f"Parties d evaluation: {evaluation['games']}")
    if evaluation["anchor_games"] or evaluation["mixed_games"]:
        print(f"  dont bots du palier courant: {evaluation['primary_games']}")
        print(f"  dont anciens paliers: {evaluation['anchor_games']}")
        print(f"  dont tournoi mixte phase 5: {evaluation['mixed_games']}")
    print(f"Parties d entrainement: {training['episodes_completed_estimate']}")
    print(f"Total observe: {stats['total_observed_games_estimate']}")
    print(f"Dernier step entrainement: {training['latest_step']}")
    print(f"Dernier step evaluation: {evaluation['latest_step']}")
    print("Parties evaluation par dieu:")
    for god, games in evaluation["games_by_god"].items():
        print(f"  {god} {games}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
