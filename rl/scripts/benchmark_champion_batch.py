"""Compare frozen-opponent and rollout optimizations with real PPO updates."""

import argparse
import json
import statistics
import tempfile
import time
from copy import deepcopy
from pathlib import Path
from unittest.mock import patch

import torch

from samstone_rl.batch_engine import BatchSamStoneEnv
from samstone_rl.opponents.checkpoint import CheckpointOpponent
from samstone_rl.training.league import LeagueOpponent, SelfPlayLeague
from samstone_rl.training.ppo_cleanrl import PPOTrainer
from samstone_rl.training.ppo_self_play import PhaseFiveTrainer
from samstone_rl.utils.checkpoints import atomic_text, load_checkpoint, state_checksum


class BenchmarkTrainer(PPOTrainer):
    _training_scenario_options = PhaseFiveTrainer._training_scenario_options
    _evaluation_game_count = PhaseFiveTrainer._evaluation_game_count

    def _training_opponent(self):
        return LeagueOpponent(self.league)


def measure(config, checkpoint, source, mode, updates, warmup):
    """Use a temporary league and logs. Evaluation and saving are excluded."""
    batch_choose = CheckpointOpponent.choose_many
    batch_step = BatchSamStoneEnv.step

    def choose(opponent, requests, *, evaluate_tactics=None):
        if mode in ("baseline", "terminal_skip"):
            requests = [
                (bridge, bridge.legal_actions() if moves is None else moves, rng, player)
                for bridge, moves, rng, player in requests
            ]
        if mode == "scalar":
            return [batch_choose(opponent, [request])[0] for request in requests]
        return batch_choose(
            opponent,
            requests,
            evaluate_tactics=evaluate_tactics if mode == "vector_tactics" else None,
        )

    def step(env, actions, *, encode_terminal=True):
        return batch_step(
            env,
            actions,
            encode_terminal=True if mode in ("baseline", "direct_mask") else encode_terminal,
        )

    with tempfile.TemporaryDirectory(prefix="champion_benchmark_") as temporary:
        with (
            patch.object(CheckpointOpponent, "choose_many", choose),
            patch.object(BatchSamStoneEnv, "step", step),
        ):
            with BenchmarkTrainer(config, output_override=Path(temporary) / "run") as trainer:
                trainer.model.load_state_dict(source["model"])
                trainer.optimizer.load_state_dict(deepcopy(source["optimizer"]))
                trainer.curriculum.load_state_dict(source["curriculum"])
                trainer.league = SelfPlayLeague(
                    Path(temporary) / "league",
                    trainer.config["phase5"]["training_weights"],
                    "cpu",
                    trainer.curriculum.stages,
                )
                for entry in source["phase5"]["champion_curriculum"]["champions"]:
                    category = (
                        "current"
                        if entry == source["phase5"]["champion_curriculum"]["champions"][-1]
                        else "historical"
                    )
                    trainer.league.register(
                        checkpoint.parent / entry["path"],
                        entry["global_step"],
                        entry["score"],
                        category,
                    )
                # Freeze loading overhead outside the timed sections.
                for entry in trainer.league.entries:
                    trainer.league._cache[
                        str((trainer.league.directory / entry.path).resolve())
                    ] = CheckpointOpponent(
                        trainer.league.directory / entry.path, deterministic=False
                    )
                trainer.rng.bit_generator.state = source["rng"]["numpy"]
                torch.set_rng_state(source["rng"]["torch"])
                obs, infos = trainer._reset_training_episodes(list(range(trainer.num_envs)))
                rows = []
                for update in range(warmup + updates):
                    started = time.perf_counter()
                    rollout = trainer._collect_rollout(
                        obs, infos, trainer.config["ppo"]["rollout_steps"], 0, update + 1
                    )
                    obs, infos = rollout.observations, rollout.infos
                    with torch.no_grad():
                        next_values = trainer.model.value(
                            torch.as_tensor(trainer.batch_env.observations, device=trainer.device)
                        )
                    advantages, returns = trainer._gae_vectorized(
                        rollout.storage, next_values, trainer.config["ppo"]["rollout_steps"]
                    )
                    trainer._optimize(rollout.storage, advantages, returns)
                    elapsed = time.perf_counter() - started
                    if update >= warmup:
                        rows.append(dict(seconds=elapsed, games=len(rollout.episodes)))
                return dict(
                    mode=mode,
                    seconds=sum(r["seconds"] for r in rows),
                    games=sum(r["games"] for r in rows),
                    updates=updates,
                    decisions=updates * trainer.num_envs * trainer.config["ppo"]["rollout_steps"],
                    final_policy=state_checksum(trainer.model.state_dict()),
                )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--config", type=Path, default=Path("configs/ppo_self_play_v2.yaml"))
    parser.add_argument("--updates", type=int, default=10)
    parser.add_argument("--warmup", type=int, default=2)
    parser.add_argument("--repeats", type=int, default=2)
    parser.add_argument(
        "--comparison", choices=("batching", "rollout", "tactics"), default="batching"
    )
    parser.add_argument(
        "--ablation", action="store_true", help="Mesurer chaque optimisation de collecte separement"
    )
    parser.add_argument(
        "--output", type=Path, default=Path("artifacts/champion_batch_benchmark.json")
    )
    args = parser.parse_args()
    if args.updates < 1 or args.repeats < 1 or args.warmup < 0:
        parser.error("updates/repeats >= 1 et warmup >= 0 requis")
    if args.ablation and args.comparison != "rollout":
        parser.error("--ablation exige --comparison rollout")
    modes = {
        "batching": ("scalar", "batch"),
        "rollout": ("baseline", "optimized"),
        "tactics": ("scalar_tactics", "vector_tactics"),
    }[args.comparison]
    if args.ablation:
        modes = ("baseline", "direct_mask", "terminal_skip", "optimized")
    checkpoint = args.checkpoint.resolve()
    source = load_checkpoint(checkpoint)
    rows = []
    for repeat in range(args.repeats):
        order = modes if repeat % 2 == 0 else tuple(reversed(modes))
        for mode in order:
            result = measure(args.config, checkpoint, source, mode, args.updates, args.warmup)
            result["games_per_second"] = result["games"] / result["seconds"]
            result["decisions_per_second"] = result["decisions"] / result["seconds"]
            rows.append(result)
            print(json.dumps(result), flush=True)
    rates = {
        mode: statistics.mean(r["decisions_per_second"] for r in rows if r["mode"] == mode)
        for mode in modes
    }
    report = dict(
        checkpoint=str(checkpoint),
        torch_threads=torch.get_num_threads(),
        comparison=args.comparison,
        results=rows,
        speedup=rates[modes[-1]] / rates[modes[0]],
        speedups={mode: rates[mode] / rates[modes[0]] for mode in modes},
        all_final_policies_equal=len({r["final_policy"] for r in rows}) == 1,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    atomic_text(args.output, json.dumps(report, indent=2, allow_nan=False))
    print(json.dumps(dict(report=str(args.output), speedup=report["speedup"])), flush=True)


if __name__ == "__main__":
    main()
