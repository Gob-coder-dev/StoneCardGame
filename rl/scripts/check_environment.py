"""Check a training installation without creating or modifying any run."""

from __future__ import annotations

import argparse
import importlib.metadata
import json
import subprocess
import sys
from pathlib import Path

import torch
import yaml
from packaging.requirements import Requirement

from samstone_rl.bridge import GodotProcess
from samstone_rl.fast_engine import StoneCatalog
from samstone_rl.utils.device import resolve_torch_device
from samstone_rl.utils.optim import DirectMLAdam
from samstone_rl.utils.provenance import game_rules_checksum


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path("configs/ppo_phase4_vectorized.yaml"))
    parser.add_argument("--skip-godot", action="store_true")
    parser.add_argument("--strict-lock", action="store_true")
    args = parser.parse_args()
    config = yaml.safe_load(args.config.read_text(encoding="utf-8"))
    errors = []
    if sys.version_info[:2] != (3, 11):
        errors.append("Python 3.11 requis")
    dependencies = subprocess.run(
        [sys.executable, "-m", "pip", "check"], capture_output=True, text=True
    )
    if dependencies.returncode:
        errors.append(dependencies.stdout.strip() or dependencies.stderr.strip())
    flavor = "directml" if config.get("device") == "directml" else "cpu"
    if args.strict_lock:
        lock = Path(__file__).resolve().parents[1] / f"requirements-{flavor}.lock"
        for raw in lock.read_text(encoding="utf-8").splitlines():
            if not raw or raw.startswith(("#", "--")):
                continue
            requirement = Requirement(raw)
            try:
                installed = importlib.metadata.version(requirement.name)
                if installed not in requirement.specifier:
                    errors.append(f"version verrouillee non respectee: {requirement}")
            except importlib.metadata.PackageNotFoundError:
                errors.append(f"dependance absente: {requirement}")
    catalog = StoneCatalog()
    device = resolve_torch_device(config.get("device"))
    # A real gradient/update also catches unsupported accelerator kernels.
    parameter = torch.nn.Parameter(torch.tensor([1.0, 2.0], device=device))
    optimizer = (DirectMLAdam if device.type == "privateuseone" else torch.optim.Adam)([parameter])
    parameter.square().sum().backward()
    optimizer.step()
    if not torch.isfinite(parameter).all():
        errors.append("mise a jour du peripherique non finie")
    oracle = None
    if not args.skip_godot:
        with GodotProcess(godot_path=config["environment"].get("godot_path")) as bridge:
            oracle = bridge.engine_manifest()
            if oracle["catalogue_checksum"] != catalog.checksum:
                errors.append("catalogues Python/Godot differents")
            if oracle["rules_checksum"] != game_rules_checksum():
                errors.append("identites des regles Python/Godot differentes")
            if oracle.get("action_feature_schema") != 2:
                errors.append("schema tactique incompatible")
    print(
        json.dumps(
            {
                "ok": not errors,
                "python": sys.version.split()[0],
                "device": str(device),
                "variants": len(catalog.definitions),
                "oracle": oracle,
                "errors": errors,
            },
            indent=2,
        )
    )
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
