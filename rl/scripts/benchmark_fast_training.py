#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import statistics
import tempfile
from pathlib import Path

import yaml

from samstone_rl.training.ppo_cleanrl import PPOTrainer


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Mesure un vrai cycle collecte + optimisation PPO sur le moteur Python.")
    parser.add_argument("--config", type=Path,
                        default=Path("configs/ppo_phase4_tactical.yaml"))
    parser.add_argument("--updates", type=int, default=5)
    parser.add_argument("--num-envs", type=int)
    parser.add_argument("--batch-size", type=int, default=1024)
    parser.add_argument("--minibatches", type=int)
    parser.add_argument("--epochs", type=int)
    parser.add_argument("--backend", choices=("python", "python_batch"))
    parser.add_argument("--device", choices=("cpu", "directml"))
    parser.add_argument(
        "--scalar-tactical", action="store_true",
        help="desactive le noyau tactique vectorise pour mesurer la reference")
    parser.add_argument(
        "--scalar-effects", action="store_true",
        help="conserve le noyau mais remet Essaim/Pillage sur le fallback exact")
    parser.add_argument(
        "--stage", help="limite le benchmark a un palier du curriculum")
    args = parser.parse_args()
    if args.updates <= 0 or args.batch_size <= 0:
        parser.error("updates et batch-size doivent etre strictement positifs")

    config = yaml.safe_load(args.config.read_text(encoding="utf-8"))
    if args.backend:
        config["environment"]["backend"] = args.backend
    if args.device:
        config["device"] = args.device
    if args.scalar_tactical:
        config["environment"]["vector_tactical"] = False
    if args.scalar_effects:
        config["environment"]["vector_effects"] = False
    if args.stage:
        matching = [stage for stage in config["curriculum"]["stages"]
                    if stage["name"] == args.stage]
        if not matching:
            parser.error(f"palier inconnu: {args.stage}")
        config["curriculum"]["stages"] = matching
    num_envs = int(args.num_envs or config["ppo"].get("num_envs", 1))
    if num_envs <= 0 or args.batch_size % num_envs:
        parser.error("num-envs doit etre positif et diviser exactement batch-size")
    config["ppo"].update({
        "num_envs": num_envs,
        "rollout_steps": args.batch_size // num_envs,
        "total_timesteps": args.batch_size * args.updates,
    })
    if args.minibatches:
        config["ppo"]["minibatches"] = args.minibatches
    if args.epochs:
        config["ppo"].update({
            "update_epochs": args.epochs,
            "min_update_epochs": args.epochs,
            "max_update_epochs": args.epochs,
        })
    # This benchmark deliberately avoids Godot evaluation and checkpoint I/O.
    config["environment"]["evaluation_backend"] = "python"
    config["evaluation"]["every_updates"] = args.updates + 1
    config["curriculum"]["bootstrap_evaluation"] = {"enabled": False}
    config["monitoring"].update({
        "tensorboard": False,
        "checkpoint_every_updates": 0,
        "snapshot_every_updates": 0,
    })

    with tempfile.TemporaryDirectory(prefix="samstone-fast-benchmark-") as directory:
        root = Path(directory)
        config["output_dir"] = str(root / "run")
        config_path = root / "benchmark.yaml"
        config_path.write_text(yaml.safe_dump(config), encoding="utf-8")
        PPOTrainer(config_path).train()
        events = [json.loads(line) for line in (root / "run" / "metrics.jsonl").read_text(
            encoding="utf-8").splitlines() if line]

    metrics = [event["metrics"] for event in events if event["stream"] == "training"]
    decisions = statistics.median(float(item["steps_per_second"]) for item in metrics)
    games = statistics.median(float(item["training_games_per_second"]) for item in metrics)
    seconds = statistics.median(float(item["update_seconds"]) for item in metrics)
    backend = config["environment"].get("backend", "python")
    tactical = ("scalaire" if args.scalar_tactical else "vectorise")
    effects = ("scalaire" if not config["environment"].get("vector_effects", True)
               else "vectorise")
    print(f"PPO {backend}: {num_envs} environnements, batch {args.batch_size}, "
          f"tactique {tactical}, effets {effects}, "
          f"mediane sur {len(metrics)} updates")
    print(f"  {decisions:.2f} decisions agent/s")
    print(f"  {games:.2f} parties terminees/s")
    print(f"  {seconds:.3f} s/update (collecte + optimisation)")
    if vector := metrics[-1].get("vector_engine"):
        print(f"  couverture vectorisee: {float(vector.get('coverage', 0.0)):.1%}")
        print("  tactique: " + ", ".join(
            f"{name}={float(vector.get(name + '_seconds', 0.0)):.3f}s"
            for name in ("extraction", "kernel", "fallback")))
        print(f"  espace reutilise: {float(vector.get('workspace_mb', 0.0)):.1f} Mio")
    phases = ("environment_seconds", "reset_seconds", "optimization_seconds")
    print("  profil median: " + ", ".join(
        f"{name.removesuffix('_seconds')}={statistics.median(float(item['profile'][name]) for item in metrics):.3f}s"
        for name in phases))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
