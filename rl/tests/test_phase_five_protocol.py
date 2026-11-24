"""Fair pairings, draw-aware confidence and bounded promotion requirements."""

from collections import Counter
from copy import deepcopy
from pathlib import Path

import numpy as np
import pytest
import yaml

from samstone_rl.training.phase_five_protocol import (
    duel_cases,
    duel_summary,
    promotion_judgement,
    regression_judgement,
    score_lower_bound,
    validate_settings,
)


def settings():
    return yaml.safe_load(
        (Path(__file__).resolve().parents[1] / "configs/ppo_self_play_v2.yaml").read_text(
            encoding="utf-8"
        )
    )["phase5"]


def test_schedule_covers_all_gods_roles_and_first_players_with_paired_seeds():
    cases = duel_cases(6, 3, 1000)
    assert len(cases) == 36 * 4 * 3
    by_matchup = Counter(
        (
            c["left"] if c["player"] == 1 else c["right"],
            c["right"] if c["player"] == 1 else c["left"],
            c["player"],
            c["first"],
        )
        for c in cases
    )
    assert len(by_matchup) == 36 * 4
    assert set(by_matchup.values()) == {3}
    for first, second in zip(cases[::2], cases[1::2], strict=True):
        assert first["player"] == 1 and second["player"] == 2
        assert {k: v for k, v in first.items() if k != "player"} == {
            k: v for k, v in second.items() if k != "player"
        }


def test_intrinsic_god_advantages_do_not_create_a_false_global_improvement():
    scenarios = [{"god": "strong"}, {"god": "weak"}]
    cases = duel_cases(2, 10, 1000)
    # Physical winner is entirely determined by the gods, not the policies.
    results = [{"winner": 1 if c["left"] <= c["right"] else 2} for c in cases]
    summary = duel_summary(cases, results, scenarios)
    assert summary["score"] == 0.5
    assert summary["by_god"]["weak"]["score"] < 0.5
    assert regression_judgement(summary, summary, 0.05)["passed"]


def test_draws_contribute_to_score_and_bootstrap_uses_whole_pairs():
    paired = [0.5] * 500 + [1.0] * 100
    summary = dict(score=sum(paired) / len(paired), paired_scores=paired, games=1200)
    result = promotion_judgement(summary, settings()["promotion"], 91)
    assert result["passed"] and result["score_lower"] > 0.5
    assert result["confidence_method"] == "paired_percentile_bootstrap"
    assert not promotion_judgement(
        dict(score=0.5, paired_scores=[0.5] * 100, games=200), settings()["promotion"], 91
    )["passed"]
    assert score_lower_bound(paired, 0.95, 2000, 42) == score_lower_bound(paired, 0.95, 2000, 42)


def test_score_bootstrap_preserves_external_numpy_rng():
    np.random.seed(42)
    state = np.random.get_state()
    score_lower_bound([0, 0.5, 1] * 100, 0.95, 100, 73)
    observed = np.random.random()
    np.random.set_state(state)
    assert observed == np.random.random()


def test_god_guard_is_relative_to_the_reference_in_the_same_matchups():
    reference = {"by_god": {"weak": {"score": 0.25}, "strong": {"score": 0.85}}}
    candidate = deepcopy(reference)
    candidate["by_god"]["weak"]["score"] = 0.28
    assert regression_judgement(candidate, reference, 0.05)["passed"]
    candidate["by_god"]["weak"]["score"] = 0.19
    assert regression_judgement(candidate, reference, 0.05)["failed_gods"] == ["weak"]


def test_incomplete_pair_cannot_be_used_for_promotion():
    cases = duel_cases(2, 1, 1)
    with pytest.raises(ValueError, match="incomplets"):
        duel_summary(cases[:-1], [{"winner": 0} for _ in cases[:-1]], [{"god": "a"}, {"god": "b"}])


@pytest.mark.parametrize(
    "key,value",
    [
        ("target_promotions", 0),
        ("maximum_updates_without_promotion", 0),
        ("screen_minimum_score", 0.5),
    ],
)
def test_invalid_curriculum_is_rejected(key, value):
    config = settings()
    config[key] = value
    with pytest.raises(ValueError):
        validate_settings(config)
