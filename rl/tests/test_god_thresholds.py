"""Veskar's phase-4 exception must not weaken the other gods or force promotion."""

import json
from pathlib import Path

import pytest
import yaml

from samstone_rl.training.curriculum import CurriculumManager
from samstone_rl.training.god_thresholds import parse_god_thresholds
from samstone_rl.training.validation import EvaluationSlice, PhaseFourGateReport

THRESHOLDS = {"veskar": {"minimum_win_rate": 0.60, "maximum_loss_rate": 0.20}}


def curriculum():
    return CurriculumManager(
        target_win_rate=0.8,
        confidence_floor=0.81,
        maximum_loss_rate=0.10,
        non_loss_confidence_floor=0.87,
        promotion_confirmations=2,
        god_thresholds=THRESHOLDS,
    )


def outcomes(wins=60, draws=20, core_wins=85, core_draws=10):
    return {
        "veskar": dict(wins=wins, draws=draws, games=100),
        "nerava": dict(wins=core_wins, draws=core_draws, games=100),
    }


def metrics(manager, data):
    return manager.promotion_metrics(
        sum(v["wins"] for v in data.values()),
        sum(v["draws"] for v in data.values()),
        sum(v["games"] for v in data.values()),
        data,
    )


def test_veskar_60_20_passes_without_inheriting_core_confidence_floor():
    result = metrics(curriculum(), outcomes())
    assert result["eligible"]
    assert result["win_rate"] == 0.725  # Global dashboard stays unmodified.
    assert result["god_thresholds"]["groups"]["core"]["win_rate"] == 0.85
    assert result["god_thresholds"]["groups"]["veskar"]["loss_rate"] == 0.2


@pytest.mark.parametrize(
    "data",
    [
        outcomes(59, 21),
        outcomes(60, 19),
        outcomes(core_wins=79),
        outcomes(core_draws=0),
        {"nerava": dict(wins=100, draws=0, games=100)},
    ],
)
def test_failure_in_either_group_cannot_be_masked_by_the_other(data):
    assert not metrics(curriculum(), data)["eligible"]


def test_confirmations_are_fresh_consecutive_and_restore_new_config_thresholds():
    manager = curriculum()
    good = outcomes()
    assert not manager.consider_promotion(145, 200, 30, good)
    state = manager.state_dict()
    restored = curriculum()
    restored.load_state_dict(state)
    assert restored.consider_promotion(145, 200, 30, good)
    assert restored.stage_index == 1
    assert not manager.consider_promotion(144, 200, 31, outcomes(59, 21))
    assert manager.consecutive_promotion_successes == 0
    assert not manager.consider_promotion(145, 200, 30, good)


def test_missing_and_inconsistent_god_counts_fail_closed():
    manager = curriculum()
    assert not manager.promotion_metrics(145, 30, 200)["eligible"]
    assert not manager.promotion_metrics(200, 0, 200, outcomes())["eligible"]


def gate(veskar=None, core=(85, 10, 5)):
    if veskar is None:
        # The four balanced slices pool to 60% wins / 20% losses. One small
        # slice is below 60%; the exception is deliberately judged in aggregate.
        veskar = [(40, 40, 20), (80, 0, 20), (60, 20, 20), (60, 20, 20)]
    slices = []
    for i, (agent, first) in enumerate(((1, 1), (1, 2), (2, 1), (2, 2))):
        slices.append(EvaluationSlice("hard", "veskar", agent, first, *veskar[i]))
        slices.append(EvaluationSlice("hard", "nerava", agent, first, *core))
    return slices


def report(slices):
    return PhaseFourGateReport.build(
        slices,
        ["hard"],
        ["veskar", "nerava"],
        overall_threshold=0.8,
        confidence_floor=0.8,
        slice_floor=0.7,
        minimum_games_per_slice=100,
        maximum_loss_rate=0.1,
        non_loss_confidence_floor=0.87,
        maximum_slice_loss_rate=0.1,
        god_thresholds=THRESHOLDS,
    )


