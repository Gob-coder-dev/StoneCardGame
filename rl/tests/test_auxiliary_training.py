from __future__ import annotations

import numpy as np
import torch

from samstone_rl.training.auxiliary import (
    FinalMarginHead,
    RolloutMarginLabels,
    auxiliary_loss,
)


def test_rollout_margin_labels_use_only_current_episode_positions():
    labels = RolloutMarginLabels(batch_size=12, num_envs=2)
    labels.observe(0, 0)
    labels.observe(1, 1)
    labels.observe(0, 2)
    target = labels.finish(0, {"score": 6, "opponent_score": 2})
    assert target == 0.5
    assert labels.samples == 2
    assert np.array_equal(np.flatnonzero(labels.mask), [0, 2])
    assert np.array_equal(labels.targets[[0, 2]], [0.5, 0.5])
    labels.observe(0, 4)
    labels.finish(0, {"score": 1, "opponent_score": 3})
    assert labels.targets[4] == -0.5
    assert not labels.mask[1]


def test_margin_head_backpropagates_into_shared_features():
    backbone = torch.nn.Linear(10, 16)
    head = FinalMarginHead(16)
    observations = torch.randn(8, 10)
    targets = torch.linspace(-1.0, 1.0, 8)
    predictions = head(backbone(observations))
    loss = auxiliary_loss(predictions, targets, "huber")
    loss.backward()
    assert backbone.weight.grad is not None
    assert head.network[0].weight.grad is not None
    assert torch.isfinite(loss)
