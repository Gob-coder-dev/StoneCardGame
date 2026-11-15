from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import torch

from samstone_rl.bridge.godot_process import GodotProcess
from samstone_rl.envs.action_space import ActionCodec
from samstone_rl.envs.observation import ObservationEncoder
from samstone_rl.models.policy import feature_args, restore_policy
from samstone_rl.models.tactical_actor_critic import TacticalActorCritic
from samstone_rl.utils.checkpoints import load_checkpoint
from samstone_rl.utils.device import resolve_torch_device


class CheckpointOpponent:
    """Frozen policy used for a complete episode of self-play."""

    def __init__(
        self, checkpoint_path: str | Path, device: str = "cpu", deterministic: bool = True
    ) -> None:
        self.path = Path(checkpoint_path).resolve()
        self.device = resolve_torch_device(device)
        self.deterministic = deterministic
        checkpoint = load_checkpoint(self.path)
        self.encoder = ObservationEncoder()
        self.codec = ActionCodec()
        self.model = restore_policy(checkpoint, self.device)

    def begin_episode(self, rng: np.random.Generator) -> None:
        del rng

    def choose(
        self,
        bridge: GodotProcess,
        legal_actions: list[dict[str, Any]],
        rng: np.random.Generator,
        player: int,
    ) -> dict[str, Any]:
        snapshot = bridge.get_state(player)
        observation = snapshot["observation"]
        mask = self.codec.legal_mask(legal_actions, observation["hand"])
        if not mask.any():
            raise RuntimeError("le checkpoint adverse n'a aucune action legale")
        with torch.no_grad():
            encoded = torch.as_tensor(
                self.encoder.encode(observation), dtype=torch.float32, device=self.device
            ).unsqueeze(0)
            masks = torch.as_tensor(mask, dtype=torch.bool, device=self.device).unsqueeze(0)
            scores = (
                [bridge.tactical_action_scores(player)]
                if isinstance(self.model, TacticalActorCritic)
                else None
            )
            distribution, _value = self.model.distribution_and_value(
                encoded,
                masks,
                *feature_args(self.model, encoded, masks, scores),
            )
        probabilities = distribution.probs[0].cpu().numpy()
        action = (
            int(probabilities.argmax())
            if self.deterministic
            else int(rng.choice(len(probabilities), p=probabilities))
        )
        return self.codec.action_to_move(action, observation["hand"])
