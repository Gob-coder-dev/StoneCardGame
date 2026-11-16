"""Persistent Python CPU workers for exact, public-information teacher scores.

Only the immutable catalogue is initialized per worker. Requests contain board
data and the actor's hand, never the opponent's identities or actual RNG state.
"""

import sys
from concurrent.futures import ProcessPoolExecutor
from multiprocessing import get_context

from .catalog import StoneCatalog
from .core import FastSimulator
from .state import FastState

_catalog = None


def _initialize(game_root, checksum):
    global _catalog
    _catalog = StoneCatalog(game_root)
    if _catalog.checksum != checksum:
        raise RuntimeError("catalogue du worker Python different du parent")
    # Spawned CLI children may already have imported torch. Limit their CPU
    # pools without changing the trainer's own DirectML/CPU thread settings.
    if "torch" in sys.modules:
        sys.modules["torch"].set_num_threads(1)


def _score_group(requests):
    simulator = FastSimulator(_catalog)
    results = []
    for board, hand, hidden_count, gods, player, empty, next_id, anticipation in requests:
        state = FastState(_catalog)
        state.board = board
        state.hands = {player: hand, 3 - player: [""] * hidden_count}
        state.gods, state.current_player = gods, player
        state.empty_playable_cells, state.next_instance_id = empty, next_id
        simulator.state = state
        results.append(simulator.profile_action_scores(anticipation))
    return results


class PythonProfilePool:
    def __init__(self, catalog: StoneCatalog, workers: int):
        if workers < 2:
            raise ValueError("le pool requiert au moins deux workers")
        self.workers = workers
        self._executor = ProcessPoolExecutor(
            max_workers=workers,
            mp_context=get_context("spawn"),
            initializer=_initialize,
            initargs=(str(catalog.game_root), catalog.checksum),
        )
        self._closed = False

    def scores(self, simulators, anticipations):
        if self._closed:
            raise RuntimeError("pool du bot ferme")
        if len(simulators) < self.workers * 2:
            return [
                sim.profile_action_scores(flag)
                for sim, flag in zip(simulators, anticipations, strict=True)
            ]
        requests = []
        for simulator, flag in zip(simulators, anticipations, strict=True):
            state = simulator._require_state()
            player = state.current_player
            requests.append(
                (
                    state.board,
                    state.hands[player],
                    len(state.hands[3 - player]),
                    state.gods,
                    player,
                    state.empty_playable_cells,
                    state.next_instance_id,
                    flag,
                )
            )
        groups = [requests[i :: self.workers] for i in range(self.workers)]
        batches = list(self._executor.map(_score_group, groups))
        result = [None] * len(requests)
        for worker, batch in enumerate(batches):
            result[worker :: self.workers] = batch
        return result

    def close(self):
        if not self._closed:
            self._executor.shutdown(wait=True, cancel_futures=True)
            self._closed = True
