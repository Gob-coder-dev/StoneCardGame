from __future__ import annotations

import torch
from torch import nn
from torch.distributions import Categorical


class ActorCritic(nn.Module):
    def __init__(self, obs_dim: int, action_dim: int, hidden_dim: int = 256) -> None:
        super().__init__()
        self.backbone = nn.Sequential(
            nn.Linear(obs_dim, hidden_dim), nn.Tanh(),
            nn.Linear(hidden_dim, hidden_dim), nn.Tanh(),
        )
        self.actor = nn.Linear(hidden_dim, action_dim)
        self.critic = nn.Linear(hidden_dim, 1)
        self.hidden_dim = int(hidden_dim)
        self._initialize()

    def encode_state(self, observations: torch.Tensor) -> torch.Tensor:
        return self.backbone(observations)

    def distribution_and_value(self, observations: torch.Tensor,
                               action_mask: torch.Tensor) -> tuple[Categorical, torch.Tensor]:
        if action_mask.dtype is not torch.bool:
            raise TypeError("action_mask doit etre un tenseur bool")
        if torch.any(~action_mask.any(dim=-1)):
            raise ValueError("au moins une ligne ne contient aucune action legale")
        features = self.encode_state(observations)
        logits = self.actor(features).masked_fill(~action_mask, -1.0e9)
        return Categorical(logits=logits), self.critic(features).squeeze(-1)

    def act(self, observations: torch.Tensor, action_mask: torch.Tensor,
            deterministic: bool = False) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        distribution, value = self.distribution_and_value(observations, action_mask)
        action = distribution.probs.argmax(dim=-1) if deterministic else distribution.sample()
        selected = (action.long().unsqueeze(-1) == torch.arange(
            self.actor.out_features, device=action.device)).to(distribution.logits.dtype)
        return action, (distribution.logits * selected).sum(dim=-1), value

    def evaluate_actions(self, observations: torch.Tensor, action_mask: torch.Tensor,
                         actions: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        distribution, value = self.distribution_and_value(observations, action_mask)
        selected = (actions.long().unsqueeze(-1) == torch.arange(
            self.actor.out_features, device=actions.device)).to(distribution.logits.dtype)
        log_prob = (distribution.logits * selected).sum(dim=-1)
        entropy = -(distribution.probs * distribution.logits).sum(dim=-1)
        return log_prob, entropy, value

    def value(self, observations: torch.Tensor) -> torch.Tensor:
        return self.critic(self.encode_state(observations)).squeeze(-1)

    def _initialize(self) -> None:
        for layer in self.modules():
            if isinstance(layer, nn.Linear):
                nn.init.orthogonal_(layer.weight, 2**0.5)
                nn.init.zeros_(layer.bias)
        nn.init.orthogonal_(self.actor.weight, 0.01)
        nn.init.orthogonal_(self.critic.weight, 1.0)
