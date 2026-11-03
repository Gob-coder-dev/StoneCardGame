#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from copy import deepcopy
from pathlib import Path
from typing import Any

import torch
import yaml

from samstone_rl.training.ppo_cleanrl import PPOTrainer


def _latest_metrics(directory: Path) -> dict[str, Any]:
    events = [json.loads(line) for line in (directory / "metrics.jsonl").read_text(
        encoding="utf-8").splitlines() if line]
    training = [event for event in events if event.get("stream") == "training"]
    evaluations = [event for event in events if event.get("stream") == "evaluation"]
    return {
        "training": training[-1] if training else None,
        "evaluation": evaluations[-1] if evaluations else None,
    }


def _variant(base: dict[str, Any], output: Path, enabled: bool,
             coefficient: float, total_timesteps: int) -> dict[str, Any]:
    config = deepcopy(base)
    config["output_dir"] = str(output.resolve())
    config["ppo"]["total_timesteps"] = int(total_timesteps)
    config["curriculum"]["bootstrap_evaluation"] = {"enabled": False}
    config["auxiliary"] = {
        "enabled": bool(enabled),
        "target": "final_board_margin",
        "coefficient": float(coefficient),
        "loss": "huber",
    }
    return config


def _prepare_variant(config: dict[str, Any], directory: Path,
                     source_checkpoint: Path) -> tuple[Path, Path]:
    """Create a variant once, then resume it safely after an interruption."""
    directory.mkdir(parents=True, exist_ok=True)
    config_path = directory / "config.yaml"
    if config_path.exists():
        existing = yaml.safe_load(config_path.read_text(encoding="utf-8"))
        if existing != config:
            raise ValueError(
                f"le run A/B existant utilise une autre configuration: {directory}")
    else:
        config_path.write_text(
            yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
    latest = directory / "latest.pt"
    return config_path, latest if latest.exists() else source_checkpoint


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare PPO seul et PPO + prediction de marge depuis le meme checkpoint.")
    parser.add_argument("--config", type=Path,
                        default=Path("configs/ppo_phase4_vectorized.yaml"))
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--updates", type=int, default=500)
    parser.add_argument("--coefficient", type=float, default=0.02)
    args = parser.parse_args()
    if args.updates <= 0 or args.coefficient < 0.0:
        parser.error("updates doit etre positif et coefficient positif")

    base = yaml.safe_load(args.config.read_text(encoding="utf-8"))
    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    batch_size = (int(base["ppo"]["rollout_steps"])
                  * int(base["ppo"].get("num_envs", 1)))
    start_step = int(checkpoint.get("global_step", 0))
    total = start_step + args.updates * batch_size
    root = args.output.resolve()
    variants = (("control", False), ("auxiliary", True))
    for name, enabled in variants:
        directory = root / name
        config = _variant(base, directory, enabled, args.coefficient, total)
        config_path, resume = _prepare_variant(
            config, directory, args.checkpoint)
        trainer = PPOTrainer(config_path)
        trainer.load_checkpoint(resume)
        trainer.train()

    report = {
        "schema_version": 1,
        "checkpoint": str(args.checkpoint.resolve()),
        "updates": args.updates,
        "coefficient": args.coefficient,
        "control": _latest_metrics(root / "control"),
        "auxiliary": _latest_metrics(root / "auxiliary"),
    }
    report_path = root / "comparison.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

