from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import torch

from samstone_rl.bridge.godot_process import GodotProcess
from samstone_rl.envs.action_space import ActionCodec
from samstone_rl.envs.observation import ObservationEncoder
from samstone_rl.models.actor_critic import ActorCritic


class CheckpointOpponent:
    """Frozen policy used for a complete episode of self-play."""

    def __init__(self, checkpoint_path: str | Path, device: str = "cpu",
                 deterministic: bool = True) -> None:
        self.path = Path(checkpoint_path).resolve()
        self.device = torch.device(device)
        self.deterministic = deterministic
        checkpoint = torch.load(self.path, map_location=self.device, weights_only=False)
        config = checkpoint.get("config", {})
        hidden_dim = int(config.get("model", {}).get("hidden_dim", 256))
        self.encoder = ObservationEncoder()
        self.codec = ActionCodec()
        self.model = ActorCritic(self.encoder.get_obs_size(), self.codec.n_actions, hidden_dim).to(self.device)
        self.model.load_state_dict(checkpoint["model"])
        self.model.eval()

    def begin_episode(self, rng: np.random.Generator) -> None:
        del rng

    def choose(self, bridge: GodotProcess, legal_actions: list[dict[str, Any]],
               rng: np.random.Generator, player: int) -> dict[str, Any]:
        snapshot = bridge.get_state(player)
        observation = snapshot["observation"]
        mask = self.codec.legal_mask(legal_actions, observation["hand"])
        if not mask.any():
            raise RuntimeError("le checkpoint adverse n'a aucune action legale")
        with torch.no_grad():
            distribution, _value = self.model.distribution_and_value(
                torch.as_tensor(self.encoder.encode(observation), dtype=torch.float32,
                                device=self.device).unsqueeze(0),
                torch.as_tensor(mask, dtype=torch.bool, device=self.device).unsqueeze(0),
            )
        probabilities = distribution.probs[0].cpu().numpy()
        action = int(probabilities.argmax()) if self.deterministic else int(
            rng.choice(len(probabilities), p=probabilities))
        return self.codec.action_to_move(action, observation["hand"])
