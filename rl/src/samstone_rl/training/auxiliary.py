from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import torch
from torch import nn


class FinalMarginHead(nn.Module):
    """Training-only prediction of the normalized final board margin."""

    def __init__(self, hidden_dim: int) -> None:
        super().__init__()
        inner = max(32, min(128, int(hidden_dim) // 4))
        self.network = nn.Sequential(
            nn.Linear(int(hidden_dim), inner),
            nn.Tanh(),
            nn.Linear(inner, 1),
            nn.Tanh(),
        )
        for layer in self.modules():
            if isinstance(layer, nn.Linear):
                nn.init.orthogonal_(layer.weight, 0.5)
                nn.init.zeros_(layer.bias)

    def forward(self, features: torch.Tensor) -> torch.Tensor:
        return self.network(features).squeeze(-1)


@dataclass(frozen=True, slots=True)
class AuxiliaryConfig:
    enabled: bool = False
    coefficient: float = 0.02
    learning_rate: float | None = None
    loss: str = "huber"

    @classmethod
    def from_mapping(cls, values: dict | None) -> AuxiliaryConfig:
        raw = values or {}
        target = str(raw.get("target", "final_board_margin"))
        if target != "final_board_margin":
            raise ValueError("auxiliary.target doit valoir final_board_margin")
        loss = str(raw.get("loss", "huber"))
        if loss not in ("huber", "mse"):
            raise ValueError("auxiliary.loss doit valoir huber ou mse")
        coefficient = float(raw.get("coefficient", 0.02))
        if coefficient < 0.0:
            raise ValueError("auxiliary.coefficient doit etre positif")
        learning_rate = raw.get("learning_rate")
        if learning_rate is not None and float(learning_rate) <= 0.0:
            raise ValueError("auxiliary.learning_rate doit etre positif")
        return cls(bool(raw.get("enabled", False)), coefficient,
                   None if learning_rate is None else float(learning_rate), loss)


class RolloutMarginLabels:
    """Label only transitions collected in the current on-policy rollout.

    Lists are per environment and are cleared as soon as an episode ends.
    Positions from previous updates are deliberately not retained: this is
    supervision on the current PPO batch, not experience replay.
    """

    def __init__(self, batch_size: int, num_envs: int) -> None:
        self.targets = np.zeros(int(batch_size), dtype=np.float32)
        self.mask = np.zeros(int(batch_size), dtype=np.bool_)
        self._pending: list[list[int]] = [[] for _ in range(int(num_envs))]

    def observe(self, environment: int, flat_index: int) -> None:
        self._pending[int(environment)].append(int(flat_index))

    def finish(self, environment: int, episode: dict) -> float:
        own = int(episode["score"])
        opponent = int(episode["opponent_score"])
        playable = max(1, own + opponent)
        target = float(np.clip((own - opponent) / playable, -1.0, 1.0))
        indices = self._pending[int(environment)]
        if indices:
            self.targets[indices] = target
            self.mask[indices] = True
            indices.clear()
        return target

    @property
    def samples(self) -> int:
        return int(np.count_nonzero(self.mask))


def auxiliary_loss(predictions: torch.Tensor, targets: torch.Tensor,
                   kind: str) -> torch.Tensor:
    if kind == "huber":
        return nn.functional.smooth_l1_loss(predictions, targets)
    if kind == "mse":
        return nn.functional.mse_loss(predictions, targets)
    raise ValueError(f"perte auxiliaire inconnue: {kind}")

