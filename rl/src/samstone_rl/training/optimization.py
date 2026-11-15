"""PPO losses, gradient updates and diagnostics; independent of simulators."""

from __future__ import annotations

from collections import defaultdict
from typing import Any

import numpy as np
import torch
from torch import nn

from samstone_rl.models import ActorCritic, TacticalActorCritic
from samstone_rl.training.auxiliary import (
    auxiliary_loss,
)


class PPOOptimizer:
    def __init__(
        self,
        model,
        optimizer,
        config,
        rng,
        device,
        auxiliary_head,
        auxiliary_optimizer,
        auxiliary_config,
    ):
        self.model, self.optimizer = model, optimizer
        self.tactical_features_enabled = isinstance(model, TacticalActorCritic)
        self.config, self.rng, self.device = config, rng, device
        self.auxiliary_head = auxiliary_head
        self.auxiliary_optimizer = auxiliary_optimizer
        self.auxiliary_config = auxiliary_config

    def optimize(self, storage, advantages, returns) -> dict[str, float]:
        ppo, size = self.config["ppo"], len(advantages)
        advantages = advantages - advantages.mean()
        advantages = advantages / (advantages.square().mean().sqrt() + 1e-8)
        indices = np.arange(size)
        collected: dict[str, list[float]] = defaultdict(list)
        legacy_epochs = int(ppo.get("update_epochs", 1))
        min_epochs = int(ppo.get("min_update_epochs", legacy_epochs))
        max_epochs = int(ppo.get("max_update_epochs", legacy_epochs))
        if min_epochs <= 0 or max_epochs < min_epochs:
            raise ValueError("min_update_epochs/max_update_epochs invalides")
        target_kl = float(ppo.get("target_kl", 0.0))
        epochs_used = 0
        stopped_early = False
        for _epoch in range(max_epochs):
            self.rng.shuffle(indices)
            for batch in np.array_split(indices, int(ppo["minibatches"])):
                batch_index = torch.as_tensor(batch, dtype=torch.long, device=self.device)
                if self.tactical_features_enabled:
                    assert isinstance(self.model, TacticalActorCritic)
                    new_log_prob, entropy, value = self.model.evaluate_actions(
                        storage["obs"][batch_index],
                        storage["masks"][batch_index],
                        storage["action_features"][batch_index],
                        storage["actions"][batch_index],
                    )
                else:
                    assert isinstance(self.model, ActorCritic)
                    new_log_prob, entropy, value = self.model.evaluate_actions(
                        storage["obs"][batch_index],
                        storage["masks"][batch_index],
                        storage["actions"][batch_index],
                    )
                log_ratio = new_log_prob - storage["log_probs"][batch_index]
                ratio = log_ratio.exp()
                policy_loss = torch.maximum(
                    -advantages[batch_index] * ratio,
                    -advantages[batch_index]
                    * ratio.clamp(1 - ppo["clip_coef"], 1 + ppo["clip_coef"]),
                ).mean()
                value_loss = 0.5 * (value - returns[batch_index]).pow(2).mean()
                loss = (
                    policy_loss
                    + ppo["value_coef"] * value_loss
                    - ppo["entropy_coef"] * entropy.mean()
                )
                auxiliary_batch_loss: torch.Tensor | None = None
                auxiliary_batch_mae: torch.Tensor | None = None
                if self.auxiliary_head is not None:
                    cpu_mask = storage["auxiliary_mask"][batch]
                    selected_positions = np.flatnonzero(cpu_mask)
                    if len(selected_positions):
                        selected = torch.as_tensor(
                            selected_positions, dtype=torch.long, device=self.device
                        )
                        selected_indices = batch_index[selected]
                        predictions = self.auxiliary_head(
                            self.model.encode_state(storage["obs"][selected_indices])
                        )
                        targets = torch.as_tensor(
                            storage["auxiliary_targets"][batch[selected_positions]],
                            dtype=torch.float32,
                            device=self.device,
                        )
                        auxiliary_batch_loss = auxiliary_loss(
                            predictions, targets, self.auxiliary_config.loss
                        )
                        auxiliary_batch_mae = (predictions - targets).abs().mean()
                        loss = loss + self.auxiliary_config.coefficient * auxiliary_batch_loss
                self.optimizer.zero_grad(set_to_none=True)
                if self.auxiliary_optimizer is not None:
                    self.auxiliary_optimizer.zero_grad(set_to_none=True)
                loss.backward()
                gradient_norm = nn.utils.clip_grad_norm_(
                    self.model.parameters(), ppo["max_grad_norm"], error_if_nonfinite=True
                )
                if self.auxiliary_head is not None:
                    nn.utils.clip_grad_norm_(self.auxiliary_head.parameters(), ppo["max_grad_norm"])
                self.optimizer.step()
                if auxiliary_batch_loss is not None:
                    assert self.auxiliary_optimizer is not None
                    self.auxiliary_optimizer.step()
                legal_counts = storage["masks"][batch_index].sum(dim=-1).clamp_min(2).float()
                normalized_entropy = entropy / legal_counts.log()
                values = {
                    "policy_loss": policy_loss,
                    "value_loss": value_loss,
                    "entropy": entropy.mean(),
                    "normalized_entropy": normalized_entropy.mean(),
                    "approx_kl": ((ratio - 1) - log_ratio).mean(),
                    "clip_fraction": ((ratio - 1).abs() > ppo["clip_coef"]).float().mean(),
                    "gradient_norm": gradient_norm,
                }
                for name, metric in values.items():
                    collected[name].append(float(metric.detach()))
                if auxiliary_batch_loss is not None and auxiliary_batch_mae is not None:
                    collected["auxiliary_margin_loss"].append(float(auxiliary_batch_loss.detach()))
                    collected["auxiliary_margin_mae"].append(float(auxiliary_batch_mae.detach()))
            epochs_used += 1
            epoch_metrics = len(np.array_split(indices, int(ppo["minibatches"])))
            epoch_kl = float(np.mean(collected["approx_kl"][-epoch_metrics:]))
            if (
                epochs_used >= min_epochs
                and target_kl > 0.0
                and epoch_kl > target_kl
                and epochs_used < max_epochs
            ):
                stopped_early = True
                break
        with torch.no_grad():
            fitted_values = self.model.value(storage["obs"])
        return_variance = (returns - returns.mean()).square().mean()
        residual = returns - fitted_values
        residual_variance = (residual - residual.mean()).square().mean()
        explained = (
            1.0 - residual_variance / return_variance
            if float(return_variance) > 1e-12
            else torch.tensor(0.0, device=self.device)
        )
        metrics = {name: float(np.mean(values)) for name, values in collected.items()}
        metrics["epochs_used"] = float(epochs_used)
        metrics["epoch_early_stop"] = float(stopped_early)
        metrics["explained_variance"] = float(explained)
        metrics["learning_rate"] = float(self.optimizer.param_groups[0]["lr"])
        if self.auxiliary_head is not None:
            metrics.update(self._auxiliary_metrics(storage))
        return metrics

    def _auxiliary_metrics(self, storage: dict[str, Any]) -> dict[str, float]:
        mask = np.asarray(storage.get("auxiliary_mask", ()), dtype=np.bool_)
        indices = np.flatnonzero(mask)
        if self.auxiliary_head is None or not len(indices):
            return {
                "auxiliary_margin_samples": 0.0,
                "auxiliary_margin_loss": 0.0,
                "auxiliary_margin_mae": 0.0,
                "auxiliary_margin_correlation": 0.0,
            }
        device_indices = torch.as_tensor(indices, dtype=torch.long, device=self.device)
        with torch.no_grad():
            predictions = (
                self.auxiliary_head(self.model.encode_state(storage["obs"][device_indices]))
                .detach()
                .cpu()
                .numpy()
            )
        targets = np.asarray(storage["auxiliary_targets"], dtype=np.float32)[indices]
        prediction_std = float(np.std(predictions))
        target_std = float(np.std(targets))
        correlation = (
            float(np.corrcoef(predictions, targets)[0, 1])
            if len(indices) > 1 and prediction_std > 1e-8 and target_std > 1e-8
            else 0.0
        )
        return {
            "auxiliary_margin_samples": float(len(indices)),
            "auxiliary_margin_mae": float(np.mean(np.abs(predictions - targets))),
            "auxiliary_margin_correlation": correlation,
        }
