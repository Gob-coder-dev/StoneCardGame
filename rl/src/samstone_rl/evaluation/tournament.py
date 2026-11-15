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
from pathlib import Path
from typing import Any


def run_tournament(
    cases: Sequence[dict[str, Any]],
    environments: Sequence[Any],
    play: Callable[[Any, dict[str, Any]], dict[str, Any]],
    output: Path,
    identity: dict[str, Any],
) -> list[dict[str, Any]]:
    serialized = json.dumps(
        {"identity": identity, "cases": cases}, sort_keys=True, separators=(",", ":")
    )
    digest = hashlib.sha256(serialized.encode()).hexdigest()
    output.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(output / f"{digest}.sqlite3", check_same_thread=False)
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
                payload = json.dumps(info, allow_nan=False)
                with lock:
                    connection.execute("INSERT INTO results VALUES (?, ?)", (index, payload))
                    connection.commit()
                    completed[index] = info
                    if len(completed) % 100 == 0:
                        print(f"Validation: {len(completed)}/{len(cases)} matchs", flush=True)
        except BaseException:
            stopped.set()
            raise

    try:
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
