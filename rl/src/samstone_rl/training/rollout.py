"""Experience collection, episode resets and rollout statistics for PPO."""

from __future__ import annotations

import time
from collections import defaultdict
from dataclasses import dataclass
from typing import Any

import numpy as np
import torch

from .auxiliary import RolloutMarginLabels


@dataclass
class RolloutBatch:
    storage: dict[str, Any]
    observations: list[np.ndarray]
    infos: list[dict]
    global_step: int
    profile: dict[str, float]
    episodes: list[dict]
    sampled_gods: dict[str, int]
    sampled_terrains: dict[str, int]
    terrain_attempts: int
    capture_rewards: list[float]
    terminal_rewards: list[float]
    final_margin_rewards: list[float]
    control_delta_rewards: list[float]


class RolloutMixin:
    def _collect_rollout(
        self,
        observations: list[np.ndarray],
        infos: list[dict],
        steps: int,
        global_step: int,
        update: int,
    ) -> RolloutBatch:
        """Collect complete decisions while keeping incomplete episodes alive."""
        batch_size = steps * self.num_envs
        profile: dict[str, float] = defaultdict(float)
        phase_started = time.perf_counter()
        storage = self._empty_storage(batch_size)
        auxiliary_labels = (
            RolloutMarginLabels(batch_size, self.num_envs)
            if self.auxiliary_config.enabled
            else None
        )
        profile["storage_seconds"] += time.perf_counter() - phase_started
        episodes: list[dict] = []
        sampled_gods: dict[str, int] = defaultdict(int)
        sampled_terrains: dict[str, int] = defaultdict(int)
        terrain_attempts = [0]
        capture_rewards: list[float] = []
        terminal_rewards: list[float] = []
        final_margin_rewards: list[float] = []
        control_delta_rewards: list[float] = []
        for step in range(steps):
            phase_started = time.perf_counter()
            slot = slice(step * self.num_envs, (step + 1) * self.num_envs)
            obs_batch = torch.as_tensor(
                self.batch_env.observations
                if self.batch_env is not None
                else np.asarray(observations),
                dtype=torch.float32,
                device=self.device,
            )
            masks = torch.as_tensor(
                self.batch_env.action_masks
                if self.batch_env is not None
                else np.asarray([info["action_mask"] for info in infos]),
                dtype=torch.bool,
                device=self.device,
            )
            action_features = self._action_features_tensor(infos)
            storage["obs"][slot] = obs_batch
            storage["masks"][slot] = masks
            if action_features is not None:
                storage["action_features"][slot] = action_features
            profile["preparation_seconds"] += time.perf_counter() - phase_started
            phase_started = time.perf_counter()
            with torch.no_grad():
                actions, log_probs, values = self._act(obs_batch, masks, action_features)
            action_values = [int(action) for action in actions.detach().cpu().tolist()]
            profile["policy_seconds"] += time.perf_counter() - phase_started
            phase_started = time.perf_counter()
            try:
                transitions = self._step_training_envs(action_values)
            except ValueError as exc:
                if "action illegale" in str(exc):
                    self._observe_health(global_step, {"illegal_actions": 1.0}, update)
                raise
            profile["environment_seconds"] += time.perf_counter() - phase_started
            phase_started = time.perf_counter()
            storage["actions"][slot] = actions
            storage["log_probs"][slot] = log_probs
            storage["values"][slot] = values
            terminated_indices: list[int] = []
            next_observations: list[np.ndarray] = []
            next_infos: list[dict] = []
            for index, (next_obs, reward, terminated, truncated, info) in enumerate(transitions):
                if auxiliary_labels is not None:
                    auxiliary_labels.observe(index, slot.start + index)
                storage["rewards"][slot.start + index] = float(reward)
                storage["dones"][slot.start + index] = float(terminated or truncated)
                capture_rewards.append(float(info.get("capture_reward", 0.0)))
                terminal_rewards.append(float(info.get("terminal_reward", 0.0)))
                final_margin_rewards.append(float(info.get("final_margin_reward", 0.0)))
                control_delta_rewards.append(float(info.get("control_delta_reward", 0.0)))
                next_observations.append(next_obs)
                next_infos.append(info)
                if terminated or truncated:
                    if "episode" in info:
                        episodes.append(info["episode"])
                        if auxiliary_labels is not None:
                            auxiliary_labels.finish(index, info["episode"])
                    terminated_indices.append(index)
            profile["bookkeeping_seconds"] += time.perf_counter() - phase_started
            global_step += self.num_envs
            if terminated_indices:
                phase_started = time.perf_counter()
                resets, reset_infos = self._reset_training_episodes(
                    terminated_indices,
                    sampled_gods=sampled_gods,
                    sampled_terrains=sampled_terrains,
                    terrain_attempts=terrain_attempts,
                )
                for index, reset_obs, reset_info in zip(
                    terminated_indices, resets, reset_infos, strict=True
                ):
                    next_observations[index] = reset_obs
                    next_infos[index] = reset_info
                profile["reset_seconds"] += time.perf_counter() - phase_started
            observations, infos = next_observations, next_infos
        if auxiliary_labels is not None:
            storage["auxiliary_targets"] = auxiliary_labels.targets
            storage["auxiliary_mask"] = auxiliary_labels.mask
        return RolloutBatch(
            storage=storage,
            observations=observations,
            infos=infos,
            global_step=global_step,
            profile=profile,
            episodes=episodes,
            sampled_gods=sampled_gods,
            sampled_terrains=sampled_terrains,
            terrain_attempts=terrain_attempts[0],
            capture_rewards=capture_rewards,
            terminal_rewards=terminal_rewards,
            final_margin_rewards=final_margin_rewards,
            control_delta_rewards=control_delta_rewards,
        )
