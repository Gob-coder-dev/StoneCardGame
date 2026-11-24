"""Training-only league diagnostics; promotion uses held-out tournaments."""

from collections import Counter, defaultdict


def log_self_play(trainer, global_step, update, episodes):
    categories: Counter[str] = Counter()
    matchups: Counter[str] = Counter()
    by_god: dict[str, list[tuple[bool, bool, float]]] = defaultdict(list)
    by_matchup: dict[str, list[tuple[bool, bool, float]]] = defaultdict(list)
    by_category: dict[str, list[tuple[bool, bool, float]]] = defaultdict(list)
    for episode in episodes:
        opponent_id = str(episode.get("opponent_id", ""))
        if not opponent_id:
            raise RuntimeError("episode de ligue sans adversaire identifie")
        score = 1.0 if episode["won"] else (0.5 if episode["draw"] else 0.0)
        trainer.league.record_result(
            "live",
            opponent_id,
            score,
            global_step,
            {
                "god": episode["god"],
                "opponent_god": episode["opponent_god"],
                "agent_player": episode["agent_player"],
                "first_player": episode["first_player"],
            },
            persist=False,
        )
        categories[str(episode["opponent_category"])] += 1
        matchups[f"{episode['god']}_vs_{episode['opponent_god']}"] += 1
        outcome = (bool(episode["won"]), bool(episode["draw"]), float(episode["margin"]))
        by_god[str(episode["god"])].append(outcome)
        by_matchup[f"{episode['god']}_vs_{episode['opponent_god']}"].append(outcome)
        by_category[str(episode["opponent_category"])].append(outcome)
    trainer.league.flush_results()
    league_metrics = trainer.league.metrics_snapshot(True)
    trainer.tracker.log(
        "self_play",
        global_step,
        {
            "episodes": len(episodes),
            "by_category": dict(categories),
            "by_matchup": dict(matchups),
            "outcomes_by_god": {
                name: trainer._outcome_stats(values) for name, values in by_god.items()
            },
            "outcomes_by_matchup": {
                name: trainer._outcome_stats(values) for name, values in by_matchup.items()
            },
            "outcomes_by_category": {
                name: trainer._outcome_stats(values) for name, values in by_category.items()
            },
            "league_entries": league_metrics["entries"],
            "league_samples": league_metrics["samples"],
            "league_weights": league_metrics["weights"],
            "live_rating": trainer.league.ratings.get("live", 1500.0),
        },
        {"update": update},
    )
