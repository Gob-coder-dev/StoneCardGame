"""Verified checkpoint I/O with an interrupted-write recovery journal.

The journal is committed before replacing the model and removed after the
sidecar. A loader repairs only an interrupted transaction whose exact bytes
match its journal; unrelated corruption is always rejected.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any

import torch


def file_checksum(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def policy_checksum(model: torch.nn.Module) -> str:
    """Stable weight identity, independent of torch.save archive metadata."""
    return state_checksum(model.state_dict())


def state_checksum(state: dict[str, torch.Tensor]) -> str:
    digest = hashlib.sha256()
    for name, tensor in sorted(state.items()):
        value = tensor.detach().cpu().contiguous()
        digest.update(f"{name}:{value.dtype}:{tuple(value.shape)}:".encode())
        digest.update(value.numpy().tobytes())
    return digest.hexdigest()


def atomic_text(path: Path, text: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(text)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def save_checkpoint(path: str | Path, payload: dict[str, Any]) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".tmp")
    with temporary.open("wb") as stream:
        torch.save(payload, stream)
        stream.flush()
        os.fsync(stream.fileno())
    checksum = file_checksum(temporary)
    journal = target.with_suffix(target.suffix + ".pending.json")
    atomic_text(journal, json.dumps({"target": target.name, "sha256": checksum}))
    temporary.replace(target)
    atomic_text(target.with_suffix(target.suffix + ".sha256"), f"{checksum}  {target.name}\n")
    journal.unlink()


def load_checkpoint(path: str | Path) -> dict[str, Any]:
    target = Path(path).resolve()
    sidecar = target.with_suffix(target.suffix + ".sha256")
    journal = target.with_suffix(target.suffix + ".pending.json")
    actual = file_checksum(target)
    if journal.is_file():
        pending = json.loads(journal.read_text(encoding="utf-8"))
        if pending.get("target") == target.name and pending.get("sha256") == actual:
            atomic_text(sidecar, f"{actual}  {target.name}\n")
            journal.unlink()
    if sidecar.is_file():
        fields = sidecar.read_text(encoding="ascii").split()
        if not fields or fields[0] != actual:
            raise ValueError(f"checksum invalide pour {target}")
    return torch.load(target, map_location="cpu", weights_only=False)
