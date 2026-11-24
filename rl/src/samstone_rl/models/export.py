"""Portable single-file float32 policies; no PyTorch dependency in Godot."""

from __future__ import annotations

import hashlib
import json
import os
import struct
from pathlib import Path
from typing import Any

import numpy as np

from samstone_rl.fast_engine.catalog import StoneCatalog
from samstone_rl.utils.certification import require_certified
from samstone_rl.utils.checkpoints import load_checkpoint
from samstone_rl.utils.provenance import provenance

from .policy import policy_spec, restore_policy

MAGIC = b"SSPOLICY2\n"


def export_policy(
    checkpoint_path: str | Path, output: str | Path, *, allow_unvalidated: bool = False
) -> dict[str, Any]:
    checkpoint = load_checkpoint(checkpoint_path)
    if "veskar_extensions" in policy_spec(checkpoint.get("config", {})):
        raise ValueError("politique Veskar experimentale: export Godot non pris en charge")
    model = restore_policy(checkpoint)
    if not allow_unvalidated:
        require_certified(checkpoint, "boss", provenance())
        specialization = checkpoint.get("specialization", {})
        catalog = StoneCatalog()
        deck = specialization.get("deck", [])
        if (
            specialization.get("god_id") not in catalog.gods
            or not isinstance(deck, list)
            or len(deck) != 8
            or any(not isinstance(stone, str) or stone not in catalog.definitions for stone in deck)
        ):
            raise ValueError("un export de boss exige un dieu et un deck fixe de huit pierres")
    spec = policy_spec(checkpoint.get("config", {}))
    arrays, tensors, offset = [], {}, 0
    for name, tensor in sorted(model.state_dict().items()):
        value = tensor.detach().cpu().numpy().astype("<f4", copy=False)
        if not np.isfinite(value).all():
            raise ValueError(f"poids non finis: {name}")
        raw = value.tobytes(order="C")
        tensors[name] = {"shape": list(value.shape), "offset": offset, "bytes": len(raw)}
        arrays.append(raw)
        offset += len(raw)
    weights = b"".join(arrays)
    specialization = checkpoint.get("specialization", {})
    metadata = {
        "schema": 2,
        "dtype": "float32-le",
        "policy_spec": spec,
        "provenance": provenance(),
        "source_provenance": checkpoint.get("provenance"),
        "validated": not allow_unvalidated,
        "god": specialization.get("god_id", ""),
        "deck": specialization.get("deck", []),
        "tensors": tensors,
        "sha256": hashlib.sha256(weights).hexdigest(),
    }
    header = json.dumps(metadata, sort_keys=True, separators=(",", ":")).encode()
    digest = hashlib.sha256(header + weights).digest()
    target = Path(output).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".tmp")
    with temporary.open("wb") as stream:
        stream.write(MAGIC + struct.pack("<I", len(header)) + digest + header + weights)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(target)
    return metadata
