"""Promotion and independent final assessment of a frozen phase-5 candidate."""

from samstone_rl.training.phase_five_protocol import (
    duel_summary,
    promotion_judgement,
    regression_judgement,
)


def evaluate_candidate(trainer, pending: dict) -> dict:
    """All rounds reuse exact frozen weights; ledgers make interruptions resumable."""
    arena, settings = trainer.arena, trainer.config["phase5"]
    actor = arena.opponent(trainer.output / pending["path"]).model
    champion = trainer.output / trainer.phase5_state["champions"][-1]["path"]
    guards = evaluate_guards(trainer, actor, pending, domain=3)
    if not guards["passed"]:
        return dict(passed=False, reason="retention", guards=guards, confirmations=[])
    all_cases, all_outcomes, rounds = [], [], []
    for round_index in range(int(settings["promotion"]["confirmations"])):
        seed = trainer._phase5_seed(1, pending["attempt"], round_index)
        cases, outcomes, summary = arena.duels(
            actor,
            champion,
            int(settings["promotion"]["games_per_slice"]),
            seed,
            f"confirmation_{round_index + 1}",
        )
        judgement = promotion_judgement(summary, settings["promotion"], seed)
        rounds.append(judgement)
        if not judgement["passed"]:
            return dict(
                passed=False,
                reason="confirmation",
                guards=guards,
                confirmations=rounds,
                minimum_confirmation_score=min(r["score"] for r in rounds),
                minimum_confirmation_score_lower=min(r["score_lower"] for r in rounds),
            )
        all_cases.extend(cases)
        all_outcomes.extend(outcomes)
    pooled = duel_summary(all_cases, all_outcomes, trainer.scenarios)
    reference = arena.champion_reference(all_cases, champion, "champion_self_reference")
    regression = regression_judgement(
        pooled, reference, float(settings["promotion"]["maximum_god_regression"])
    )
    report = dict(
        passed=regression["passed"],
        confirmations=rounds,
        minimum_confirmation_score=min(r["score"] for r in rounds),
        minimum_confirmation_score_lower=min(r["score_lower"] for r in rounds),
        candidate=pooled,
        champion_self_reference=reference,
        god_regression=regression,
        guards=guards,
    )
    if not report["passed"]:
        report["reason"] = "god_regression"
        return report
    if pending["final"]:
        seed = trainer._phase5_seed(2, pending["attempt"])
        cases, outcomes, summary = arena.duels(
            actor,
            champion,
            int(settings["final"]["games_per_slice"]),
            seed,
            "final_holdout",
        )
        holdout = promotion_judgement(summary, settings["promotion"], seed)
        baseline = arena.champion_reference(cases, champion, "final_champion_self_reference")
        holdout["god_regression"] = regression_judgement(
            summary, baseline, float(settings["promotion"]["maximum_god_regression"])
        )
        holdout["guards"] = evaluate_guards(trainer, actor, pending, domain=5)
        holdout["passed"] &= holdout["god_regression"]["passed"] and holdout["guards"]["passed"]
        report["holdout"] = holdout
        report["passed"] = holdout["passed"]
        if not report["passed"]:
            report["reason"] = "final_holdout"
    return report


def evaluate_guards(trainer, actor, pending, domain):
    settings, arena = trainer.config["phase5"], trainer.arena
    retention = arena.retention(
        actor,
        trainer.phase4_baseline,
        int(settings["retention"]["games_per_slice"]),
        trainer._phase5_seed(domain + 1, pending["attempt"]),
        "final_retention" if domain == 5 else "retention",
    )
    if not retention["passed"]:
        return dict(passed=False, history={}, godot=retention)
    history = trainer._phase5_history()
    current = arena.opponent(trainer.output / trainer.phase5_state["champions"][-1]["path"]).model
    results = {}
    for index, entry in enumerate(history):
        seed = trainer._phase5_seed(domain, pending["attempt"], index)
        path = trainer.output / entry["path"]
        repetitions = int(settings["history"]["games_per_slice"])
        _, _, candidate = arena.duels(
            actor, path, repetitions, seed, f"history_{domain}_{index}_candidate"
        )
        _, _, reference = arena.duels(
            current, path, repetitions, seed, f"history_{domain}_{index}_reference"
        )
        results[str(entry["generation"])] = dict(
            passed=(
                candidate["score"] >= float(settings["history"]["minimum_score"])
                and candidate["score"]
                >= reference["score"] - float(settings["history"]["maximum_regression"]) - 1e-12
            ),
            candidate_score=candidate["score"],
            reference_score=reference["score"],
        )
    return dict(
        passed=retention["passed"] and all(r["passed"] for r in results.values()),
        history=results,
        godot=retention,
    )
