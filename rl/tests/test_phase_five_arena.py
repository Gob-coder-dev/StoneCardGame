"""Small real-Godot checks for balanced neural duels and durable resume."""

import json
import os
import sqlite3
from collections import Counter
from contextlib import closing
from pathlib import Path
from types import SimpleNamespace

import pytest
import torch
import yaml
from checkpoint_fixtures import certified

from samstone_rl.models.policy import build_policy
from samstone_rl.training.phase_five_arena import PhaseFiveArena, cpu_inference_threads
from samstone_rl.training.phase_five_decks import DECK_POOLS, FAMILY_COUNTS, assign_match_decks
from samstone_rl.training.phase_five_protocol import duel_cases
from samstone_rl.training.ppo_self_play import PhaseFiveTrainer
from samstone_rl.utils.checkpoints import load_checkpoint, save_checkpoint


def test_deck_schedule_balances_ratios_and_reuses_decks_on_both_roles():
    scenarios = [
        {
            name: {
                ratio: [[f"{name}-{god}-{ratio}-{deck}"] for deck in range(2)]
                for ratio in FAMILY_COUNTS
            }
            for name in DECK_POOLS
        }
        for god in range(6)
    ]
    cases = duel_cases(6, 1, 42)
    assign_match_decks(cases, scenarios, 42, "confirmation_1")
    counts = Counter()
    mirrors = duel_cases(6, 1, 42)
    assign_match_decks(mirrors, scenarios, 42, "final_holdout")
    for first, second, final in zip(cases[::2], cases[1::2], mirrors[::2], strict=True):
        for side in ("left", "right"):
            assert first[f"{side}_deck"] == second[f"{side}_deck"]
            assert first[f"{side}_deck"][0].startswith("validation_decks-")
            assert final[f"{side}_deck"][0].startswith("holdout_decks-")
            counts[(first[side], side, first[f"{side}_ratio"])] += 1
    assert len(counts) == 6 * 2 * 4
    assert set(counts.values()) == {3}


def test_retention_pairs_all_gods_and_attributes_scores_to_the_policy_camp(monkeypatch):
    stages = [
        SimpleNamespace(
            name="hard", precision=1.0, anticipation=True, anticipation_probability=None
        )
    ]
    arena = PhaseFiveArena(
        SimpleNamespace(
            config={
                "phase5": {
                    "retention": {
                        "maximum_stage_regression": 0.05,
                        "maximum_god_regression": 0.08,
                    }
                }
            },
            scenarios=[{"god": str(i)} for i in range(6)],
            curriculum=SimpleNamespace(stages=stages),
        )
    )
    calls = []

    def run(cases, actor, *_):
        calls.append(cases)
        results = []
        matchups = Counter()
        for case in cases:
            camp = case["player"]
            own, rival = (
                (case["left"], case["right"]) if camp == 1 else (case["right"], case["left"])
            )
            matchups[(own, rival)] += 1
            results.append({"winner": 3 - camp if actor == "candidate" and own == 0 else camp})
        assert matchups == {(i, j): 2 for i in range(6) for j in range(6)}
        assert set(Counter((c["player"], c["first"]) for c in cases).values()) == {18}
        return results

    monkeypatch.setattr(arena, "run", run)
    monkeypatch.setattr(arena, "opponent", lambda _: SimpleNamespace(model="reference"))
    report = arena.retention("candidate", None, 2, 5_000_000)
    assert calls[0] == calls[1]
    assert report["games_per_policy"] == 72
    assert report["win_rate_deltas"]["god:0"] == -1
    assert all(report["win_rate_deltas"][f"god:{i}"] == 0 for i in range(1, 6))


