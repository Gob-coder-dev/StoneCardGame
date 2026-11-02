#!/usr/bin/env python3
"""Compare PPO checkpoints on an identical, balanced set of Godot matches."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from itertools import product
from pathlib import Path
from typing import Any

import torch
import yaml

from samstone_rl.envs import SamStoneEnv
from samstone_rl.evaluation.paired import (
    ComparisonCase,
    ComparisonOutcome,
    grouped_summary,
    outcome_row,
    paired_delta,
)
from samstone_rl.models.actor_critic import ActorCritic
from samstone_rl.training.curriculum import DEFAULT_STAGES


def scenario_options(scenario: dict[str, Any]) -> dict[str, Any]:
    """Build the same mirror-deck configuration used by PPO evaluation."""
    config = dict(scenario)
    deck = list(config.pop("deck"))
    god = str(config.pop("god"))
    config.update({"human_deck": deck, "ai_deck": deck, "human_god": god, "ai_god": god})
    return {"config": config}


def checkpoint_label(path: Path) -> str:
    parent = path.parent.parent if path.parent.name == "checkpoints" else path.parent
    return f"{parent.name}/{path.stem}"


def checksum(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_model(path: Path, observation_size: int, action_size: int, device: torch.device) -> ActorCritic:
    checkpoint = torch.load(path, map_location=device, weights_only=False)
    state = checkpoint["model"]
    hidden = int(state["backbone.0.weight"].shape[0])
    expected_observation = int(state["backbone.0.weight"].shape[1])
    expected_actions = int(state["actor.weight"].shape[0])
    if expected_observation != observation_size or expected_actions != action_size:
        raise ValueError(f"checkpoint incompatible: {path}")
    model = ActorCritic(observation_size, action_size, hidden).to(device)
    model.load_state_dict(state)
    model.eval()
    return model


def build_cases(env: SamStoneEnv, scenarios: list[dict[str, Any]], games: int,
                seed_base: int, blocked_counts: tuple[int, ...], max_attempts: int) -> list[ComparisonCase]:
    """Resolve a fixed actual seed for every balanced evaluation case."""
    strata = list(product(range(len(scenarios)), (1, 2), (1, 2), blocked_counts))
    if games % len(strata) != 0:
        raise ValueError(f"--games doit être divisible par {len(strata)} pour un planning équilibré")
    cases: list[ComparisonCase] = []
    for case_id in range(games):
        scenario_index, agent_player, first_player, target_blocked = strata[case_id % len(strata)]
        options = scenario_options(scenarios[scenario_index])
        options["config"]["first_player"] = first_player
        actual_seed = None
        for attempt in range(max_attempts):
            candidate = seed_base + case_id * max_attempts + attempt
            env.agent_player = agent_player
            _, info = env.reset(seed=candidate, options=options)
            if len(info["blocked"]) == target_blocked:
                actual_seed = candidate
                break
        if actual_seed is None:
            raise RuntimeError(
                f"terrain {target_blocked} introuvable pour le cas {case_id} après {max_attempts} seeds")
        cases.append(ComparisonCase(
            case_id=case_id,
            seed=actual_seed,
            scenario_index=scenario_index,
            god=str(scenarios[scenario_index]["god"]),
            agent_player=agent_player,
            first_player=first_player,
            blocked_count=target_blocked,
        ))
    return cases


def play_case(env: SamStoneEnv, model: ActorCritic, case: ComparisonCase,
              scenario: dict[str, Any], opponent: Any, device: torch.device) -> ComparisonOutcome:
    env.opponent = opponent
    env.agent_player = case.agent_player
    options = scenario_options(scenario)
    options["config"]["first_player"] = case.first_player
    observation, info = env.reset(seed=case.seed, options=options)
    if len(info["blocked"]) != case.blocked_count:
        raise RuntimeError(f"seed incohérent pour le cas {case.case_id}")
    terminated = False
    while not terminated:
        with torch.no_grad():
            action, _, _ = model.act(
                torch.as_tensor(observation, dtype=torch.float32, device=device).unsqueeze(0),
                torch.as_tensor(info["action_mask"], dtype=torch.bool, device=device).unsqueeze(0),
                deterministic=True,
            )
        observation, _, ended, truncated, info = env.step(int(action.item()))
        terminated = ended or truncated
    episode = info["episode"]
    return ComparisonOutcome(
        model="",
        checkpoint="",
        case=case,
        winner=int(info["winner"]),
        margin=int(episode["margin"]),
        turns=int(episode["turns"]),
    )


def write_json(path: Path, payload: dict[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    temporary.replace(path)


def write_markdown(path: Path, models: dict[str, dict[str, Any]], pairs: dict[str, dict[str, Any]]) -> None:
    lines = ["# Comparaison appariée des checkpoints", "", "## Résultats globaux", "",
             "| Modèle | Parties | Win rate | Wilson lower | Loss rate | Marge moyenne |",
             "|---|---:|---:|---:|---:|---:|"]
    for label, result in models.items():
        overall = result["summary"]["overall"]
        lines.append(
            f"| {label} | {overall['games']} | {overall['win_rate']:.3%} | "
            f"{overall['wilson_lower']:.3%} | {overall['loss_rate']:.3%} | "
            f"{overall['mean_margin']:.2f} |")
    if pairs:
        lines.extend(["", "## Comparaisons appariées", "",
                      "| Référence → candidat | Candidat meilleur | Identique | Candidat pire | Delta score moyen | p-value signe |",
                      "|---|---:|---:|---:|---:|---:|"])
        for label, result in pairs.items():
            lines.append(
                f"| {label} | {result['candidate_better']} | {result['same']} | "
                f"{result['candidate_worse']} | {result['mean_score_delta']:+.4f} | "
                f"{result['two_sided_sign_p_value']:.4f} |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare plusieurs checkpoints sur les mêmes seeds et conditions Godot.")
    parser.add_argument("checkpoints", nargs="+", type=Path)
    parser.add_argument("--config", type=Path,
                        default=Path(__file__).resolve().parents[1]
                        / "configs" / "ppo_phase4_tactical.yaml")
    parser.add_argument("--stage", default="precision_025", choices=[stage.name for stage in DEFAULT_STAGES])
    parser.add_argument("--games", type=int, default=720,
                        help="Multiple de 72 avec les 6 dieux, 2 côtés, 2 départs et 3 terrains.")
    parser.add_argument("--seed-base", type=int, default=2100000000)
    parser.add_argument("--blocked-counts", default="0,1,2")
    parser.add_argument("--max-terrain-attempts", type=int, default=64)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if len(args.checkpoints) < 2:
        parser.error("au moins deux checkpoints sont requis")
    if len({path.resolve() for path in args.checkpoints}) != len(args.checkpoints):
        parser.error("un checkpoint ne peut être fourni qu'une fois")
    for checkpoint in args.checkpoints:
        if not checkpoint.is_file():
            parser.error(f"checkpoint introuvable: {checkpoint}")
    blocked_counts = tuple(int(value.strip()) for value in args.blocked_counts.split(",") if value.strip())
    if not blocked_counts or min(blocked_counts) < 0 or args.max_terrain_attempts <= 0:
        parser.error("terrains ou tentatives invalides")
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error(f"dossier de sortie non vide: {output}")
    output.mkdir(parents=True, exist_ok=True)

    with args.config.open(encoding="utf-8") as stream:
        config = yaml.safe_load(stream)
    scenarios = list(config["environment"]["scenarios"])
    if not scenarios:
        parser.error("la configuration ne contient aucun scénario")
    stage = next(item for item in DEFAULT_STAGES if item.name == args.stage)
    backend = str(config["environment"].get("evaluation_backend", "godot"))
    if backend != "godot":
        parser.error("la comparaison officielle doit utiliser evaluation_backend: godot")
    device = torch.device(config.get("device", "cpu"))
    env = SamStoneEnv(
        godot_path=config["environment"].get("godot_path"),
        opponent=stage.opponent(),
        backend="godot",
    )
    try:
        cases = build_cases(env, scenarios, args.games, args.seed_base, blocked_counts,
                            args.max_terrain_attempts)
        models: dict[str, dict[str, Any]] = {}
        all_outcomes: dict[str, list[ComparisonOutcome]] = {}
        for index, checkpoint in enumerate(args.checkpoints, start=1):
            label = checkpoint_label(checkpoint.resolve())
            if label in models:
                label = f"{label}#{index}"
            model = load_model(checkpoint, env.observation_space.shape[0], env.action_space.n, device)
            outcomes: list[ComparisonOutcome] = []
            for count, case in enumerate(cases, start=1):
                raw = play_case(env, model, case, scenarios[case.scenario_index], stage.opponent(), device)
                outcomes.append(ComparisonOutcome(label, str(checkpoint.resolve()), raw.case, raw.winner,
                                                  raw.margin, raw.turns))
                if count % 100 == 0 or count == len(cases):
                    print(f"{label}: {count}/{len(cases)}")
            all_outcomes[label] = outcomes
            models[label] = {
                "checkpoint": str(checkpoint.resolve()),
                "sha256": checksum(checkpoint),
                "summary": grouped_summary(outcomes),
            }
        reference_label = next(iter(models))
        pairs = {f"{reference_label} → {label}": paired_delta(all_outcomes[reference_label], outcomes)
                 for label, outcomes in all_outcomes.items() if label != reference_label}
        rows = [outcome_row(item) for outcomes in all_outcomes.values() for item in outcomes]
        with (output / "outcomes.csv").open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        report = {
            "schema_version": 1,
            "config": str(args.config.resolve()),
            "stage": args.stage,
            "seed_base": args.seed_base,
            "games_per_model": len(cases),
            "blocked_counts": list(blocked_counts),
            "cases": [case.__dict__ for case in cases],
            "models": models,
            "paired_against_first": pairs,
        }
        write_json(output / "comparison.json", report)
        write_markdown(output / "summary.md", models, pairs)
        print(f"Rapport créé: {output}")
        for label, model in models.items():
            overall = model["summary"]["overall"]
            print(f"{label}: win={overall['win_rate']:.3%}, Wilson={overall['wilson_lower']:.3%}")
        return 0
    finally:
        env.close()


if __name__ == "__main__":
    raise SystemExit(main())
