"""OS-owned exclusive run lease; a process crash releases it automatically."""

from __future__ import annotations

import os
from pathlib import Path


class RunLock:
    def __init__(self, directory: Path) -> None:
        self.stream = (directory / ".run.lock").open("a+b")
        if self.stream.tell() == 0:
            self.stream.write(b"0")
            self.stream.flush()
        self.stream.seek(0)
        try:
            if os.name == "nt":
                import msvcrt

                msvcrt.locking(self.stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(self.stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            self.stream.close()
            raise RuntimeError(f"run deja utilise par un autre processus: {directory}") from exc

    def close(self) -> None:
        if self.stream.closed:
            return
        if os.name == "nt":
            import msvcrt

            self.stream.seek(0)
            msvcrt.locking(self.stream.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl

            fcntl.flock(self.stream, fcntl.LOCK_UN)
        self.stream.close()
