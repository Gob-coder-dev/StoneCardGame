"""Summaries for the low-overhead PPO phase profiler."""

from __future__ import annotations

from pathlib import Path
from statistics import mean
from typing import Any

from .training_report import load_json_lines

PROFILE_PHASES = (
    "storage",
    "preparation",
    "policy",
    "environment",
    "bookkeeping",
    "reset",
    "bootstrap_gae",
    "optimization",
    "other",
)


def summarize_run_profile(run_directory: str | Path, last_updates: int = 500) -> dict[str, Any]:
    """Aggregate recent phase timings and identify the useful optimization target."""
    if last_updates <= 0:
        raise ValueError("last_updates doit être strictement positif")
    run = Path(run_directory).resolve()
    events = load_json_lines(run / "metrics.jsonl")
    training = [event for event in events
                if event.get("stream") == "training"
                and isinstance(event.get("metrics", {}).get("profile"), dict)]
    selected = training[-last_updates:]
    if not selected:
        raise ValueError("aucune métrique de profilage; relancer avec le trainer récent")

    profiles = [event["metrics"]["profile"] for event in selected]
    total_seconds = sum(float(item.get("total_seconds", 0.0)) for item in profiles)
    if total_seconds <= 0.0:
        raise ValueError("temps de profilage invalide")
    phases = {
        name: {
            "mean_seconds": mean(float(item.get(f"{name}_seconds", 0.0)) for item in profiles),
            "fraction": sum(float(item.get(f"{name}_seconds", 0.0))
                            for item in profiles) / total_seconds,
        }
        for name in PROFILE_PHASES
    }
    simulation_fraction = phases["environment"]["fraction"] + phases["reset"]["fraction"]
    neural_fraction = phases["policy"]["fraction"] + phases["optimization"]["fraction"]
    dominant = max(PROFILE_PHASES, key=lambda name: phases[name]["fraction"])

    all_training_seconds = sum(float(event.get("metrics", {}).get("update_seconds", 0.0))
                               for event in events if event.get("stream") == "training")
    all_evaluation_seconds = sum(float(event.get("metrics", {}).get(
        "evaluation_seconds", 0.0)) for event in events if event.get("stream") == "evaluation")
    measured_wall = all_training_seconds + all_evaluation_seconds
    evaluation_fraction = all_evaluation_seconds / measured_wall if measured_wall else 0.0

    if simulation_fraction >= 0.45:
        decision = "vectorization_recommended"
    elif neural_fraction >= 0.45:
        decision = "optimize_neural_compute_first"
    else:
        decision = "mixed_profile_measure_before_rewrite"
    return {
        "run": str(run),
        "updates_available": len(training),
        "updates_analyzed": len(selected),
        "first_step": int(selected[0].get("step", 0)),
        "last_step": int(selected[-1].get("step", 0)),
        "mean_update_seconds": mean(float(item.get("total_seconds", 0.0))
                                    for item in profiles),
        "phases": phases,
        "dominant_phase": dominant,
        "simulation_fraction": simulation_fraction,
        "neural_fraction": neural_fraction,
        "evaluation_fraction_of_measured_time": evaluation_fraction,
        "decision": decision,
    }
