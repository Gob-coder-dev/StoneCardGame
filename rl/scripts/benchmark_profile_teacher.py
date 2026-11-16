"""Compare teacher implementations on identical short PPO runs, outside user runs."""

from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path
from statistics import median

import yaml

from samstone_rl.training.ppo_cleanrl import PPOTrainer
from samstone_rl.utils.checkpoints import file_checksum


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path("configs/ppo_phase4_vectorized.yaml"))
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--updates", type=int, default=3)
    parser.add_argument("--stage", type=int, default=6)
    parser.add_argument(
        "--backends", nargs="+", choices=("python", "godot"), default=["python", "godot"]
    )
    args = parser.parse_args()
    if args.updates <= 0:
        parser.error("updates doit etre positif")
    results = []
    source_checksum = file_checksum(args.checkpoint)
    for backend in args.backends:
        config = yaml.safe_load(args.config.read_text(encoding="utf-8"))
        config["environment"]["profile_backend"] = backend
        ppo = config["ppo"]
        ppo["total_timesteps"] = args.updates * ppo["num_envs"] * ppo["rollout_steps"]
        config["curriculum"]["bootstrap_evaluation"]["enabled"] = False
        config["evaluation"]["every_updates"] = args.updates + 1
        config["monitoring"].update(
            tensorboard=False, checkpoint_every_updates=0, snapshot_every_updates=0
        )
        with tempfile.TemporaryDirectory(prefix="samstone-teacher-benchmark-") as directory:
            config["output_dir"] = str(Path(directory) / "run")
            path = Path(directory) / "config.yaml"
            path.write_text(yaml.safe_dump(config), encoding="utf-8")
            with PPOTrainer(path) as trainer:
                if not 0 <= args.stage < len(trainer.curriculum.stages):
                    parser.error("stage hors curriculum")
                trainer.load_checkpoint(
                    args.checkpoint, load_optimizer=False, load_training_state=False
                )
                if file_checksum(args.checkpoint) != source_checksum:
                    raise RuntimeError(
                        "checkpoint modifie pendant le benchmark; utiliser un snapshot fixe"
                    )
                trainer.curriculum.stage_index = args.stage
                trainer.train()
            events = [
                json.loads(line)
                for line in (Path(directory) / "run/metrics.jsonl")
                .read_text(encoding="utf-8")
                .splitlines()
            ]
            rows = [event["metrics"] for event in events if event["stream"] == "training"]
            # Include collection and optimization, exclude process startup and
            # validation, which are not part of update_seconds.
            result = {
                "backend": backend,
                "checkpoint_sha256": source_checksum,
                "updates": len(rows),
                "update_seconds": [round(row["update_seconds"], 4) for row in rows],
                "median_update_seconds": median(row["update_seconds"] for row in rows),
                "median_decisions_per_second": median(row["steps_per_second"] for row in rows),
                "epochs": [row["epochs_used"] for row in rows],
            }
            results.append(result)
            print(json.dumps(result), flush=True)
    if len(results) == 2:
        by_backend = {result["backend"]: result for result in results}
        print(
            json.dumps(
                {
                    "python_speedup": by_backend["godot"]["median_update_seconds"]
                    / by_backend["python"]["median_update_seconds"]
                }
            ),
            flush=True,
        )


if __name__ == "__main__":
    main()
