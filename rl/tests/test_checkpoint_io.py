"""Shared persistence retains the Windows reader-lock fix after experiment cleanup."""

from pathlib import Path

import pytest

from samstone_rl.utils import checkpoints


def test_atomic_text_retries_windows_lock_without_exposing_partial_data(tmp_path, monkeypatch):
    path = tmp_path / "manifest.json"
    checkpoints.atomic_text(path, "old")
    replace = Path.replace
    attempts = 0
    sleeps = []

    def retry(temporary, target):
        nonlocal attempts
        attempts += 1
        assert path.read_text() == "old"
        if attempts < 3:
            error = PermissionError("Windows reader")
            error.winerror = 5
            raise error
        return replace(temporary, target)

    monkeypatch.setattr(Path, "replace", retry)
    monkeypatch.setattr(checkpoints.time, "sleep", sleeps.append)
    checkpoints.atomic_text(path, "new")
    assert path.read_text() == "new" and attempts == 3 and len(sleeps) == 2
    assert not list(tmp_path.glob("*.tmp"))


def test_persistent_lock_is_bounded_and_previous_file_preserved(tmp_path, monkeypatch):
    path = tmp_path / "manifest.json"
    checkpoints.atomic_text(path, "old")
    sleeps = []

    def locked(*args):
        error = PermissionError("Windows reader")
        error.winerror = 32
        raise error

    monkeypatch.setattr(Path, "replace", locked)
    monkeypatch.setattr(checkpoints.time, "sleep", sleeps.append)
    with pytest.raises(PermissionError):
        checkpoints.atomic_text(path, "new")
    assert path.read_text() == "old" and len(sleeps) == 40 and sum(sleeps) < 4
    assert not list(tmp_path.glob("*.tmp"))
