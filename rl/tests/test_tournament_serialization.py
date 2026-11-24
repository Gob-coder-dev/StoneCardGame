"""Real environment payloads must survive durable JSON storage and resume."""

import sqlite3

import numpy as np
import pytest

from samstone_rl.evaluation.tournament import run_tournament


def test_numpy_results_are_saved_and_resume_has_identical_types(tmp_path):
    calls = []

    def play(env, case):
        calls.append(case["seed"])
        return dict(
            winner=np.int64(1),
            action_mask=np.array([True, False]),
            action_features=np.array([[1.25, 0]], dtype=np.float32),
            episode=dict(won=np.bool_(True), margin=np.float64(2)),
        )

    cases = [dict(seed=i) for i in range(3)]
    first = run_tournament(cases, [object()], play, tmp_path, {"policy": "same"})
    assert calls == [0, 1, 2]
    calls.clear()
    second = run_tournament(cases, [object()], play, tmp_path, {"policy": "same"})
    assert calls == [] and first == second
    assert first[0]["action_mask"] == [True, False]
    assert first[0]["action_features"] == [[1.25, 0]]


def test_invalid_array_does_not_corrupt_committed_results(tmp_path):
    def play(env, case):
        if case["seed"] == 1:
            return {"array": np.array([float("nan")])}
        return {"winner": 1}

    with pytest.raises(ValueError):
        run_tournament([dict(seed=0), dict(seed=1)], [object()], play, tmp_path, {})
    with sqlite3.connect(next(tmp_path.glob("*.sqlite3"))) as db:
        assert db.execute("SELECT COUNT(*) FROM results").fetchone()[0] == 1


def test_progress_interrupt_resumes_committed_cases_and_new_policy_is_separate(tmp_path):
    cases = [dict(seed=i) for i in range(4)]
    played = []
    progress = []

    def play(env, case):
        played.append(case["seed"])
        return {"winner": 1}

    def interrupt(completed, total):
        progress.append((completed, total))
        if completed == 2:
            raise InterruptedError()

    with pytest.raises(InterruptedError):
        run_tournament(cases, [object()], play, tmp_path, {"policy": "a"}, interrupt)
    assert played == [0, 1]
    assert progress == [(0, 4), (1, 4), (2, 4)]
    played.clear()
    progress.clear()
    run_tournament(
        cases, [object()], play, tmp_path, {"policy": "a"}, lambda *p: progress.append(p)
    )
    assert played == [2, 3]
    assert progress == [(2, 4), (3, 4), (4, 4)]
    played.clear()
    run_tournament(cases, [object()], play, tmp_path, {"policy": "b"})
    assert played == [0, 1, 2, 3]
