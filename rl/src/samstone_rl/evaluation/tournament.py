"""Durable, parallel match execution shared by held-out validations.

Each case is seeded independently and committed before the next case starts.
The ledger identity includes policy, rules, content and the full schedule.
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import threading
from collections.abc import Callable, Sequence
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path
from typing import Any

import numpy as np


def _json_default(value):
    """Persist environment masks/features and NumPy scalar diagnostics."""
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def tournament_path(cases, output: Path, identity: dict) -> Path:
    serialized = json.dumps(
        {"identity": identity, "cases": cases}, sort_keys=True, separators=(",", ":")
    )
    return output / f"{hashlib.sha256(serialized.encode()).hexdigest()}.sqlite3"


def read_completed_tournament(cases, output: Path, identity: dict) -> tuple[Path, list[dict]]:
    """Read committed winners without loading large masks and feature arrays."""
    path = tournament_path(cases, output, identity).resolve()
    with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)) as connection:
        rows = connection.execute(
            "SELECT case_id, json_extract(info, '$.winner') FROM results ORDER BY case_id"
        ).fetchall()
    if [row[0] for row in rows] != list(range(len(cases))):
        raise ValueError("tournoi enregistre incomplet ou planning incompatible")
    return path, [{"winner": row[1]} for row in rows]


def run_tournament(
    cases: Sequence[dict[str, Any]],
    environments: Sequence[Any],
    play: Callable[[Any, dict[str, Any]], dict[str, Any]],
    output: Path,
    identity: dict[str, Any],
    on_progress: Callable[[int, int], None] | None = None,
) -> list[dict[str, Any]]:
    output.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(tournament_path(cases, output, identity), check_same_thread=False)
    connection.execute("PRAGMA journal_mode=WAL")
    connection.execute("PRAGMA synchronous=FULL")
    connection.execute(
        "CREATE TABLE IF NOT EXISTS results (case_id INTEGER PRIMARY KEY, info TEXT NOT NULL)"
    )
    completed = {
        int(row[0]): json.loads(row[1])
        for row in connection.execute("SELECT case_id, info FROM results")
    }
    pending = [index for index in range(len(cases)) if index not in completed]
    lock = threading.Lock()
    stopped = threading.Event()

    def worker(environment, indices):
        try:
            for index in indices:
                if stopped.is_set():
                    return
                info = play(environment, cases[index])
                payload = json.dumps(info, default=_json_default, allow_nan=False)
                # Fresh and resumed cases must expose the same JSON-compatible
                # types; otherwise consumers would depend on interruption timing.
                info = json.loads(payload)
                with lock:
                    connection.execute("INSERT INTO results VALUES (?, ?)", (index, payload))
                    connection.commit()
                    completed[index] = info
                    if on_progress is not None:
                        on_progress(len(completed), len(cases))
                    if len(completed) % 100 == 0:
                        print(f"Validation: {len(completed)}/{len(cases)} matchs", flush=True)
        except BaseException:
            stopped.set()
            raise

    try:
        if on_progress is not None:
            on_progress(len(completed), len(cases))
        with ThreadPoolExecutor(max_workers=len(environments)) as executor:
            futures = [
                executor.submit(worker, env, pending[i :: len(environments)])
                for i, env in enumerate(environments)
            ]
            for future in futures:
                future.result()
        return [completed[index] for index in range(len(cases))]
    finally:
        connection.close()
