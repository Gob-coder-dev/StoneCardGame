"""Prove that only sources outside the fixed-deck RL match changed.

The broad Godot fingerprint remains intact. Old identities are recovered from
verified per-file checkpoint hashes, or from a Git tree with exactly the saved
broad fingerprint. Missing evidence never authorizes a resume.
"""

from __future__ import annotations

import hashlib
import re
import subprocess
from pathlib import Path

RULE_FOLDERS = ("scripts/engine", "scripts/ai", "scripts/data", "scripts/domain")
# These namespaces are not referenced by the fixed-deck simulator/evaluator.
# Anything outside this explicit list (including all engine/AI sources) remains
# protected. LoadoutGenerator generates campaign decks, not RL match decks.
NONCOMBAT_FOLDERS = tuple(
    f"scripts/{layer}/{area}/" for layer in ("data", "domain") for area in ("campaign", "economy")
)
NONCOMBAT_FILES = {"scripts/domain/LoadoutGenerator.gd"}


def source_hash(data: bytes) -> str:
    normalized = data.decode("utf-8-sig").replace("\r\n", "\n")
    return hashlib.sha256(normalized.encode()).hexdigest()


def rules_sources(game_root: Path) -> dict[str, str]:
    return {
        path.relative_to(game_root).as_posix(): source_hash(path.read_bytes())
        for folder in RULE_FOLDERS
        for path in (game_root / folder).rglob("*.gd")
    }


def fingerprint(sources: dict[str, str]) -> str:
    rows = [f"{path}:{value}" for path, value in sorted(sources.items())]
    return hashlib.sha256("\n".join(rows).encode()).hexdigest()


def _git_sources(repository: Path, commit: str, relative_game: str) -> dict[str, str]:
    prefix = relative_game + "/"
    listing = subprocess.run(
        ["git", "ls-tree", "-rz", commit, "--", *[prefix + folder for folder in RULE_FOLDERS]],
        cwd=repository,
        capture_output=True,
        check=True,
        timeout=15,
    ).stdout
    entries = []
    for entry in listing.split(b"\0"):
        if not entry:
            continue
        header, path = entry.split(b"\t", 1)
        name = path.decode("utf-8")
        if name.endswith(".gd") and name.startswith(prefix):
            entries.append((name[len(prefix) :], header.split()[2]))
    objects = subprocess.run(
        ["git", "cat-file", "--batch"],
        cwd=repository,
        input=b"\n".join(blob for _, blob in entries) + b"\n",
        capture_output=True,
        check=True,
        timeout=20,
    ).stdout
    sources, offset = {}, 0
    for name, blob in entries:
        boundary = objects.index(b"\n", offset)
        header = objects[offset:boundary].split()
        if len(header) != 3 or header[0] != blob or header[1] != b"blob":
            raise ValueError("objet Git invalide")
        offset = boundary + 1
        size = int(header[2])
        sources[name] = source_hash(objects[offset : offset + size])
        offset += size + 1
    return sources


def noncombat_change_proof(game_root: Path, saved_checksum: str, saved_sources=None) -> dict | None:
    """Return auditable evidence, only when every changed source is allowed."""
    if not isinstance(saved_checksum, str) or not re.fullmatch("[0-9a-f]{64}", saved_checksum):
        return None
    current = rules_sources(game_root)
    origin = "checkpoint_sources"
    previous = saved_sources
    if previous is not None:
        if (
            not isinstance(previous, dict)
            or not all(
                isinstance(path, str) and isinstance(value, str) for path, value in previous.items()
            )
            or fingerprint(previous) != saved_checksum
        ):
            return None
    else:
        try:
            repository = Path(
                subprocess.run(
                    ["git", "rev-parse", "--show-toplevel"],
                    cwd=game_root,
                    capture_output=True,
                    text=True,
                    check=True,
                    timeout=5,
                ).stdout.strip()
            )
            relative = game_root.resolve().relative_to(repository.resolve()).as_posix()
            commits = subprocess.run(
                ["git", "rev-list", "-64", "HEAD"],
                cwd=repository,
                capture_output=True,
                text=True,
                check=True,
                timeout=5,
            ).stdout.splitlines()
            for commit in commits:
                candidate = _git_sources(repository, commit, relative)
                if fingerprint(candidate) == saved_checksum:
                    previous, origin = candidate, f"git:{commit}"
                    break
        except (OSError, ValueError, subprocess.SubprocessError):
            return None
    if previous is None:
        return None
    changed = sorted(
        path for path in previous.keys() | current.keys() if previous.get(path) != current.get(path)
    )
    if any(
        path not in NONCOMBAT_FILES and not path.startswith(NONCOMBAT_FOLDERS) for path in changed
    ):
        return None
    protected = {
        path: value
        for path, value in current.items()
        if path not in NONCOMBAT_FILES and not path.startswith(NONCOMBAT_FOLDERS)
    }
    return {
        "previous_rules_checksum": saved_checksum,
        "rules_checksum": fingerprint(current),
        "unchanged_combat_checksum": fingerprint(protected),
        "evidence": origin,
        "changed_files": changed,
    }
