"""Balanced paired duels and draw-aware statistics for champion promotion."""

from collections import defaultdict

import numpy as np


def duel_cases(gods: int, repetitions: int, seed: int) -> list[dict]:
    """Swap model roles on the same physical setup, including mirror matches."""
    cases = []
    for left in range(gods):
        for right in range(left, gods):
            placements = [(left, right)] if left == right else [(left, right), (right, left)]
            for home, away in placements:
                for first in (1, 2):
                    for _ in range(repetitions):
                        for player in (1, 2):
                            cases.append(
                                dict(
                                    left=home,
                                    right=away,
                                    first=first,
                                    player=player,
                                    seed=seed,
                                    block=seed,
                                )
                            )
                        seed += 1
    return cases


def outcome_stats(scores: list[float]) -> dict:
    if not scores:
        raise ValueError("evaluation vide")
    n = len(scores)
    wins, draws = scores.count(1.0), scores.count(0.5)
    return dict(
        games=n,
        wins=wins,
        draws=draws,
        losses=n - wins - draws,
        win_rate=wins / n,
        draw_rate=draws / n,
        loss_rate=(n - wins - draws) / n,
        score=sum(scores) / n,
    )


def duel_summary(cases: list[dict], outcomes: list[dict], scenarios: list[dict]) -> dict:
    scores, by_god, by_matchup, blocks = [], defaultdict(list), defaultdict(list), defaultdict(list)
    for case, info in zip(cases, outcomes, strict=True):
        winner = info["winner"]
        if type(winner) is not int or winner not in (0, 1, 2):
            raise ValueError("vainqueur invalide")
        player = case["player"]
        score = 0.5 if winner == 0 else float(winner == player)
        own = scenarios[case["left"] if player == 1 else case["right"]]["god"]
        other = scenarios[case["right"] if player == 1 else case["left"]]["god"]
        scores.append(score)
        by_god[own].append(score)
        by_matchup[f"{own}_vs_{other}"].append(score)
        blocks[case["block"]].append(score)
    if any(len(values) != 2 for values in blocks.values()):
        raise ValueError("duels incomplets : les deux roles doivent etre evalues")
    return dict(
        **outcome_stats(scores),
        by_god={name: outcome_stats(values) for name, values in by_god.items()},
        by_matchup={name: outcome_stats(values) for name, values in by_matchup.items()},
        paired_scores=[sum(v) / 2 for v in blocks.values()],
    )


def score_lower_bound(
    paired_scores: list[float], confidence: float, samples: int, seed: int
) -> float:
    """One-sided percentile bootstrap; resample whole paired starting setups.

    This approximate interval measures win + half-draw score, not raw wins.
    A private generator preserves the PPO and environment random streams.
    """
    values = np.asarray(paired_scores, dtype=np.float64)
    if values.size < 2 or not np.isfinite(values).all() or np.any((values < 0) | (values > 1)):
        raise ValueError("scores apparies invalides")
    if not 0.5 < confidence < 1 or samples < 100:
        raise ValueError("parametres du bootstrap invalides")
    rng = np.random.default_rng(seed)
    means = []
    for offset in range(0, samples, 128):
        means.extend(rng.choice(values, (min(128, samples - offset), len(values))).mean(axis=1))
    return float(np.quantile(means, 1 - confidence))


def promotion_judgement(summary: dict, settings: dict, seed: int) -> dict:
    lower = score_lower_bound(
        summary["paired_scores"],
        float(settings["confidence_level"]),
        int(settings["bootstrap_samples"]),
        seed,
    )
    return dict(
        passed=summary["score"] >= float(settings["minimum_score"]) and lower > 0.5,
        score=summary["score"],
        score_lower=lower,
        minimum_score=float(settings["minimum_score"]),
        confidence_level=float(settings["confidence_level"]),
        confidence_method="paired_percentile_bootstrap",
        games=summary["games"],
    )


def regression_judgement(candidate: dict, reference: dict, maximum: float) -> dict:
    """Compare each god to the champion's performance in the same matchups."""
    if set(candidate["by_god"]) != set(reference["by_god"]):
        raise ValueError("dieux manquants dans la reference")
    deltas = {
        god: values["score"] - reference["by_god"][god]["score"]
        for god, values in candidate["by_god"].items()
    }
    failed = [god for god, delta in deltas.items() if delta < -maximum - 1e-12]
    return dict(
        passed=not failed, score_deltas=deltas, maximum_regression=maximum, failed_gods=failed
    )


def validate_settings(settings: dict) -> None:
    required = {
        "protocol",
        "target_promotions",
        "minimum_updates_between_attempts",
        "maximum_updates_without_promotion",
        "maximum_history_anchors",
        "seed_base",
        "training_weights",
        "screen_games_per_slice",
        "screen_minimum_score",
        "promotion",
        "history",
        "retention",
        "final",
    }
    if not required <= set(settings) or set(settings) - required - {"mirror_probability"}:
        raise ValueError("configuration phase5 incomplete ou parametres de l'ancien plan")
    if settings.get("protocol") != "champion_v1":
        raise ValueError("phase5.protocol doit valoir champion_v1")
    for key in (
        "target_promotions",
        "minimum_updates_between_attempts",
        "maximum_updates_without_promotion",
        "maximum_history_anchors",
        "screen_games_per_slice",
    ):
        if int(settings[key]) < 1:
            raise ValueError(f"phase5.{key} doit etre positif")
    promotion = settings["promotion"]
    if int(settings["minimum_updates_between_attempts"]) > int(
        settings["maximum_updates_without_promotion"]
    ):
        raise ValueError("le delai entre tentatives depasse la patience du palier")
    for value in (
        promotion["games_per_slice"],
        promotion["confirmations"],
        settings["final"]["games_per_slice"],
        settings["history"]["games_per_slice"],
        settings["retention"]["games_per_slice"],
    ):
        if not 1 <= int(value) <= 64:
            raise ValueError("nombre de parties/confirmations hors limites [1, 64]")
    if int(promotion["confirmations"]) < 2:
        raise ValueError("au moins deux confirmations sont requises")
    for value in (promotion["minimum_score"], settings["screen_minimum_score"]):
        if not 0.5 < float(value) <= 1:
            raise ValueError("le score requis doit depasser 50 %")
    if float(settings["screen_minimum_score"]) > float(promotion["minimum_score"]):
        raise ValueError("la preselection ne doit pas etre plus exigeante que la promotion")
    weights = settings["training_weights"]
    if (
        set(weights) - {"current", "historical", "godot"}
        or any(not np.isfinite(v) or v < 0 for v in weights.values())
        or weights.get("current", 0) <= 0
        or sum(weights.values()) <= 0
    ):
        raise ValueError("poids de ligue invalides")
    if not 0 <= float(settings.get("mirror_probability", 0.1)) <= 1:
        raise ValueError("mirror_probability doit etre entre 0 et 1")
    if not 0 <= int(settings["seed_base"]) < 2**63 - 100_000_000_000:
        raise ValueError("seed_base doit rester dans le domaine entier Godot")
    for block, keys in (
        ("promotion", ("maximum_god_regression",)),
        ("history", ("maximum_regression", "minimum_score")),
        ("retention", ("maximum_stage_regression", "maximum_god_regression")),
    ):
        if any(
            not np.isfinite(float(settings[block][key]))
            or not 0 <= float(settings[block][key]) <= 1
            for key in keys
        ):
            raise ValueError("seuil de retention invalide")
    score_lower_bound(
        [0.5, 0.5], float(promotion["confidence_level"]), int(promotion["bootstrap_samples"]), 0
    )
