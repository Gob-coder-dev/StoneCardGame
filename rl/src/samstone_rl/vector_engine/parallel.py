"""Optional persistent CPU workers with private scratch buffers."""

from concurrent.futures import ThreadPoolExecutor
from dataclasses import astuple

import numpy as np

from .tactical import VectorTacticalEvaluator, VectorTacticalStats
from .workspace import VectorWorkspace


class ParallelTacticalEvaluator(VectorTacticalEvaluator):
    def __init__(self, catalog, *, workers: int, vector_effects: bool = True):
        if workers < 2:
            raise ValueError("parallel evaluator requires at least two workers")
        super().__init__(catalog, vector_effects)
        self._children = []
        for _ in range(workers):
            child = object.__new__(VectorTacticalEvaluator)
            child.catalog, child.effects = self.catalog, self.effects
            child.vector_effects = self.vector_effects
            child.workspace = VectorWorkspace()
            child._totals = np.zeros(7, dtype=np.float64)
            child.last_stats = VectorTacticalStats(0, 0, 0, 0, 0.0, 0.0, 0.0)
            self._children.append(child)
        self._executor = ThreadPoolExecutor(max_workers=workers)
        self._closed = False

    def evaluate(self, simulators, observers, action_masks):
        if self._closed:
            raise RuntimeError("tactical evaluator closed")
        batch = len(simulators)
        if len(observers) != batch or action_masks.shape != (batch, 128):
            raise ValueError("lot tactique incompatible")
        # Small batches do not amortize thread dispatch and gather costs.
        if batch < 128:
            return super().evaluate(simulators, observers, action_masks)
        chunks = [ix for ix in np.array_split(np.arange(batch), len(self._children)) if len(ix)]

        def work(pair):
            child, ix = pair
            return child.evaluate(
                [simulators[i] for i in ix], [observers[i] for i in ix], action_masks[ix]
            )

        pairs = list(zip(self._children[: len(chunks)], chunks, strict=True))
        outputs = list(self._executor.map(work, pairs))
        result = self.workspace.ensure(batch).view("scores", batch)
        offset = 0
        totals = np.zeros(7, dtype=np.float64)
        for (child, ix), values in zip(pairs, outputs, strict=True):
            result[offset : offset + len(ix)] = values
            offset += len(ix)
            totals += astuple(child.last_stats)
        self._totals += totals
        self.last_stats = VectorTacticalStats(*(int(x) for x in totals[:4]), *totals[4:])
        return result

    def metrics(self, *, reset=False):
        result = super().metrics(reset=reset)
        result["workspace_mb"] += (
            sum(child.workspace.allocated_bytes for child in self._children) / 2**20
        )
        result["workers"] = float(len(self._children))
        return result

    def close(self):
        if not self._closed:
            self._executor.shutdown(wait=True)
            self._closed = True
