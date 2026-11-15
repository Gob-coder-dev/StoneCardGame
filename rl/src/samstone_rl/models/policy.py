"""Single model/inference contract for training, frozen opponents and export."""

from __future__ import annotations

from typing import Any, Literal, TypedDict

import numpy as np
import torch

from samstone_rl.envs.action_space import ActionCodec
from samstone_rl.envs.observation import ObservationEncoder
from samstone_rl.tactics import TacticalActionEncoder

from .actor_critic import ActorCritic
from .tactical_actor_critic import TacticalActorCritic

Policy = ActorCritic | TacticalActorCritic
FEATURE_SCHEMA = TacticalActionEncoder.SCHEMA_VERSION


class PolicySpec(TypedDict):
    architecture: Literal["actor_critic", "tactical_actor_critic"]
    observation_schema: int
    observation_size: int
    action_count: int
    feature_schema: int
    feature_size: int
    hidden_dim: int
    action_hidden_dim: int


def policy_spec(config: dict[str, Any]) -> PolicySpec:
    model = config.get("model", {})
    tactical = model.get("architecture", "actor_critic") == "tactical_actor_critic"
    return {
        "architecture": "tactical_actor_critic" if tactical else "actor_critic",
        "observation_schema": ObservationEncoder.SCHEMA_VERSION,
        "observation_size": ObservationEncoder().get_obs_size(),
        "action_count": ActionCodec().n_actions,
        "feature_schema": FEATURE_SCHEMA if tactical else 0,
        "feature_size": TacticalActionEncoder().feature_size if tactical else 0,
        "hidden_dim": int(model.get("hidden_dim", 256)),
        "action_hidden_dim": int(model.get("action_hidden_dim", 128)) if tactical else 0,
    }


def build_policy(config: dict[str, Any], device: str | torch.device = "cpu") -> Policy:
    spec = policy_spec(config)
    architecture = config.get("model", {}).get("architecture", "actor_critic")
    if architecture == "tactical_actor_critic":
        model: Policy = TacticalActorCritic(
            spec["observation_size"],
            spec["action_count"],
            spec["feature_size"],
            spec["hidden_dim"],
            spec["action_hidden_dim"],
        )
    elif architecture == "actor_critic":
        model = ActorCritic(spec["observation_size"], spec["action_count"], spec["hidden_dim"])
    else:
        raise ValueError(f"architecture inconnue: {architecture}")
    return model.to(device)


def restore_policy(checkpoint: dict[str, Any], device: str | torch.device = "cpu") -> Policy:
    config = checkpoint.get("config", {})
    recorded = checkpoint.get("policy_spec")
    if recorded is not None and recorded != policy_spec(config):
        raise ValueError("contrat du modele incompatible avec cette version")
    model = build_policy(config, device)
    model.load_state_dict(checkpoint["model"])
    model.eval()
    return model


def feature_args(
    model: Policy, observations: torch.Tensor, masks: torch.Tensor, scores: Any
) -> tuple[torch.Tensor, ...]:
    """Encode public per-action scores for either a single state or a batch."""
    if not isinstance(model, TacticalActorCritic):
        return ()
    encoder = TacticalActionEncoder()
    obs = observations.detach().cpu().numpy()
    mask = masks.detach().cpu().numpy()
    values = np.stack([encoder.encode(o, m, s) for o, m, s in zip(obs, mask, scores, strict=True)])
    return (torch.as_tensor(values, dtype=torch.float32, device=observations.device),)


def act(
    model: Policy,
    observations: torch.Tensor,
    masks: torch.Tensor,
    features: torch.Tensor | None = None,
    deterministic: bool = True,
):
    if isinstance(model, TacticalActorCritic):
        if features is None:
            raise ValueError("features tactiques requises par cette politique")
        return model.act(observations, masks, features, deterministic=deterministic)
    return model.act(observations, masks, deterministic=deterministic)


def act_from_info(
    model: Policy, observation: np.ndarray, info: dict[str, Any], device: str | torch.device = "cpu"
):
    features = info.get("action_features")
    return act(
        model,
        torch.as_tensor(observation, dtype=torch.float32, device=device).unsqueeze(0),
        torch.as_tensor(info["action_mask"], dtype=torch.bool, device=device).unsqueeze(0),
        None
        if features is None
        else torch.as_tensor(features, dtype=torch.float32, device=device).unsqueeze(0),
    )