def test_final_gate_uses_same_60_20_exception_with_complete_slice_coverage():
    result = report(gate())
    assert result.passed and not result.failed_slices
    assert result.to_dict()["criteria"]["god_thresholds"] == THRESHOLDS
    assert result.god_groups["hard"]["groups"]["veskar"]["games"] == 400
    assert not report(gate()[:-1]).passed


@pytest.mark.parametrize(
    "slices",
    [
        gate([(59, 21, 20)] * 4),
        gate([(60, 19, 21)] * 4),
        gate(core=(69, 26, 5)),
        gate(core=(85, 0, 15)),
    ],
)
def test_final_gate_rejects_weak_veskar_or_regressed_core(slices):
    assert not report(slices).passed


@pytest.mark.parametrize(
    "value",
    [
        {"veskar": {"minimum_win_rate": 0.6}},
        {"veskar": {"minimum_win_rate": float("nan"), "maximum_loss_rate": 0.2}},
        {"veskar": {"minimum_win_rate": 0.6, "maximum_loss_rate": 2}},
    ],
)
def test_invalid_god_criteria_are_rejected(value):
    with pytest.raises(ValueError):
        parse_god_thresholds(value)


def test_official_config_promotion_and_final_gate_agree():
    config = yaml.safe_load(
        (Path(__file__).parents[1] / "configs/ppo_phase4_vectorized.yaml").read_text(
            encoding="utf-8"
        )
    )
    assert config["curriculum"]["god_thresholds"] == THRESHOLDS
    assert config["evaluation"]["final_gate"]["god_thresholds"] == THRESHOLDS
    assert config["curriculum"]["promotion_win_rate"] == 0.8
    assert config["curriculum"]["maximum_loss_rate"] == 0.1
    assert json.loads(json.dumps(THRESHOLDS)) == THRESHOLDS


def test_resume_preserves_learning_but_revalidates_changed_god_thresholds(tmp_path):
    import torch

    from samstone_rl.training.ppo_cleanrl import PPOTrainer
    from samstone_rl.utils.checkpoints import load_checkpoint, state_checksum

    source = Path(__file__).parents[1] / "configs/ppo_phase4_vectorized.yaml"
    config = yaml.safe_load(source.read_text(encoding="utf-8"))
    config["device"] = "cpu"
    config["output_dir"] = str(tmp_path / "run")
    config["model"].update(hidden_dim=16, action_hidden_dim=8)
    config["environment"].update(evaluation_backend="python", python_profile_workers=1)
    config["ppo"].update(num_envs=2, rollout_steps=4, total_timesteps=16, minibatches=2)
    config["monitoring"]["tensorboard"] = False
    config["curriculum"].pop("god_thresholds")
    config["evaluation"]["final_gate"].pop("god_thresholds")
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    with PPOTrainer(path) as trainer:
        trainer.model.value(torch.zeros(1, 929)).sum().backward()
        trainer.optimizer.step()
        trainer.curriculum.stage_index = 7
        trainer.curriculum.awaiting_final_validation = True
        trainer.curriculum.bootstrap_evaluation_completed = True
        trainer.curriculum.consecutive_promotion_successes = 1
        trainer._save("latest.pt", 16, {}, 2)
    payload = load_checkpoint(tmp_path / "run/latest.pt")
    config["curriculum"]["god_thresholds"] = THRESHOLDS
    config["evaluation"]["final_gate"]["god_thresholds"] = THRESHOLDS
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    with PPOTrainer(path, mode="resume") as resumed:
        resumed.load_checkpoint(tmp_path / "run/latest.pt")
        assert resumed._resume_global_step == 16 and resumed._resume_update == 2
        assert resumed.curriculum.stage_index == 7
        assert not resumed.curriculum.awaiting_final_validation
        assert not resumed.curriculum.bootstrap_evaluation_completed
        assert not resumed.curriculum.phase_five_ready
        assert resumed.curriculum.consecutive_promotion_successes == 0
        assert state_checksum(resumed.model.state_dict()) == state_checksum(payload["model"])
        assert len(resumed.optimizer.state) == len(payload["optimizer"]["state"]) > 0
