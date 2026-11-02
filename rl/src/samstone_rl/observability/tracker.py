from __future__ import annotations

import hashlib
import json
import platform
import subprocess
import sys
from collections.abc import Mapping
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Self

import gymnasium
import numpy as np
import torch
from torch.utils.tensorboard import SummaryWriter


def utc_now() -> str:
    return datetime.now(UTC).isoformat()


def json_value(value: Any) -> Any:
    if isinstance(value, Mapping):
        return {str(key): json_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_value(item) for item in value]
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, torch.Tensor):
        return value.detach().cpu().tolist()
    return value


def flatten_metrics(metrics: Mapping[str, Any], prefix: str = "") -> dict[str, float]:
    flattened: dict[str, float] = {}
    for key, value in metrics.items():
        name = f"{prefix}/{key}" if prefix else str(key)
        if isinstance(value, Mapping):
            flattened.update(flatten_metrics(value, name))
        elif isinstance(value, (bool, int, float, np.number)):
            flattened[name] = float(value)
    return flattened


def build_run_manifest(run_type: str, config: Mapping[str, Any], config_path: str | Path,
                       seed: int, checksums: Mapping[str, str] | None = None,
                       extra: Mapping[str, Any] | None = None) -> dict[str, Any]:
    path = Path(config_path).resolve()
    config_bytes = path.read_bytes()
    git = _git_metadata(path.parent)
    return {
        "schema_version": 1,
        "run_type": run_type,
        "created_at": utc_now(),
        "seed": int(seed),
        "config_path": str(path),
        "config_sha256": hashlib.sha256(config_bytes).hexdigest(),
        "config": json_value(config),
        "checksums": dict(checksums or {}),
        "software": {
            "python": sys.version.split()[0],
            "torch": torch.__version__,
            "numpy": np.__version__,
            "gymnasium": gymnasium.__version__,
            "platform": platform.platform(),
        },
        "git": git,
        "extra": json_value(extra or {}),
    }


class RunTracker:
    """Append-only JSONL plus TensorBoard, with atomic manifest updates."""

    def __init__(self, output_directory: str | Path, run_type: str,
                 tensorboard: bool = True) -> None:
        self.output = Path(output_directory).resolve()
        self.output.mkdir(parents=True, exist_ok=True)
        self.run_type = run_type
        self.metrics_path = self.output / "metrics.jsonl"
        self.alerts_path = self.output / "alerts.jsonl"
        self.manifest_path = self.output / "run_manifest.json"
        self._metrics = self.metrics_path.open("a", encoding="utf-8", buffering=1)
        self._alerts = self.alerts_path.open("a", encoding="utf-8", buffering=1)
        self.tensorboard = (SummaryWriter(
            str(self.output / "tensorboard"), max_queue=1000, flush_secs=10)
            if tensorboard else None)

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def write_manifest(self, manifest: Mapping[str, Any]) -> None:
        payload = json_value(manifest)
        temporary = self.manifest_path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
        temporary.replace(self.manifest_path)

    def initialize_manifest(self, manifest: Mapping[str, Any]) -> None:
        incoming = json_value(manifest)
        if not self.manifest_path.is_file():
            incoming["sessions"] = [{"opened_at": utc_now()}]
            self.write_manifest(incoming)
            return
        current = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        for key in ("run_type", "config_sha256"):
            if current.get(key) != incoming.get(key):
                raise ValueError(f"le dossier de run contient un autre {key}")
        current_checksums = current.get("checksums", {})
        for key, value in incoming.get("checksums", {}).items():
            if key in current_checksums and current_checksums[key] != value:
                raise ValueError(f"le dossier de run contient un autre checksum {key}")
        current.setdefault("sessions", []).append({"opened_at": utc_now()})
        self.write_manifest(current)

    def update_manifest(self, **updates: Any) -> None:
        current = (json.loads(self.manifest_path.read_text(encoding="utf-8"))
                   if self.manifest_path.is_file() else {})
        clean_updates = json_value(updates)
        for key, value in clean_updates.get("checksums", {}).items():
            existing = current.get("checksums", {}).get(key)
            if existing is not None and existing != value:
                raise ValueError(f"le dossier de run contient un autre checksum {key}")
        _deep_update(current, clean_updates)
        self.write_manifest(current)

    def log(self, stream: str, step: int, metrics: Mapping[str, Any],
            context: Mapping[str, Any] | None = None) -> dict[str, Any]:
        event = {
            "schema_version": 1,
            "timestamp": utc_now(),
            "run_type": self.run_type,
            "stream": stream,
            "step": int(step),
            "metrics": json_value(metrics),
            "context": json_value(context or {}),
        }
        self._metrics.write(json.dumps(event, ensure_ascii=False, allow_nan=False) + "\n")
        if self.tensorboard is not None:
            for name, value in flatten_metrics(metrics).items():
                if np.isfinite(value):
                    self.tensorboard.add_scalar(f"{stream}/{name}", value, int(step))
        return event

    def log_alert(self, alert: Mapping[str, Any]) -> None:
        payload = {"schema_version": 1, "timestamp": utc_now(), **json_value(alert)}
        self._alerts.write(json.dumps(payload, ensure_ascii=False, allow_nan=False) + "\n")
        if self.tensorboard is not None:
            step = int(payload.get("step", 0))
            self.tensorboard.add_text(
                f"alerts/{payload.get('severity', 'warning')}/{payload.get('code', 'unknown')}",
                str(payload.get("message", "")), step)

    def close(self) -> None:
        if not self._metrics.closed:
            self._metrics.close()
        if not self._alerts.closed:
            self._alerts.close()
        if self.tensorboard is not None:
            self.tensorboard.close()
            self.tensorboard = None


def _git_metadata(start: Path) -> dict[str, Any]:
    def run(*args: str) -> str:
        try:
            return subprocess.run(
                ["git", *args], cwd=start, capture_output=True, text=True,
                timeout=5, check=True).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return ""

    status = run("status", "--porcelain")
    return {
        "commit": run("rev-parse", "HEAD"),
        "branch": run("branch", "--show-current"),
        "dirty": bool(status),
    }


def _deep_update(target: dict[str, Any], updates: Mapping[str, Any]) -> None:
    for key, value in updates.items():
        if isinstance(value, Mapping) and isinstance(target.get(key), dict):
            _deep_update(target[key], value)
        else:
            target[key] = value
