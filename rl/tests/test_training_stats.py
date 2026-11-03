import json

from scripts.training_stats import collect_stats


def test_stats_include_phase_five_mixed_matches_and_anchors(tmp_path):
    events = [
        {"stream": "training", "step": 16,
         "metrics": {"episodes_completed": 2}},
        {"stream": "evaluation", "step": 16,
         "metrics": {"games": 8, "by_god": {"veskar": {"games": 4}},
                     "anchors": {"precision_0": {"games": 2}},
                     "mixed_vs_phase4": {"games": 144,
                                         "by_god": {"veskar": {"games": 24}}}}},
    ]
    (tmp_path / "metrics.jsonl").write_text(
        "\n".join(json.dumps(item) for item in events) + "\n", encoding="utf-8")
    stats = collect_stats(tmp_path)
    assert stats["evaluation"]["games"] == 154
    assert stats["evaluation"]["primary_games"] == 8
    assert stats["evaluation"]["anchor_games"] == 2
    assert stats["evaluation"]["mixed_games"] == 144
    assert stats["evaluation"]["games_by_god"]["veskar"] == 28
    assert stats["total_observed_games_estimate"] == 156