def test_inference_thread_setting_is_restored_after_an_error():
    previous = torch.get_num_threads()
    try:
        torch.set_num_threads(2)
        with pytest.raises(RuntimeError):
            with cpu_inference_threads():
                assert torch.get_num_threads() == 1
                raise RuntimeError("simulated")
        assert torch.get_num_threads() == 2
    finally:
        torch.set_num_threads(previous)


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
@pytest.mark.parametrize("god", ["ilyr", "veskar"])
def test_identical_policies_score_half_and_completed_duels_are_not_replayed(
    tmp_path, monkeypatch, god
):
    config = yaml.safe_load(
        (Path(__file__).resolve().parents[1] / "configs/ppo_self_play_v2.yaml").read_text(
            encoding="utf-8"
        )
    )
    config["output_dir"] = str(tmp_path / "run")
    config["model"].update(hidden_dim=16, action_hidden_dim=8)
    config["ppo"].update(num_envs=1, rollout_steps=4, minibatches=1)
    config["evaluation"]["num_envs"] = 2
    config["environment"]["scenarios"] = [
        s for s in config["environment"]["scenarios"] if s["god"] == god
    ]
    config["monitoring"]["tensorboard"] = False
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    source = tmp_path / "phase4.pt"
    save_checkpoint(
        source,
        certified(
            dict(
                config=config,
                model=build_policy(config).state_dict(),
                curriculum=dict(stage_index=7, completed=True),
            ),
            "phase4",
        ),
    )
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        before = torch.get_rng_state().clone()
        actor = trainer.arena.live_actor()
        champion = trainer.output / trainer.phase5_state["champions"][-1]["path"]
        cases, outcomes, result = trainer.arena.duels(actor, champion, 1, 167894, "test_duels")
        assert torch.equal(before, torch.get_rng_state())
        assert result["games"] == 4 and result["score"] == 0.5
        monkeypatch.setattr(trainer.curriculum, "stages", trainer.curriculum.stages[:1])
        retention = trainer.arena.retention(actor, trainer.phase4_baseline, 1, 179902)
        assert retention["passed"]
        assert all(delta == 0 for delta in retention["win_rate_deltas"].values())
        ledger = next((trainer.output / "evaluations/phase5").glob("*.sqlite3"))
        with closing(sqlite3.connect(ledger)) as db:
            stored = [json.loads(row[0]) for row in db.execute("SELECT info FROM results")]
            assert all(set(info) == {"winner", "margin", "turns"} for info in stored)
        monkeypatch.setattr(
            trainer.arena, "_play", lambda *a: pytest.fail("committed match replayed")
        )
        assert trainer.arena.duels(actor, champion, 1, 167894, "test_duels")[1] == outcomes


@pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")
def test_real_pending_duels_resume_committed_games_before_budget_exit(tmp_path, monkeypatch):
    config = yaml.safe_load(
        (Path(__file__).resolve().parents[1] / "configs/ppo_self_play_v2.yaml").read_text(
            encoding="utf-8"
        )
    )
    config["output_dir"] = str(tmp_path / "run")
    config["model"].update(hidden_dim=16, action_hidden_dim=8)
    config["ppo"].update(num_envs=1, rollout_steps=4, minibatches=1, total_timesteps=4)
    config["evaluation"]["num_envs"] = 1
    config["environment"]["scenarios"] = [
        s for s in config["environment"]["scenarios"] if s["god"] == "ilyr"
    ]
    config["monitoring"]["tensorboard"] = False
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    source = tmp_path / "phase4.pt"
    save_checkpoint(
        source,
        certified(
            dict(
                config=config,
                model=build_policy(config).state_dict(),
                curriculum=dict(stage_index=7, completed=True),
            ),
            "phase4",
        ),
    )

    def small_gate(trainer, pending):
        actor = trainer.arena.opponent(trainer.output / pending["path"]).model
        champion = trainer.output / trainer.phase5_state["champions"][-1]["path"]
        trainer.arena.duels(actor, champion, 1, 189052, "resume_check")
        return dict(passed=False, reason="test_complete")

    monkeypatch.setattr("samstone_rl.training.phase_five_curriculum.evaluate_candidate", small_gate)
    with PhaseFiveTrainer(path, phase4_checkpoint=source) as trainer:
        with torch.no_grad():
            next(trainer.model.parameters()).add_(0.001)
        original = trainer._phase5_progress

        def stop(operation, completed, total):
            original(operation, completed, total)
            if operation == "resume_check" and completed == 1:
                raise InterruptedError("simulated interruption after commit")

        monkeypatch.setattr(trainer, "_phase5_progress", stop)
        with pytest.raises(InterruptedError):
            trainer._start_candidate(4, 1, {})
        latest = trainer.output / "latest.pt"
        assert load_checkpoint(latest)["phase5"]["champion_curriculum"]["pending"]
    with PhaseFiveTrainer(path, resume=latest) as trainer:
        count = []
        play = trainer.arena._play

        def record(*args):
            count.append(1)
            return play(*args)

        monkeypatch.setattr(trainer.arena, "_play", record)
        monkeypatch.setattr(trainer, "_collect_rollout", lambda *a: pytest.fail("unexpected PPO"))
        trainer.train()
        assert len(count) == 3
        assert trainer.phase5_state["pending"] is None
        assert trainer.phase5_state["failed_attempts"] == 1
        assert trainer.phase5_state["status"] == "budget_exhausted"
