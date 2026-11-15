"""Measure concatenated versus factorized tactical PPO forward/backward."""

from __future__ import annotations

import argparse
import json
import platform
import statistics
import sys
import time
from pathlib import Path

import torch
from torch.distributions import Categorical

from samstone_rl.models.tactical_actor_critic import TacticalActorCritic
from samstone_rl.utils.device import resolve_torch_device


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="cpu", choices=("cpu", "directml"))
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument("--iterations", type=int, default=5)
    parser.add_argument("--warmup", type=int, default=2)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if min(args.batch_size, args.iterations) <= 0 or args.warmup < 0:
        parser.error("dimensions et repetitions invalides")
    torch.manual_seed(70)
    device = resolve_torch_device(args.device)
    model = TacticalActorCritic(929, 128, 79).to(device)
    observation = torch.randn(args.batch_size, 929, device=device)
    features = torch.randn(args.batch_size, 128, 79, device=device)
    masks = torch.ones(args.batch_size, 128, dtype=torch.bool, device=device)
    selected = torch.zeros(args.batch_size, 128, device=device)
    selected[:, 0] = 1

    def reference():
        state = model.backbone(observation)
        repeated = state.unsqueeze(1).expand(-1, 128, -1)
        logits = model.legacy_actor(state) + model.action_scorer(
            torch.cat((repeated, model.action_encoder(features)), dim=-1)
        ).squeeze(-1)
        return Categorical(logits=logits), model.critic(state).squeeze(-1)

    def factorized():
        return model.distribution_and_value(observation, masks, features)

    timings = {"concatenated": [], "factorized": []}
    for iteration in range(args.warmup + args.iterations):
        # Alternate order to reduce warm-cache and temperature bias.
        methods = [("concatenated", reference), ("factorized", factorized)]
        if iteration % 2:
            methods.reverse()
        for name, method in methods:
            model.zero_grad(set_to_none=True)
            started = time.perf_counter()
            distribution, value = method()
            loss = -(distribution.logits * selected).sum(dim=-1).mean() + value.square().mean()
            loss.backward()
            # DirectML is asynchronous: synchronize before measuring completion.
            model.backbone[0].weight.grad.detach().cpu()
            elapsed = time.perf_counter() - started
            if iteration >= args.warmup:
                timings[name].append(elapsed)
    medians = {name: statistics.median(values) for name, values in timings.items()}
    device_name = platform.processor()
    if device.type == "privateuseone":
        import torch_directml

        device_name = torch_directml.device_name(int(device.index or 0))
    report = {
        "python": sys.version.split()[0],
        "torch": str(torch.__version__),
        "threads": torch.get_num_threads(),
        "device_name": device_name,
        "device": str(device),
        "batch_size": args.batch_size,
        "iterations": args.iterations,
        "seconds": medians,
        "samples": timings,
        "speedup": medians["concatenated"] / medians["factorized"],
        "concatenation_avoided_mib": args.batch_size * 128 * 640 * 4 / 2**20,
    }
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
