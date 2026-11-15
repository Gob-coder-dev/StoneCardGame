"""Content and source identities carried by checkpoints and evaluations."""

from __future__ import annotations

import hashlib
from pathlib import Path

from samstone_rl.fast_engine.catalog import StoneCatalog


def source_checksum(root: Path, folders: tuple[str, ...], suffix: str) -> str:
    rows = []
    for path in sorted(
        (p for folder in folders for p in (root / folder).rglob(f"*{suffix}")),
        key=lambda p: p.relative_to(root).as_posix(),
    ):
        # Normalize checkout line endings so Windows and CI share an identity.
        source = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
        rows.append(
            f"{path.relative_to(root).as_posix()}:{hashlib.sha256(source.encode()).hexdigest()}"
        )
    return hashlib.sha256("\n".join(rows).encode()).hexdigest()


def game_rules_checksum(game_root: Path | None = None) -> str:
    root = game_root or Path(__file__).resolve().parents[4] / "game"
    return source_checksum(
        root, ("scripts/engine", "scripts/ai", "scripts/data", "scripts/domain"), ".gd"
    )


def provenance(catalog: StoneCatalog | None = None) -> dict[str, str | int]:
    catalog = catalog or StoneCatalog()
    return {
        "schema": 2,
        "content": catalog.checksum,
        "game_rules": game_rules_checksum(catalog.game_root),
        "python_source": source_checksum(Path(__file__).resolve().parents[1], (".",), ".py"),
        "feature_schema": 2,
    }
