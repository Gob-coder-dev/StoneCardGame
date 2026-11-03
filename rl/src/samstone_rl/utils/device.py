from __future__ import annotations

import torch


def resolve_torch_device(name: str | None) -> torch.device:
    """Resolve CPU/CUDA and the optional Windows DirectML backend lazily."""
    normalized = str(name or "cpu").strip().lower()
    if normalized != "directml":
        return torch.device(normalized)
    try:
        import torch_directml
    except ImportError as exc:  # pragma: no cover - depends on optional package
        raise RuntimeError(
            "device=directml requiert l'extra 'directml' (pip install -e .[directml])"
        ) from exc
    return torch_directml.device()
