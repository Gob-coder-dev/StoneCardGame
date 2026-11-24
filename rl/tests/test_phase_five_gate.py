"""The final round is independent and historical guards can veto a promotion."""

from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

from samstone_rl.training.phase_five_gate import evaluate_candidate
from samstone_rl.training.phase_five_protocol import duel_cases, duel_summary


class Arena:
    scenarios = [{"god": "a"}, {"god": "b"}]

    def __init__(self, failed=None):
        self.failed = failed
        self.calls = []

    def opponent(self, path):
        return SimpleNamespace(model=str(path))

    def duels(self, actor, opponent, repetitions, seed, label):
        self.calls.append((seed, label))
        cases = duel_cases(2, repetitions, seed)
        winners = [dict(winner=case["player"]) for case in cases]
        if self.failed == "final" and label == "final_holdout":
            winners = [dict(winner=0) for _ in cases]
        if self.failed == "history" and "history_" in label and label.endswith("candidate"):
            winners = [dict(winner=3 - case["player"]) for case in cases]
        return cases, winners, duel_summary(cases, winners, self.scenarios)

    def champion_reference(self, cases, path, label):
        return duel_summary(cases, [dict(winner=1) for _ in cases], self.scenarios)

    def retention(self, *args):
        self.calls.append((args[3], args[4]))
        if self.failed == "technical":
            raise TimeoutError("Godot unavailable")
        return dict(passed=self.failed != "bots")


def trainer(failed=None):
    settings = yaml.safe_load(
        (Path(__file__).resolve().parents[1] / "configs/ppo_self_play_v2.yaml").read_text(
            encoding="utf-8"
        )
    )["phase5"]
    arena = Arena(failed)
    return SimpleNamespace(
        arena=arena,
        config={"phase5": settings},
        output=Path("/fake"),
        scenarios=arena.scenarios,
        phase5_state={"champions": [{"path": "champion0"}, {"path": "champion1"}]},
        _phase5_history=lambda: [dict(generation=0, path="champion0")],
        phase4_baseline=Path("/phase4"),
        _phase5_seed=lambda domain, attempt, round_index=0: (
            domain * 1_000_000 + attempt * 10000 + round_index * 1000
        ),
    )


def test_successful_last_promotion_includes_fresh_final_duels_and_guards():
    subject = trainer()
    report = evaluate_candidate(subject, dict(path="candidate", attempt=1, final=True))
    assert report["passed"] and report["holdout"]["passed"]
    assert len(report["confirmations"]) == 2
    seeds = {label: seed for seed, label in subject.arena.calls}
    assert seeds["final_holdout"] not in [seeds["confirmation_1"], seeds["confirmation_2"]]
    assert report["guards"]["history"]["0"]["passed"]
    assert subject.arena.calls[0][1] == "retention"
    assert report["holdout"]["guards"]["godot"]["passed"]


@pytest.mark.parametrize("failed", ["final", "history", "bots"])
def test_a_failed_guard_vetoes_a_candidate_before_promotion(failed):
    subject = trainer(failed)
    report = evaluate_candidate(subject, dict(path="candidate", attempt=1, final=True))
    assert not report["passed"]
    assert all(c["passed"] for c in report["confirmations"])
    if failed in ("bots", "history"):
        assert report["confirmations"] == []
        assert not any(label.startswith("confirmation_") for _, label in subject.arena.calls)
    if failed == "bots":
        assert [label for _, label in subject.arena.calls] == ["retention"]


def test_bot_technical_error_propagates_before_duels():
    subject = trainer("technical")
    with pytest.raises(TimeoutError, match="Godot unavailable"):
        evaluate_candidate(subject, dict(path="candidate", attempt=1, final=False))
    assert [label for _, label in subject.arena.calls] == ["retention"]
