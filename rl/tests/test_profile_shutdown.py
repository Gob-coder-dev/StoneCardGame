from threading import Event

import pytest

from samstone_rl.fast_engine.profile_pool import _shutdown_executor


class FakeWorker:
    def __init__(self, released):
        self.released = released
        self.terminated = False

    def is_alive(self):
        return not self.released.is_set()

    def terminate(self):
        self.terminated = True
        self.released.set()

    def join(self, timeout):
        self.released.wait(timeout)


class FakeExecutor:
    def __init__(self, stuck=False):
        self.released = Event()
        self.worker = FakeWorker(self.released)
        self._processes = {1: self.worker}
        self.stuck = stuck

    def shutdown(self, wait, cancel_futures):
        assert wait and cancel_futures
        if not self.stuck:
            self.released.set()
        assert self.released.wait(3)


@pytest.mark.parametrize("stuck", [False, True])
def test_shutdown_bounds_idle_worker_finalization(stuck):
    executor = FakeExecutor(stuck)
    _shutdown_executor(executor, grace_seconds=0.02)
    assert executor.worker.terminated == stuck
    assert executor.released.is_set()
