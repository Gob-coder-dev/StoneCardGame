from __future__ import annotations

from collections.abc import Mapping

import torch
from torch import nn
from torch.distributions import Categorical


class TacticalActorCritic(nn.Module):
    """PPO model which scores legal placements with shared relational weights."""

    def __init__(self, obs_dim: int, action_dim: int, action_feature_dim: int,
                 hidden_dim: int = 512, action_hidden_dim: int = 128) -> None:
        super().__init__()
        if action_feature_dim <= 0 or action_hidden_dim <= 0:
            raise ValueError("les dimensions tactiques doivent etre positives")
        self.action_dim = int(action_dim)
        self.action_feature_dim = int(action_feature_dim)
        self.backbone = nn.Sequential(
            nn.Linear(obs_dim, hidden_dim), nn.Tanh(),
            nn.Linear(hidden_dim, hidden_dim), nn.Tanh(),
        )
        self.action_encoder = nn.Sequential(
            nn.Linear(action_feature_dim, action_hidden_dim), nn.Tanh(),
        )
        # Residual legacy head preserves a proven checkpoint at initialization;
        # the shared tactical scorer then learns corrections instead of starting
        # from a random policy.
        self.legacy_actor = nn.Linear(hidden_dim, action_dim)
        scorer_hidden = max(64, hidden_dim // 2)
        self.action_scorer = nn.Sequential(
            nn.Linear(hidden_dim + action_hidden_dim, scorer_hidden), nn.Tanh(),
            nn.Linear(scorer_hidden, 1),
        )
        self.critic = nn.Linear(hidden_dim, 1)
        self._initialize()

    def distribution_and_value(
            self, observations: torch.Tensor, action_mask: torch.Tensor,
            action_features: torch.Tensor) -> tuple[Categorical, torch.Tensor]:
        self._validate_inputs(observations, action_mask, action_features)
        state = self.backbone(observations)
        actions = self.action_encoder(action_features)
        expanded = state.unsqueeze(1).expand(-1, self.action_dim, -1)
        logits = (self.legacy_actor(state)
                  + self.action_scorer(torch.cat((expanded, actions), dim=-1)).squeeze(-1))
        logits = logits.masked_fill(~action_mask, torch.finfo(logits.dtype).min)
        return Categorical(logits=logits), self.critic(state).squeeze(-1)

    def act(self, observations: torch.Tensor, action_mask: torch.Tensor,
            action_features: torch.Tensor, deterministic: bool = False
            ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        distribution, value = self.distribution_and_value(
            observations, action_mask, action_features)
        action = distribution.probs.argmax(dim=-1) if deterministic else distribution.sample()
        return action, distribution.log_prob(action), value

    def evaluate_actions(self, observations: torch.Tensor, action_mask: torch.Tensor,
                         action_features: torch.Tensor, actions: torch.Tensor
                         ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        distribution, value = self.distribution_and_value(
            observations, action_mask, action_features)
        return distribution.log_prob(actions.long()), distribution.entropy(), value

    def value(self, observations: torch.Tensor) -> torch.Tensor:
        return self.critic(self.backbone(observations)).squeeze(-1)

    def import_legacy_state(self, state: Mapping[str, torch.Tensor]) -> tuple[str, ...]:
        """Transfer the strategic backbone and critic, never the incompatible actor."""
        own = self.state_dict()
        transferred = {
            name: tensor for name, tensor in state.items()
            if name.startswith(("backbone.", "critic."))
            and name in own and own[name].shape == tensor.shape
        }
        for legacy_name, tactical_name in (
                ("actor.weight", "legacy_actor.weight"),
                ("actor.bias", "legacy_actor.bias")):
            tensor = state.get(legacy_name)
            if tensor is not None and own[tactical_name].shape == tensor.shape:
                transferred[tactical_name] = tensor
        if not transferred:
            raise ValueError("aucun poids strategique compatible dans le checkpoint")
        self.load_state_dict(transferred, strict=False)
        return tuple(sorted(transferred))

    def _validate_inputs(self, observations: torch.Tensor, action_mask: torch.Tensor,
                         action_features: torch.Tensor) -> None:
        if action_mask.dtype is not torch.bool:
            raise TypeError("action_mask doit etre un tenseur bool")
        if torch.any(~action_mask.any(dim=-1)):
            raise ValueError("au moins une ligne ne contient aucune action legale")
        expected = (*observations.shape[:-1], self.action_dim, self.action_feature_dim)
        if tuple(action_features.shape) != expected:
            raise ValueError(
                f"features tactiques {tuple(action_features.shape)}, attendues {expected}")

    def _initialize(self) -> None:
        for layer in self.modules():
            if isinstance(layer, nn.Linear):
                nn.init.orthogonal_(layer.weight, 2**0.5)
                nn.init.zeros_(layer.bias)
        nn.init.orthogonal_(self.legacy_actor.weight, 0.01)
        nn.init.zeros_(self.action_scorer[-1].weight)
        nn.init.zeros_(self.action_scorer[-1].bias)
        nn.init.orthogonal_(self.critic.weight, 1.0)
