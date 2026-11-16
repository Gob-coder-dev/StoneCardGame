"""Batched authoritative teacher; only public positions cross the bridge."""

import json
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor

from .godot_process import GodotProcess


class ProfileOracle:
    def __init__(self, workers=10, godot_path=None, project_path=None):
        if workers <= 0:
            raise ValueError("profile_workers doit etre positif")
        self.processes = [
            GodotProcess(project_path, godot_path, command_timeout=120) for _ in range(workers)
        ]
        self.executor = ThreadPoolExecutor(max_workers=workers)
        self._closed = False
        self._cache = OrderedDict()

    def scores(self, requests):
        # The evaluator is deterministic given this public snapshot. Reuse
        # opening positions across slots without sharing any hidden hand data.
        keys = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in requests]
        missing = dict(
            (key, request)
            for key, request in zip(keys, requests, strict=True)
            if key not in self._cache
        )
        computed = self._scores(list(missing.values())) if missing else []
        available = {**self._cache, **dict(zip(missing, computed, strict=True))}
        result = [available[key] for key in keys]
        self._cache.update(zip(missing, computed, strict=True))
        while len(self._cache) > 2048:
            self._cache.popitem(last=False)
        return result

    def _scores(self, requests):
        groups = [requests[index :: len(self.processes)] for index in range(len(self.processes))]

        def call(item):
            process, group = item
            if not group:
                return []
            process.start()
            return process.send_command("profile_scores", requests=group)["results"]

        batches = list(self.executor.map(call, zip(self.processes, groups, strict=True)))
        result = [None] * len(requests)
        for worker, batch in enumerate(batches):
            for index, scores in enumerate(batch):
                result[worker + index * len(self.processes)] = {
                    int(k): float(v) for k, v in scores.items()
                }
        return result

    def close(self):
        if self._closed:
            return
        try:
            list(self.executor.map(lambda process: process.close(), self.processes))
        finally:
            self.executor.shutdown(wait=True)
            self._closed = True
            self._cache.clear()
