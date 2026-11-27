"""Compare PPO on the original and equal-budget decks in isolated runs."""

import argparse
import json
from copy import deepcopy
from pathlib import Path

import yaml

from samstone_rl.bridge.godot_process import GodotProcess
from samstone_rl.decks.catalog import DeckCatalog
from samstone_rl.decks.generator import DeckGenerator
from samstone_rl.models.policy import policy_spec
from samstone_rl.training.league import LeagueOpponent, SelfPlayLeague
from samstone_rl.training.phase_five_arena import PhaseFiveArena
from samstone_rl.training.ppo_cleanrl import PPOTrainer
from samstone_rl.training.ppo_self_play import PhaseFiveTrainer
from samstone_rl.utils.checkpoints import atomic_text, file_checksum, load_checkpoint
from samstone_rl.utils.provenance import provenance


class PilotTrainer(PPOTrainer):
    _training_scenario_options = PhaseFiveTrainer._training_scenario_options
    _evaluation_game_count = PhaseFiveTrainer._evaluation_game_count

    def _training_opponent(self):
        return LeagueOpponent(self.league)

    def _phase5_progress(self, operation, completed, total):
        if completed == total:
            print(f"{operation}: {completed}/{total}", flush=True)


def train_arm(config, scenarios, output, source, weights, updates):
    config = deepcopy(config)
    config["environment"]["scenarios"] = scenarios
    config["ppo"]["total_timesteps"] = (
        updates * config["ppo"]["rollout_steps"] * config["ppo"]["num_envs"]
    )
    config["evaluation"]["every_updates"] = updates + 1
    output.mkdir()
    path = output / "config.yaml"
    atomic_text(path, yaml.safe_dump(config, sort_keys=False))
    with PilotTrainer(path, output_override=output) as trainer:
        trainer.model.load_state_dict(weights["model"])
        trainer.league = SelfPlayLeague(
            output / "league", {"current": 0.5, "godot": 0.5}, "cpu", trainer.curriculum.stages
        )
        trainer.league.register(source, 0, 0.5, "current")
        trainer.train()
    return output / "latest.pt"


def run(args):
    config = yaml.safe_load(args.config.read_text(encoding="utf-8"))
    weights = load_checkpoint(args.checkpoint)
    current = provenance()
    recorded = weights["provenance"]
    if any(
        recorded.get(key) != current[key] for key in ("game_rules", "content", "feature_schema")
    ):
        raise ValueError("utiliser le jeu compatible avec le checkpoint source")
    if weights["policy_spec"] != policy_spec(config):
        raise ValueError("architecture du checkpoint incompatible")
    original = config["environment"]["scenarios"]
    with GodotProcess(godot_path=config["environment"].get("godot_path")) as bridge:
        catalog = DeckCatalog(bridge.deck_catalog())
        generator = DeckGenerator(catalog)
        matched = [
            dict(
                god=case["god"],
                deck=list(
                    generator.match_budget(
                        case["god"],
                        case["deck"],
                        catalog.deck_budget,
                    )
                ),
            )
            for case in original
        ]
        for case in matched:
            validated = bridge.validate_deck(case["deck"], case["god"])
            if not validated["valid"] or validated["cost"] != catalog.deck_budget:
                raise ValueError(f"deck a budget commun invalide pour {case['god']}: {validated}")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = dict(
        source=str(args.checkpoint.resolve()),
        source_sha256=file_checksum(args.checkpoint),
        updates=args.updates,
        training_seed=config["seed"],
        duel_seed=8_900_000_000_000,
        bot_seed=8_910_000_000_000,
        duel_repetitions=2,
        original_decks=original,
        matched_decks=matched,
        deck_costs={case["god"]: catalog.cost(case["deck"]) for case in original},
        target_budget=catalog.deck_budget,
        status="training",
    )
    path = output / "report.json"
    atomic_text(path, json.dumps(report, indent=2))
    arms = {}
    for label, scenarios in (("original", original), ("matched", matched)):
        print(f"PPO {label}: {args.updates} mises a jour", flush=True)
        arms[label] = train_arm(
            config, scenarios, output / label, args.checkpoint, weights, args.updates
        )
    report["status"] = "evaluating"
    atomic_text(path, json.dumps(report, indent=2))
    evaluation_dir = output / "evaluation"
    with PilotTrainer(output / "matched/config.yaml", output_override=evaluation_dir) as trainer:
        trainer.phase5_state = {}
        arena = PhaseFiveArena(trainer)
        actor = arena.opponent(arms["matched"]).model
        _, _, duel = arena.duels(
            actor,
            arms["original"],
            report["duel_repetitions"],
            report["duel_seed"],
            "matched_vs_original",
        )
        trainer.curriculum.stages = trainer.curriculum.stages[-1:]
        bot_reports = {
            label: arena.retention(
                arena.opponent(checkpoint).model,
                args.checkpoint,
                2,
                report["bot_seed"],
                "pilot_bots",
            )
            for label, checkpoint in arms.items()
        }
    report.update(status="completed", duels=duel, bots=bot_reports)
    atomic_text(path, json.dumps(report, indent=2, allow_nan=False))
    print(f"Rapport: {path}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path("configs/ppo_self_play_v2.yaml"))
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--updates", type=int, default=32)
    args = parser.parse_args()
    if args.updates < 1:
        parser.error("updates doit etre positif")
    run(args)


if __name__ == "__main__":
    main()
