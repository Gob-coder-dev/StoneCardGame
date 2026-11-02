from __future__ import annotations

from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Self

from .godot_process import GodotProcess


class GodotProcessPool:
    """Route stable match ids over several independent Godot workers."""

    def __init__(self, workers: int, project_path: str | Path | None = None,
                 godot_path: str | Path | None = None) -> None:
        if workers <= 0:
            raise ValueError("workers doit etre strictement positif")
        self.processes = [GodotProcess(project_path, godot_path) for _ in range(workers)]
        self.routes: dict[str, int] = {}

    def __enter__(self) -> Self:
        self.start()
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def start(self) -> None:
        with ThreadPoolExecutor(max_workers=len(self.processes)) as executor:
            list(executor.map(lambda process: process.start(), self.processes))

    def close(self) -> None:
        with ThreadPoolExecutor(max_workers=len(self.processes)) as executor:
            list(executor.map(lambda process: process.close(), self.processes))
        self.routes.clear()

    def batch_reset(self, matches: list[dict[str, Any]]) -> list[dict[str, Any]]:
        groups: list[list[dict[str, Any]]] = [[] for _ in self.processes]
        seen: set[str] = set()
        for index, match in enumerate(matches):
            match_id = str(match.get("match_id", ""))
            if not match_id or match_id in seen or match_id in self.routes:
                raise ValueError(f"match_id absent ou duplique: {match_id!r}")
            seen.add(match_id)
            groups[index % len(groups)].append(match)
        results = self._parallel(groups, lambda process, group: process.batch_reset(group))
        worker_by_match = {str(match["match_id"]): worker
                           for worker, group in enumerate(groups) for match in group}
        for result in results:
            if result.get("ok"):
                self.routes[str(result["match_id"])] = worker_by_match[str(result["match_id"])]
        return self._ordered(matches, results)

    def batch_step(self, matches: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return self._routed(matches, lambda process, group: process.batch_step(group))

    def batch_get_state(self, matches: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return self._routed(matches, lambda process, group: process.batch_get_state(group))

    def batch_choose_profile_action(self, matches: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return self._routed(matches, lambda process, group: process.batch_choose_profile_action(group))

    def release_matches(self, match_ids: list[str]) -> None:
        groups: list[list[str]] = [[] for _ in self.processes]
        for match_id in match_ids:
            if match_id in self.routes:
                groups[self.routes.pop(match_id)].append(match_id)
        with ThreadPoolExecutor(max_workers=len(self.processes)) as executor:
            futures = [executor.submit(process.release_matches, group)
                       for process, group in zip(self.processes, groups, strict=True) if group]
            for future in futures:
                future.result()

    def _routed(self, matches: list[dict[str, Any]], call: Callable) -> list[dict[str, Any]]:
        groups: list[list[dict[str, Any]]] = [[] for _ in self.processes]
        for match in matches:
            match_id = str(match.get("match_id", ""))
            if match_id not in self.routes:
                raise KeyError(f"match inconnu: {match_id}")
            groups[self.routes[match_id]].append(match)
        return self._ordered(matches, self._parallel(groups, call))

    def _parallel(self, groups: list[list], call: Callable) -> list[dict[str, Any]]:
        with ThreadPoolExecutor(max_workers=len(self.processes)) as executor:
            futures = [executor.submit(call, process, group)
                       for process, group in zip(self.processes, groups, strict=True) if group]
            return [item for future in futures for item in future.result()]

    @staticmethod
    def _ordered(requests: list[dict[str, Any]], results: list[dict[str, Any]]) -> list[dict[str, Any]]:
        by_id = {str(result["match_id"]): result for result in results}
        return [by_id[str(request["match_id"])] for request in requests]
