from __future__ import annotations

from collections.abc import Callable, Sequence
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
        return self.choose_many([(bridge, legal_actions, rng, player)])[0]

    def choose_many(
        self,
        requests: Sequence[
            tuple[GodotProcess, list[dict[str, Any]] | None, np.random.Generator, int]
        ],
        *,
        evaluate_tactics: Callable[[np.ndarray], np.ndarray] | None = None,
    ) -> list[dict[str, Any]]:
        """Choose moves with independent RNGs and optional batched tactical scores."""
        if not requests:
            return []
        observations = [
            bridge.get_state(player)["observation"] for bridge, _, _, player in requests
        ]
        masks_array = np.stack(
            [
                bridge.action_mask(player)
                if moves is None
                else self.codec.legal_mask(moves, observation["hand"])
                for observation, (bridge, moves, _, player) in zip(
                    observations, requests, strict=True
                )
            ]
        )
        if not masks_array.any(axis=1).all():
            raise RuntimeError("le checkpoint adverse n'a aucune action legale")
        scores = None
        if isinstance(self.model, TacticalActorCritic):
            scores = (
                evaluate_tactics(masks_array)
                if evaluate_tactics is not None
                else [bridge.tactical_action_scores(player) for bridge, _, _, player in requests]
            )
        with torch.no_grad():
            encoded = torch.as_tensor(
                np.stack([self.encoder.encode(observation) for observation in observations]),
                dtype=torch.float32,
                device=self.device,
            )
            masks = torch.as_tensor(masks_array, dtype=torch.bool, device=self.device)
            distribution, _value = self.model.distribution_and_value(
                encoded,
                masks,
                *feature_args(self.model, encoded, masks, scores),
            )
        probabilities = distribution.probs.cpu().numpy()
        moves = []
        for observation, row, (_, _, rng, _) in zip(
            observations, probabilities, requests, strict=True
        ):
            action = int(row.argmax()) if self.deterministic else int(rng.choice(len(row), p=row))
            moves.append(self.codec.action_to_move(action, observation["hand"]))
        return moves
