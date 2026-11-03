from __future__ import annotations

import argparse
import hashlib
import json
import math
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

import numpy as np
import psutil
import torch
import yaml
from torch import nn

from samstone_rl.batch_engine import BatchSamStoneEnv
from samstone_rl.bridge import GodotProtocolError
from samstone_rl.envs.samstone_env import RewardScheme, SamStoneEnv
from samstone_rl.models import ActorCritic, TacticalActorCritic
from samstone_rl.observability import (
    HealthMonitor,
    RunTracker,
    TrainingHealthError,
    build_run_manifest,
)
from samstone_rl.tactics import TacticalActionEncoder
from samstone_rl.training.auxiliary import (
    AuxiliaryConfig,
    FinalMarginHead,
    RolloutMarginLabels,
    auxiliary_loss,
)
from samstone_rl.training.curriculum import CurriculumManager, stages_from_config
from samstone_rl.training.validation import (
    EvaluationSlice,
    PhaseFourGateReport,
    wilson_lower,
)
from samstone_rl.utils.device import resolve_torch_device
from samstone_rl.utils.optim import DirectMLAdam
from samstone_rl.utils.seeding import set_seed


class PPOTrainer:
    def __init__(self, config_path: str | Path,
                 output_override: str | Path | None = None) -> None:
        config_path = Path(config_path).resolve()
        with config_path.open(encoding="utf-8") as stream:
            self.config = yaml.safe_load(stream)
        self._validate_config()
        seed = int(self.config["seed"])
        set_seed(seed)
        self.rng = np.random.default_rng(seed)
        self.device = resolve_torch_device(self.config.get("device", "cpu"))
        model_config = self.config["model"]
        self.model_architecture = str(model_config.get("architecture", "actor_critic"))
        self.tactical_features_enabled = self.model_architecture == "tactical_actor_critic"
        self.tactical_feature_dim = TacticalActionEncoder().feature_size
        self.process = psutil.Process()
        self.process.cpu_percent(None)
        configured_output = Path(output_override or self.config["output_dir"])
        self.output = (configured_output if configured_output.is_absolute()
                       else config_path.parent.parent / configured_output)
        self.output.mkdir(parents=True, exist_ok=True)
        monitoring = self.config.get("monitoring", {})
        self.tracker = RunTracker(
            self.output, "ppo", tensorboard=bool(monitoring.get("tensorboard", True)))
        self.tracker.initialize_manifest(build_run_manifest(
            "ppo", self.config, config_path, seed,
            extra={"device": str(self.device), "observation": 1, "action_space": 128,
                   "model_architecture": self.model_architecture,
                   "action_feature_size": (self.tactical_feature_dim
                                           if self.tactical_features_enabled else 0)}))
        self.health = HealthMonitor(self.output, monitoring.get("alerts", {}))
        curriculum = self.config["curriculum"]
        self.curriculum = CurriculumManager(curriculum["promotion_win_rate"],
                                            curriculum["confidence_floor"],
                                            curriculum["replay_probability"],
                                            stages=stages_from_config(
                                                curriculum.get("stages")),
                                            god_sampling=curriculum.get("god_sampling"),
                                            terrain_sampling=curriculum.get("terrain_sampling"),
                                            maximum_loss_rate=curriculum.get("maximum_loss_rate"),
                                            non_loss_confidence_floor=curriculum.get(
                                                "non_loss_confidence_floor"),
                                            promotion_confirmations=curriculum.get(
                                                "promotion_confirmations", 1))
        if self.curriculum.god_sampling_enabled:
            self.curriculum.initialize_god_sampling(
                [str(scenario["god"]) for scenario in self.scenarios])
        self.num_envs = int(self.config["ppo"].get("num_envs", 1))
        environment = self.config["environment"]
        reward = environment["reward"]
        self.reward_scheme = RewardScheme(
            capture=float(reward["capture"]),
            multi_capture=float(reward["multi_capture"]),
            terminal=float(reward["terminal"]),
            final_margin=float(reward.get("final_margin", 0.0)),
            final_margin_scale=float(reward.get("final_margin_scale", 5.0)),
            board_control_delta=float(reward.get("board_control_delta", 0.0)),
            board_control_delta_limit=int(reward.get("board_control_delta_limit", 4)),
        )
        self.training_backend = str(environment.get("backend", "godot"))
        self.evaluation_backend = str(environment.get(
            "evaluation_backend",
            "python" if self.training_backend == "python_batch"
            else self.training_backend))
        scalar_training_backend = ("python" if self.training_backend == "python_batch"
                                   else self.training_backend)
        self.env = self._make_env(scalar_training_backend)
        self.batch_env: BatchSamStoneEnv | None = None
        if self.training_backend == "python_batch":
            self.batch_env = BatchSamStoneEnv(
                self.num_envs, self.reward_scheme,
                tactical_features=self.tactical_features_enabled,
                vector_tactical=bool(environment.get("vector_tactical", True)),
                vector_effects=bool(environment.get("vector_effects", True)))
            self.training_envs: list[SamStoneEnv] = []
        else:
            # Environment zero may be shared with evaluation only when both
            # workflows deliberately select the same scalar backend.
            self.training_envs = [self.env, *[
                self._make_env(self.training_backend) for _ in range(self.num_envs - 1)
            ]]
        self.evaluation_env = (
            self.env if self.batch_env is None
            and self.evaluation_backend == self.training_backend
            else self._make_env(self.evaluation_backend))
        self.evaluation_num_envs = int(self.config["evaluation"].get("num_envs", 1))
        self.evaluation_envs = [self.evaluation_env, *[
            self._make_env(self.evaluation_backend)
            for _ in range(self.evaluation_num_envs - 1)
        ]]
        if self.tactical_features_enabled:
            self.model = TacticalActorCritic(
                self.env.observation_space.shape[0], self.env.action_space.n,
                self.tactical_feature_dim, int(model_config["hidden_dim"]),
                int(model_config.get("action_hidden_dim", 128))).to(self.device)
        else:
            self.model = ActorCritic(
                self.env.observation_space.shape[0], self.env.action_space.n,
                int(model_config["hidden_dim"])).to(self.device)
        optimizer_type = DirectMLAdam if self.device.type == "privateuseone" else torch.optim.Adam
        self.optimizer = optimizer_type(
            self.model.parameters(), lr=self.config["ppo"]["learning_rate"], eps=1e-5)
        self.auxiliary_config = AuxiliaryConfig.from_mapping(
            self.config.get("auxiliary"))
        self.auxiliary_head: FinalMarginHead | None = None
        self.auxiliary_optimizer: torch.optim.Optimizer | None = None
        if self.auxiliary_config.enabled:
            self.auxiliary_head = FinalMarginHead(self.model.hidden_dim).to(self.device)
            auxiliary_lr = (self.auxiliary_config.learning_rate
                            or float(self.config["ppo"]["learning_rate"]))
            self.auxiliary_optimizer = optimizer_type(
                self.auxiliary_head.parameters(), lr=auxiliary_lr, eps=1e-5)
        self.best_win_rate = -1.0
        self.best_stage_index = -1
        self._resume_global_step = 0
        self._resume_update = 0
        self._manifest_has_engine = False
        self._simulator_processes: dict[int, psutil.Process] = {}

    def _make_env(self, backend: str) -> SamStoneEnv:
        return SamStoneEnv(
            godot_path=self.config["environment"].get("godot_path"),
            opponent=self.curriculum.current.opponent(),
            agent_player=1,
            reward_scheme=self.reward_scheme,
            backend=backend,
            tactical_features=self.tactical_features_enabled,
        )

    @property
    def scenarios(self) -> list[dict]:
        return self.config["environment"].get("scenarios", [])

    def _validate_config(self) -> None:
        ppo = self.config["ppo"]
        rollout = int(ppo["rollout_steps"])
        total = int(ppo["total_timesteps"])
        minibatches = int(ppo["minibatches"])
        if rollout <= 0 or total <= 0 or minibatches <= 0 or int(ppo["update_epochs"]) <= 0:
            raise ValueError("les paramètres PPO entiers doivent être strictement positifs")
        if total % rollout != 0:
            raise ValueError("total_timesteps doit être divisible par rollout_steps")
        if rollout % minibatches != 0:
            raise ValueError("rollout_steps doit être divisible par minibatches")
        num_envs = int(ppo.get("num_envs", 1))
        if num_envs <= 0:
            raise ValueError("num_envs doit etre strictement positif")
        batch_size = rollout * num_envs
        if total % batch_size != 0:
            raise ValueError("total_timesteps doit etre divisible par rollout_steps * num_envs")
        if batch_size % minibatches != 0:
            raise ValueError("rollout_steps * num_envs doit etre divisible par minibatches")
        if not self.config["environment"].get("scenarios"):
            raise ValueError("au moins un scénario d'entraînement est obligatoire")
        training_backend = self.config["environment"].get("backend", "godot")
        if training_backend not in ("godot", "python", "python_batch"):
            raise ValueError(
                "environment.backend doit valoir 'godot', 'python' ou 'python_batch'")
        evaluation_backend = self.config["environment"].get(
            "evaluation_backend", "python" if training_backend == "python_batch"
            else training_backend)
        if evaluation_backend not in ("godot", "python"):
            raise ValueError(
                "environment.evaluation_backend doit valoir 'godot' ou 'python'")
        architecture = str(self.config.get("model", {}).get(
            "architecture", "actor_critic"))
        if architecture not in ("actor_critic", "tactical_actor_critic"):
            raise ValueError("model.architecture inconnu")
        evaluation = self.config["evaluation"]
        if int(evaluation["games"]) <= 0 or int(evaluation["every_updates"]) <= 0:
            raise ValueError("la fréquence et le nombre de matchs d'évaluation doivent être positifs")
        if int(evaluation.get("num_envs", 1)) <= 0:
            raise ValueError("evaluation.num_envs doit etre strictement positif")
        bootstrap = self.config.get("curriculum", {}).get("bootstrap_evaluation", {})
        if not isinstance(bootstrap, dict):
            raise TypeError("curriculum.bootstrap_evaluation doit etre un objet")
        if int(bootstrap.get("seed_stride", 100000)) <= 0:
            raise ValueError("curriculum.bootstrap_evaluation.seed_stride doit etre positif")

    def train(self) -> None:
        self._train_vectorized()

    def _action_features_tensor(self, infos: list[dict[str, Any]]) -> torch.Tensor | None:
        if not self.tactical_features_enabled:
            return None
        missing = [index for index, info in enumerate(infos)
                   if "action_features" not in info]
        if missing:
            raise RuntimeError(f"features tactiques absentes pour les slots {missing}")
        values = np.asarray([info["action_features"] for info in infos], dtype=np.float32)
        expected = (len(infos), self.env.action_space.n, self.tactical_feature_dim)
        if values.shape != expected:
            raise RuntimeError(
                f"lot tactique {values.shape}, dimensions attendues {expected}")
        return torch.as_tensor(values, dtype=torch.float32, device=self.device)

    def _act(self, observations: torch.Tensor, masks: torch.Tensor,
             action_features: torch.Tensor | None, deterministic: bool = False
             ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        if self.tactical_features_enabled:
            if action_features is None or not isinstance(self.model, TacticalActorCritic):
                raise RuntimeError("modele tactique sans features d'action")
            return self.model.act(observations, masks, action_features, deterministic)
        if not isinstance(self.model, ActorCritic):
            raise TypeError("architecture de modele incoherente")
        return self.model.act(observations, masks, deterministic)

    def _evaluation_action_feature_args(self, info: dict[str, Any]) -> tuple[torch.Tensor, ...]:
        if not self.tactical_features_enabled:
            return ()
        features = np.asarray(info.get("action_features"), dtype=np.float32)
        expected = (self.env.action_space.n, self.tactical_feature_dim)
        if features.shape != expected:
            raise RuntimeError(
                f"features tactiques d'evaluation {features.shape}, attendues {expected}")
        return (torch.as_tensor(
            features, dtype=torch.float32, device=self.device).unsqueeze(0),)

    def _train_vectorized(self) -> None:
        """Collect PPO experience from one or more independent environments.

        ``rollout_steps`` is the number of decisions per environment. The
        optimizer always receives ``rollout_steps * num_envs`` transitions.
        """
        ppo = self.config["ppo"]
        steps = int(ppo["rollout_steps"])
        total = int(ppo["total_timesteps"])
        batch_size = steps * self.num_envs
        self._rollout_executor = (None if self.batch_env is not None
                                  else ThreadPoolExecutor(max_workers=self.num_envs))
        last_evaluation = self._run_bootstrap_evaluation()
        observations, infos = self._reset_training_episodes(
            list(range(self.num_envs)), initial=self._resume_update == 0)
        # Scalar Godot workers are started lazily by ``reset``.  Recording the
        # engine manifest before that reset would query an inactive process.
        # The native batch backend is already available, so the same ordering
        # is safe for every backend and keeps the manifest authoritative.
        self._record_engine_manifest()
        global_step = self._resume_global_step
        remaining_steps = max(0, total - global_step)
        updates_to_run = math.ceil(remaining_steps / batch_size)
        final_update = self._resume_update + updates_to_run
        last_evaluation = last_evaluation or {}
        monitoring = self.config.get("monitoring", {})
        checkpoint_every = int(monitoring.get("checkpoint_every_updates", 50))
        snapshot_every = int(monitoring.get("snapshot_every_updates", 200))
        try:
            for update in range(self._resume_update + 1, final_update + 1):
                started = time.perf_counter()
                profile: dict[str, float] = defaultdict(float)
                phase_started = time.perf_counter()
                storage = self._empty_storage(batch_size)
                auxiliary_labels = (RolloutMarginLabels(batch_size, self.num_envs)
                                    if self.auxiliary_config.enabled else None)
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
                        np.asarray(observations), dtype=torch.float32, device=self.device)
                    masks = torch.as_tensor(
                        np.asarray([info["action_mask"] for info in infos]),
                        dtype=torch.bool, device=self.device)
                    action_features = self._action_features_tensor(infos)
                    storage["obs"][slot] = obs_batch
                    storage["masks"][slot] = masks
                    if action_features is not None:
                        storage["action_features"][slot] = action_features
                    profile["preparation_seconds"] += time.perf_counter() - phase_started
                    phase_started = time.perf_counter()
                    with torch.no_grad():
                        actions, log_probs, values = self._act(
                            obs_batch, masks, action_features)
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
                            terminated_indices, sampled_gods=sampled_gods,
                            sampled_terrains=sampled_terrains, terrain_attempts=terrain_attempts)
                        for index, reset_obs, reset_info in zip(
                                terminated_indices, resets, reset_infos, strict=True):
                            next_observations[index] = reset_obs
                            next_infos[index] = reset_info
                        profile["reset_seconds"] += time.perf_counter() - phase_started
                    observations, infos = next_observations, next_infos
                if auxiliary_labels is not None:
                    storage["auxiliary_targets"] = auxiliary_labels.targets
                    storage["auxiliary_mask"] = auxiliary_labels.mask
                phase_started = time.perf_counter()
                with torch.no_grad():
                    next_values = self.model.value(torch.as_tensor(
                        np.asarray(observations), dtype=torch.float32, device=self.device))
                advantages, returns = self._gae_vectorized(storage, next_values, steps)
                profile["bootstrap_gae_seconds"] += time.perf_counter() - phase_started
                phase_started = time.perf_counter()
                metrics = self._optimize(storage, advantages, returns)
                profile["optimization_seconds"] += time.perf_counter() - phase_started
                elapsed = max(time.perf_counter() - started, 1e-9)
                measured = sum(profile.values())
                profile["other_seconds"] = max(0.0, elapsed - measured)
                profile["total_seconds"] = elapsed
                for name, seconds in tuple(profile.items()):
                    if name.endswith("_seconds") and name != "total_seconds":
                        profile[name.removesuffix("_seconds") + "_fraction"] = seconds / elapsed
                metrics.update(self._rollout_metrics(
                    storage, advantages, returns, episodes, capture_rewards,
                    terminal_rewards, final_margin_rewards, control_delta_rewards,
                    batch_size / elapsed))
                metrics.update(self._resource_metrics())
                metrics.update({
                    "environment_count": float(self.num_envs),
                    "rollout_batch_size": float(batch_size),
                    "profile": dict(profile),
                })
                if self.batch_env is not None:
                    metrics["vector_engine"] = self.batch_env.vector_metrics(reset=True)
                if sampling := self.curriculum.god_sampling_metrics(sampled_gods):
                    metrics["god_sampling"] = sampling
                if sampling := self.curriculum.terrain_sampling_metrics(
                        sampled_terrains, terrain_attempts[0]):
                    metrics["terrain_sampling"] = sampling
                context = {
                    "update": update,
                    "stage": self.curriculum.current.name,
                    "phase_five_ready": self.curriculum.phase_five_ready,
                    "environment_count": self.num_envs,
                }
                self._observe_health(global_step, metrics, update)
                self.tracker.log("training", global_step, metrics, context)

                if checkpoint_every > 0 and update % checkpoint_every == 0:
                    self._save("latest.pt", global_step, {}, update)
                if snapshot_every > 0 and update % snapshot_every == 0:
                    self._save(f"checkpoints/step_{global_step:012d}.pt", global_step, {}, update)

                evaluation_result = None
                if update % int(self.config["evaluation"]["every_updates"]) == 0:
                    evaluation_started = time.perf_counter()
                    results = self.evaluate()
                    evaluation_result = results
                    evaluation_seconds = max(time.perf_counter() - evaluation_started, 1e-9)
                    evaluated_games = int(results["games"]) + sum(
                        int(item["games"]) for item in results["anchors"].values())
                    for key in ("mixed_vs_phase4", "specialist_vs_universal"):
                        evaluated_games += int(results.get(key, {}).get("games", 0))
                    results["evaluation_seconds"] = evaluation_seconds
                    results["games_per_second"] = evaluated_games / evaluation_seconds
                    evaluated_stage_index = self.curriculum.stage_index
                    promoted = self.curriculum.consider_promotion(
                        int(results["wins"]), int(results["games"]), int(results["draws"]))
                    results["promotion"] = self.curriculum.promotion_metrics(
                        int(results["wins"]), int(results["draws"]), int(results["games"]))
                    results["promotion"]["consecutive_promotion_successes"] = (
                        self.curriculum.consecutive_promotion_successes)
                    if sampling := self.curriculum.update_god_sampling(results["by_god"]):
                        results["god_sampling"] = sampling
                    if sampling := self.curriculum.update_terrain_sampling(results["by_blocked_count"]):
                        results["terrain_sampling"] = sampling
                    results["promoted"] = promoted
                    results["evaluated_stage_index"] = evaluated_stage_index
                    results["next_stage_index"] = self.curriculum.stage_index
                    score = self._evaluation_score(results)
                    results["selection_score"] = score
                    last_evaluation = results
                    self.tracker.log("evaluation", global_step, results, context)
                    health_metrics = {
                        "evaluation_win_rate": float(results["win_rate"]),
                        "evaluation_wilson_lower": float(results["wilson_lower"]),
                    }
                    if results["anchors"]:
                        health_metrics["historical_win_rate"] = min(
                            float(item["win_rate"]) for item in results["anchors"].values())
                    self._observe_health(global_step, health_metrics, update)
                    self._save("latest.pt", global_step, results, update)
                    if (evaluated_stage_index > self.best_stage_index
                            or (evaluated_stage_index == self.best_stage_index
                                and score > self.best_win_rate)):
                        self.best_stage_index = evaluated_stage_index
                        self.best_win_rate = score
                        self._save("best.pt", global_step, results, update)
                    print(json.dumps({"update": update, "steps": global_step,
                                      "stage": self.curriculum.current.name, **results},
                                     ensure_ascii=False))
                    # A shared backend lets evaluation replace environment
                    # zero's partial match, so the whole vector is reset.
                    if self.evaluation_env in self.training_envs:
                        observations, infos = self._reset_training_episodes(
                            list(range(self.num_envs)))
                self._after_training_update(global_step, update, episodes, evaluation_result)
            if updates_to_run:
                # Preserve the most recent evaluation in the terminal checkpoint.
                # This final save is still required when the last update is not an
                # evaluation/checkpoint boundary.
                self._save("latest.pt", global_step, last_evaluation, final_update)
        finally:
            if self._rollout_executor is not None:
                self._rollout_executor.shutdown(wait=True)
            self._rollout_executor = None
            self.tracker.close()
            self._close_training_envs()

    def _reset_training_episodes(self, indices: list[int], initial: bool = False,
                                 sampled_gods: dict[str, int] | None = None,
                                 sampled_terrains: dict[str, int] | None = None,
                                 terrain_attempts: list[int] | None = None):
        """Configure seeds before dispatching independent reset requests."""
        if self.batch_env is not None:
            seeds: list[int] = []
            opponents: list[Any] = []
            agent_players: list[int] = []
            options_batch: list[dict[str, Any] | None] = []
            requested_terrains: list[int | None] = []
            for index in indices:
                opponent = self._training_opponent()
                agent_player = int(self.rng.integers(1, 3))
                seed = (int(self.config["seed"]) + index if initial
                        else int(self.rng.integers(1, 2**31 - 1)))
                scenario_index = self.curriculum.sample_scenario_index(
                    self.scenarios, self.rng)
                god = str(self.scenarios[scenario_index]["god"])
                target_terrain = self.curriculum.sample_blocked_count(self.rng)
                if sampled_gods is not None:
                    sampled_gods[god] = sampled_gods.get(god, 0) + 1
                options = self._training_scenario_options(
                    scenario_index, agent_player,
                    blocked=self._sample_training_blocked(target_terrain))
                assert options is not None
                seeds.append(seed)
                opponents.append(opponent)
                agent_players.append(agent_player)
                options_batch.append(options)
                requested_terrains.append(target_terrain)
            observations, infos = self.batch_env.reset_many(
                indices, seeds=seeds, opponents=opponents,
                agent_players=agent_players, options=options_batch)
            for target_terrain, info in zip(
                    requested_terrains, infos, strict=True):
                if (target_terrain is not None
                        and len(info.get("blocked", [])) != target_terrain):
                    raise RuntimeError("le terrain force ne respecte pas le curriculum")
                if sampled_terrains is not None:
                    terrain = str(len(info.get("blocked", [])))
                    sampled_terrains[terrain] = sampled_terrains.get(terrain, 0) + 1
            return observations, infos
        requests: list[tuple[SamStoneEnv, list[int], dict | None, int | None, str]] = []
        for index in indices:
            env = self.training_envs[index]
            env.opponent = self._training_opponent()
            env.agent_player = int(self.rng.integers(1, 3))
            seed = (int(self.config["seed"]) + index if initial
                    else int(self.rng.integers(1, 2**31 - 1)))
            scenario_index = self.curriculum.sample_scenario_index(self.scenarios, self.rng)
            god = str(self.scenarios[scenario_index]["god"])
            target_terrain = self.curriculum.sample_blocked_count(self.rng)
            if sampled_gods is not None:
                sampled_gods[god] = sampled_gods.get(god, 0) + 1
            requests.append((env, [seed], self._training_scenario_options(
                scenario_index, env.agent_player,
                blocked=self._sample_training_blocked(target_terrain)), target_terrain, god))
        executor = getattr(self, "_rollout_executor", None)
        if executor is None:
            with ThreadPoolExecutor(max_workers=len(requests)) as temporary_executor:
                responses = list(temporary_executor.map(
                    lambda request: self._reset_env_for_terrain(
                        request[0], request[1], request[2], request[3]), requests))
        else:
            responses = list(executor.map(
                lambda request: self._reset_env_for_terrain(
                    request[0], request[1], request[2], request[3]), requests))
        if sampled_terrains is not None or terrain_attempts is not None:
            for _obs, info, attempts in responses:
                if sampled_terrains is not None:
                    terrain = str(len(info.get("blocked", [])))
                    sampled_terrains[terrain] = sampled_terrains.get(terrain, 0) + 1
                if terrain_attempts is not None:
                    terrain_attempts[0] += attempts
        return [item[0] for item in responses], [item[1] for item in responses]

    def _step_training_envs(self, actions: list[int]):
        if self.batch_env is not None:
            return self.batch_env.step(actions)
        requests = zip(self.training_envs, actions, strict=True)
        executor = getattr(self, "_rollout_executor", None)
        if executor is None:
            with ThreadPoolExecutor(max_workers=self.num_envs) as temporary_executor:
                return list(temporary_executor.map(
                    lambda request: request[0].step(request[1]), requests))
        return list(executor.map(lambda request: request[0].step(request[1]), requests))

    def _gae_vectorized(self, storage: dict[str, torch.Tensor], next_values: torch.Tensor,
                        steps: int) -> tuple[torch.Tensor, torch.Tensor]:
        rewards = storage["rewards"].reshape(steps, self.num_envs)
        values = storage["values"].reshape(steps, self.num_envs)
        dones = storage["dones"].reshape(steps, self.num_envs)
        advantages = torch.zeros_like(rewards)
        last = torch.zeros(self.num_envs, device=self.device)
        ppo = self.config["ppo"]
        for index in reversed(range(steps)):
            nonterminal = 1.0 - dones[index]
            following = next_values if index == steps - 1 else values[index + 1]
            delta = rewards[index] + ppo["gamma"] * following * nonterminal - values[index]
            last = delta + ppo["gamma"] * ppo["gae_lambda"] * nonterminal * last
            advantages[index] = last
        flattened = advantages.reshape(-1)
        return flattened, flattened + storage["values"]

    def _close_training_envs(self) -> None:
        if self.batch_env is not None:
            self.batch_env.close()
            self.env.close()
        elif self.training_envs:
            with ThreadPoolExecutor(max_workers=len(self.training_envs)) as executor:
                list(executor.map(lambda env: env.close(), self.training_envs))
        extra = [env for env in self.evaluation_envs if env not in self.training_envs]
        if extra:
            with ThreadPoolExecutor(max_workers=len(extra)) as executor:
                list(executor.map(lambda env: env.close(), extra))

    def _run_bootstrap_evaluation(self) -> dict[str, Any] | None:
        """Skip already-solved early stages without changing the policy.

        This is only enabled for the official phase-4 run.  Every stage still
        needs the usual number of independent held-out confirmations; the
        difference is that they are run consecutively before PPO collection.
        At the first failed confirmation we persist the current curriculum and
        return to normal training on that exact stage.
        """
        settings = self.config.get("curriculum", {}).get("bootstrap_evaluation", {})
        if (not bool(settings.get("enabled", False))
                or self.curriculum.bootstrap_evaluation_completed):
            return None
        seed_stride = int(settings.get("seed_stride", 100000))
        attempt = 0
        last_result: dict[str, Any] | None = None
        while not self.curriculum.awaiting_final_validation and not self.curriculum.completed:
            evaluated_stage_index = self.curriculum.stage_index
            evaluated_stage = self.curriculum.current.name
            attempt += 1
            started = time.perf_counter()
            results = self.evaluate(seed_offset=attempt * seed_stride)
            evaluation_seconds = max(time.perf_counter() - started, 1e-9)
            evaluated_games = int(results["games"]) + sum(
                int(item["games"]) for item in results["anchors"].values())
            results["evaluation_seconds"] = evaluation_seconds
            results["games_per_second"] = evaluated_games / evaluation_seconds
            promoted = self.curriculum.consider_promotion(
                int(results["wins"]), int(results["games"]), int(results["draws"]))
            promotion = self.curriculum.promotion_metrics(
                int(results["wins"]), int(results["draws"]), int(results["games"]))
            results.update({
                "promotion": promotion,
                "promoted": promoted,
                "evaluated_stage_index": evaluated_stage_index,
                "next_stage_index": self.curriculum.stage_index,
                "selection_score": self._evaluation_score(results),
                "bootstrap": {
                    "enabled": True,
                    "attempt": attempt,
                    "seed_offset": attempt * seed_stride,
                    "stage": evaluated_stage,
                    "eligible": bool(promotion["eligible"]),
                },
            })
            results["promotion"]["consecutive_promotion_successes"] = (
                self.curriculum.consecutive_promotion_successes)
            if sampling := self.curriculum.update_god_sampling(results["by_god"]):
                results["god_sampling"] = sampling
            if sampling := self.curriculum.update_terrain_sampling(results["by_blocked_count"]):
                results["terrain_sampling"] = sampling
            context = {
                "update": 0,
                "stage": evaluated_stage,
                "phase_five_ready": self.curriculum.phase_five_ready,
                "environment_count": self.num_envs,
                "bootstrap_evaluation": True,
                "bootstrap_attempt": attempt,
            }
            self.tracker.log("evaluation", 0, results, context)
            self._observe_health(0, {
                "evaluation_win_rate": float(results["win_rate"]),
                "evaluation_wilson_lower": float(results["wilson_lower"]),
            }, 0)
            score = float(results["selection_score"])
            if (evaluated_stage_index > self.best_stage_index
                    or (evaluated_stage_index == self.best_stage_index
                        and score > self.best_win_rate)):
                self.best_stage_index = evaluated_stage_index
                self.best_win_rate = score
                self._save("best.pt", 0, results, 0)
            # Persist every confirmation. Ctrl+C or a Godot interruption can
            # therefore resume the scan at the exact remaining confirmation.
            self._save("latest.pt", 0, results, 0)
            print(json.dumps({"update": 0, "steps": 0, "stage": evaluated_stage,
                              "bootstrap_evaluation": True, **results}, ensure_ascii=False))
            last_result = results
            if not bool(promotion["eligible"]):
                break
            if promoted:
                continue
            # The evaluation passed but a further independent confirmation is
            # needed for this same stage.
        self.curriculum.complete_bootstrap_evaluation()
        if last_result is not None:
            self._save("latest.pt", 0, last_result, 0)
        return last_result

    def evaluate(self, seed_offset: int = 0) -> dict[str, Any]:
        evaluation = self.config["evaluation"]
        games, wins, draws = int(evaluation["games"]), 0, 0
        margins: list[float] = []
        turns: list[float] = []
        buckets: dict[str, dict[str, list[tuple[bool, bool, float]]]] = {
            "by_god": defaultdict(list),
            "by_agent_side": defaultdict(list),
            "by_start_order": defaultdict(list),
            "by_blocked_count": defaultdict(list),
        }
        chunks = [list(range(worker, games, self.evaluation_num_envs))
                  for worker in range(self.evaluation_num_envs)]
        if self.evaluation_num_envs == 1:
            completed = self._evaluate_offsets(
                self.evaluation_envs[0], chunks[0], int(evaluation["seed_base"]) + seed_offset)
        else:
            with ThreadPoolExecutor(max_workers=self.evaluation_num_envs) as executor:
                batches = executor.map(
                    lambda request: self._evaluate_offsets(*request),
                    zip(self.evaluation_envs, chunks,
                        [int(evaluation["seed_base"]) + seed_offset] * len(chunks), strict=True))
                completed = [item for batch in batches for item in batch]
        for offset, agent_player, first_player, final_info in sorted(completed):
            winner = int(final_info["winner"])
            episode = final_info["episode"]
            margin = float(episode["margin"])
            outcome = (winner == agent_player, winner == 0, margin)
            wins += int(winner == agent_player)
            draws += int(winner == 0)
            margins.append(margin)
            turns.append(float(episode["turns"]))
            god = str(self.scenarios[offset % len(self.scenarios)]["god"])
            buckets["by_god"][god].append(outcome)
            buckets["by_agent_side"][f"player_{agent_player}"].append(outcome)
            order = "agent_first" if first_player == agent_player else "opponent_first"
            buckets["by_start_order"][order].append(outcome)
            buckets["by_blocked_count"][str(episode["blocked_count"])].append(outcome)
        result = {
            "wins": wins,
            "draws": draws,
            "losses": games - wins - draws,
            "games": games,
            "win_rate": wins / games,
            "wilson_lower": wilson_lower(wins, games),
            "loss_rate": (games - wins - draws) / games,
            "non_loss_rate": (wins + draws) / games,
            "non_loss_wilson_lower": wilson_lower(wins + draws, games),
            "mean_margin": float(np.mean(margins)),
            "mean_turns": float(np.mean(turns)),
            **{name: {key: self._outcome_stats(values) for key, values in group.items()}
               for name, group in buckets.items()},
        }
        result["anchors"] = self._evaluate_anchors(seed_offset)
        return result

    def _evaluate_offsets(
            self, env: SamStoneEnv, offsets: list[int], seed_base: int,
    ) -> list[tuple[int, int, int, dict[str, Any]]]:
        evaluation = self.config["evaluation"]
        max_attempts = int(evaluation.get("godot_retry_attempts", 2))
        if max_attempts <= 0:
            raise ValueError("evaluation.godot_retry_attempts doit être strictement positif")
        previous, previous_player = env.opponent, env.agent_player
        completed: list[tuple[int, int, int, dict[str, Any]]] = []
        try:
            for offset in offsets:
                cycle = (offset // max(1, len(self.scenarios))) % 4
                agent_player = 1 if cycle < 2 else 2
                first_player = 1 if cycle % 2 == 0 else 2
                info = self._evaluation_game_with_retry(
                    self.curriculum.current.opponent(), offset % len(self.scenarios),
                    agent_player, first_player, seed_base + offset,
                    env, max_attempts)
                completed.append((offset, agent_player, first_player, info))
        finally:
            env.opponent, env.agent_player = previous, previous_player
        return completed

    def _evaluation_game_with_retry(self, opponent, scenario_index: int, agent_player: int,
                                    first_player: int, seed: int, env: SamStoneEnv,
                                    max_attempts: int) -> dict[str, Any]:
        """Restart one crashed Godot worker and replay its deterministic match."""
        failures: list[str] = []
        for attempt in range(1, max_attempts + 1):
            try:
                return self._evaluation_game(
                    opponent, scenario_index, agent_player, first_player, seed, env)
            except GodotProtocolError as exc:
                failures.append(str(exc))
                env.close()
                if attempt == max_attempts:
                    detail = "\n--- tentative suivante ---\n".join(failures)
                    raise GodotProtocolError(
                        f"évaluation Godot impossible après {max_attempts} tentatives "
                        f"(seed={seed}, scenario={scenario_index}).\n{detail}") from exc
        raise AssertionError("boucle de reprise d'évaluation inaccessible")

    def _evaluate_anchors(self, seed_offset: int = 0) -> dict[str, dict[str, float | int]]:
        evaluation = self.config["evaluation"]
        games = int(evaluation.get("anchor_games_per_stage", 0))
        if games <= 0 or self.curriculum.stage_index <= 0:
            return {}
        base_seed = int(evaluation.get(
            "anchor_seed_base", int(evaluation["seed_base"]) + 50000000)) + seed_offset
        anchors: dict[str, dict[str, float | int]] = {}
        env = self.evaluation_env
        previous = env.opponent
        previous_player = env.agent_player
        try:
            for stage_index, stage in enumerate(
                    self.curriculum.stages[:self.curriculum.stage_index]):
                outcomes: list[tuple[bool, bool, float]] = []
                for offset in range(games):
                    cycle = (offset // max(1, len(self.scenarios))) % 4
                    agent_player = 1 if cycle < 2 else 2
                    first_player = 1 if cycle % 2 == 0 else 2
                    final_info = self._evaluation_game(
                        stage.opponent(), offset % len(self.scenarios), agent_player,
                        first_player, base_seed + stage_index * 1000000 + offset)
                    episode = final_info["episode"]
                    winner = int(final_info["winner"])
                    outcomes.append((winner == agent_player, winner == 0,
                                     float(episode["margin"])))
                anchors[stage.name] = self._outcome_stats(outcomes)
        finally:
            env.opponent = previous
            env.agent_player = previous_player
        return anchors

    def run_final_gate(self) -> PhaseFourGateReport:
        if not self.curriculum.awaiting_final_validation:
            raise RuntimeError("le dernier palier doit etre battu avant la validation finale")
        settings = self.config["evaluation"]["final_gate"]
        games_per_slice = int(settings["games_per_slice"])
        seed = int(settings["seed_base"])
        slices: list[EvaluationSlice] = []
        env = self.evaluation_env
        previous = env.opponent
        previous_player = env.agent_player
        try:
            for stage in self.curriculum.stages:
                for scenario_index, scenario in enumerate(self.scenarios):
                    for agent_player in (1, 2):
                        for first_player in (1, 2):
                            wins = draws = 0
                            for _game in range(games_per_slice):
                                final_info = self._evaluation_game(
                                    stage.opponent(), scenario_index, agent_player, first_player, seed)
                                winner = int(final_info["winner"])
                                seed += 1
                                wins += int(winner == agent_player)
                                draws += int(winner == 0)
                            slices.append(EvaluationSlice(
                                stage.name, str(scenario["god"]), agent_player, first_player,
                                wins, draws, games_per_slice - wins - draws))
        finally:
            env.opponent = previous
            env.agent_player = previous_player
        report = PhaseFourGateReport.build(
            slices, (stage.name for stage in self.curriculum.stages),
            (str(scenario["god"]) for scenario in self.scenarios),
            overall_threshold=float(settings["overall_win_rate"]),
            confidence_floor=float(settings["confidence_floor"]),
            slice_floor=float(settings["minimum_slice_win_rate"]),
            minimum_games_per_slice=games_per_slice,
            maximum_loss_rate=self._optional_rate(settings, "maximum_loss_rate"),
            non_loss_confidence_floor=self._optional_rate(
                settings, "non_loss_confidence_floor"),
            maximum_slice_loss_rate=self._optional_rate(settings, "maximum_slice_loss_rate"),
        )
        self.curriculum.accept_final_validation(report.passed)
        gate_path = self.output / "phase4_gate.json"
        gate_temporary = gate_path.with_suffix(".json.tmp")
        gate_temporary.write_text(
            json.dumps(report.to_dict(), indent=2), encoding="utf-8")
        gate_temporary.replace(gate_path)
        return report

    @staticmethod
    def _optional_rate(settings: dict[str, Any], key: str) -> float | None:
        value = settings.get(key)
        return None if value is None else float(value)

    def _evaluation_game(self, opponent, scenario_index: int, agent_player: int,
                         first_player: int, seed: int,
                         env: SamStoneEnv | None = None,
                         options_override: dict | None = None) -> dict:
        env = env or self.evaluation_env
        env.opponent = opponent
        env.agent_player = agent_player
        options = (options_override if options_override is not None
                   else self._scenario_options(scenario_index, evaluation=True))
        if options is not None:
            options["config"]["first_player"] = first_player
        obs, info = env.reset(seed=seed, options=options)
        done = False
        while not done:
            with torch.no_grad():
                feature_args = self._evaluation_action_feature_args(info)
                action_features = feature_args[0] if feature_args else None
                action, _, _ = self._act(
                    torch.as_tensor(obs, dtype=torch.float32, device=self.device).unsqueeze(0),
                    torch.as_tensor(info["action_mask"], dtype=torch.bool,
                                    device=self.device).unsqueeze(0),
                    action_features, True)
            obs, _, terminated, truncated, info = env.step(int(action.item()))
            done = terminated or truncated
        return info

    @staticmethod
    def _reset_env_for_terrain(env: SamStoneEnv, seeds: list[int], options: dict | None,
                               target_terrain: int | None):
        """Resample only reset seeds; the policy never receives rejected states."""
        if not seeds:
            raise ValueError("au moins un seed est requis pour reset")
        observation = None
        info: dict[str, Any] = {}
        for attempts, seed in enumerate(seeds):
            observation, info = env.reset(seed=seed, options=options)
            if target_terrain is None or len(info.get("blocked", [])) == target_terrain:
                return observation, info, attempts
        assert observation is not None
        return observation, info, len(seeds) - 1

    def _scenario_options(self, index: int, evaluation: bool = False) -> dict | None:
        if not self.scenarios:
            return None
        scenario = dict(self.scenarios[index % len(self.scenarios)])
        deck = list(scenario.pop("deck"))
        god = str(scenario.pop("god"))
        scenario.update({"human_deck": deck, "ai_deck": deck, "human_god": god, "ai_god": god})
        if evaluation:
            cycle = (index // len(self.scenarios)) % 4
            scenario["first_player"] = 1 if cycle % 2 == 0 else 2
        return {"config": scenario}

    def _training_opponent(self):
        return self.curriculum.training_stage(self.rng).opponent()

    def _sample_training_blocked(self, count: int | None) -> list[list[int]] | None:
        """Draw the requested terrain directly instead of rejecting seeded resets.

        ``None`` preserves the ordinary random-terrain behavior when adaptive
        terrain sampling is disabled. Explicit cells remain diverse and are
        fully reproducible because ``self.rng`` is checkpointed.
        """
        if count is None:
            return None
        if not 0 <= count <= 2:
            raise ValueError("le curriculum ne peut demander que 0, 1 ou 2 cases bloquees")
        cells = sorted(int(value) for value in self.rng.choice(16, size=count, replace=False))
        return [[cell // 4, cell % 4] for cell in cells]

    def _training_scenario_options(self, scenario_index: int, agent_player: int,
                                   blocked: list[list[int]] | None = None) -> dict | None:
        del agent_player
        options = self._scenario_options(scenario_index)
        if options is not None and blocked is not None:
            options["config"]["blocked"] = blocked
        return options

    def _after_training_update(self, global_step: int, update: int,
                               episodes: list[dict], evaluation: dict | None) -> None:
        del global_step, update, episodes, evaluation

    def _evaluation_score(self, results: dict[str, Any]) -> float:
        return float(results["win_rate"])

    def _checkpoint_extra(self) -> dict[str, Any]:
        return {}

    def _empty_storage(self, steps: int) -> dict[str, Any]:
        obs_dim, action_dim = self.env.observation_space.shape[0], self.env.action_space.n
        storage = {"obs": torch.zeros((steps, obs_dim), device=self.device),
                "masks": torch.zeros((steps, action_dim), dtype=torch.bool, device=self.device),
                "actions": torch.zeros(steps, dtype=torch.long, device=self.device),
                "log_probs": torch.zeros(steps, device=self.device), "values": torch.zeros(steps, device=self.device),
                "rewards": torch.zeros(steps, device=self.device), "dones": torch.zeros(steps, device=self.device)}
        if self.tactical_features_enabled:
            storage["action_features"] = torch.zeros(
                (steps, action_dim, self.tactical_feature_dim), device=self.device)
        return storage

    def _optimize(self, storage, advantages, returns) -> dict[str, float]:
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
                batch_index = torch.as_tensor(
                    batch, dtype=torch.long, device=self.device)
                if self.tactical_features_enabled:
                    assert isinstance(self.model, TacticalActorCritic)
                    new_log_prob, entropy, value = self.model.evaluate_actions(
                        storage["obs"][batch_index], storage["masks"][batch_index],
                        storage["action_features"][batch_index],
                        storage["actions"][batch_index])
                else:
                    assert isinstance(self.model, ActorCritic)
                    new_log_prob, entropy, value = self.model.evaluate_actions(
                        storage["obs"][batch_index], storage["masks"][batch_index],
                        storage["actions"][batch_index])
                log_ratio = new_log_prob - storage["log_probs"][batch_index]
                ratio = log_ratio.exp()
                policy_loss = torch.maximum(-advantages[batch_index] * ratio,
                                            -advantages[batch_index] * ratio.clamp(
                                                1 - ppo["clip_coef"],
                                                1 + ppo["clip_coef"])).mean()
                value_loss = 0.5 * (value - returns[batch_index]).pow(2).mean()
                loss = policy_loss + ppo["value_coef"] * value_loss - ppo["entropy_coef"] * entropy.mean()
                auxiliary_batch_loss: torch.Tensor | None = None
                auxiliary_batch_mae: torch.Tensor | None = None
                if self.auxiliary_head is not None:
                    cpu_mask = storage["auxiliary_mask"][batch]
                    selected_positions = np.flatnonzero(cpu_mask)
                    if len(selected_positions):
                        selected = torch.as_tensor(
                            selected_positions, dtype=torch.long, device=self.device)
                        selected_indices = batch_index[selected]
                        predictions = self.auxiliary_head(
                            self.model.encode_state(storage["obs"][selected_indices]))
                        targets = torch.as_tensor(
                            storage["auxiliary_targets"][batch[selected_positions]],
                            dtype=torch.float32, device=self.device)
                        auxiliary_batch_loss = auxiliary_loss(
                            predictions, targets, self.auxiliary_config.loss)
                        auxiliary_batch_mae = (predictions - targets).abs().mean()
                        loss = loss + self.auxiliary_config.coefficient * auxiliary_batch_loss
                self.optimizer.zero_grad(set_to_none=True)
                if self.auxiliary_optimizer is not None:
                    self.auxiliary_optimizer.zero_grad(set_to_none=True)
                loss.backward()
                gradient_norm = nn.utils.clip_grad_norm_(self.model.parameters(), ppo["max_grad_norm"])
                if self.auxiliary_head is not None:
                    nn.utils.clip_grad_norm_(
                        self.auxiliary_head.parameters(), ppo["max_grad_norm"])
                self.optimizer.step()
                if auxiliary_batch_loss is not None:
                    assert self.auxiliary_optimizer is not None
                    self.auxiliary_optimizer.step()
                legal_counts = storage["masks"][batch_index].sum(
                    dim=-1).clamp_min(2).float()
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
                    collected["auxiliary_margin_loss"].append(
                        float(auxiliary_batch_loss.detach()))
                    collected["auxiliary_margin_mae"].append(
                        float(auxiliary_batch_mae.detach()))
            epochs_used += 1
            epoch_metrics = len(np.array_split(indices, int(ppo["minibatches"])))
            epoch_kl = float(np.mean(collected["approx_kl"][-epoch_metrics:]))
            if (epochs_used >= min_epochs and target_kl > 0.0 and epoch_kl > target_kl
                    and epochs_used < max_epochs):
                stopped_early = True
                break
        with torch.no_grad():
            fitted_values = self.model.value(storage["obs"])
        return_variance = (returns - returns.mean()).square().mean()
        residual = returns - fitted_values
        residual_variance = (residual - residual.mean()).square().mean()
        explained = (1.0 - residual_variance / return_variance
                     if float(return_variance) > 1e-12 else torch.tensor(0.0, device=self.device))
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
            predictions = self.auxiliary_head(
                self.model.encode_state(storage["obs"][device_indices])).detach().cpu().numpy()
        targets = np.asarray(storage["auxiliary_targets"], dtype=np.float32)[indices]
        prediction_std = float(np.std(predictions))
        target_std = float(np.std(targets))
        correlation = (float(np.corrcoef(predictions, targets)[0, 1])
                       if len(indices) > 1 and prediction_std > 1e-8 and target_std > 1e-8
                       else 0.0)
        return {
            "auxiliary_margin_samples": float(len(indices)),
            "auxiliary_margin_mae": float(np.mean(np.abs(predictions - targets))),
            "auxiliary_margin_correlation": correlation,
        }

    def _rollout_metrics(self, storage: dict[str, torch.Tensor], advantages: torch.Tensor,
                         returns: torch.Tensor, episodes: list[dict],
                         capture_rewards: list[float], terminal_rewards: list[float],
                         final_margin_rewards: list[float],
                         control_delta_rewards: list[float],
                         steps_per_second: float) -> dict[str, float]:
        update_seconds = len(storage["rewards"]) / max(steps_per_second, 1e-9)
        metrics = {
            "rollout_reward_mean": float(storage["rewards"].mean()),
            "rollout_reward_std": float((
                storage["rewards"] - storage["rewards"].mean()).square().mean().sqrt()),
            "capture_reward_mean": float(np.mean(capture_rewards)),
            "terminal_reward_mean": float(np.mean(terminal_rewards)),
            "final_margin_reward_mean": float(np.mean(final_margin_rewards)),
            "control_delta_reward_mean": float(np.mean(control_delta_rewards)),
            "advantage_mean": float(advantages.mean()),
            "advantage_std": float((
                advantages - advantages.mean()).square().mean().sqrt()),
            "return_mean": float(returns.mean()),
            "value_mean": float(storage["values"].mean()),
            "steps_per_second": float(steps_per_second),
            "update_seconds": float(update_seconds),
            "training_games_per_second": float(len(episodes) / update_seconds),
            "episodes_completed": float(len(episodes)),
            "illegal_actions": 0.0,
        }
        if episodes:
            metrics.update({
                "episode_return_mean": float(np.mean([item["return"] for item in episodes])),
                "episode_return_std": float(np.std([item["return"] for item in episodes])),
                "episode_turns_mean": float(np.mean([item["turns"] for item in episodes])),
                "episode_margin_mean": float(np.mean([item["margin"] for item in episodes])),
                "training_win_rate": float(np.mean([item["won"] for item in episodes])),
                "training_draw_rate": float(np.mean([item["draw"] for item in episodes])),
                "agent_captures_mean": float(np.mean(
                    [item["agent_captures"] for item in episodes])),
                "opponent_captures_mean": float(np.mean(
                    [item["opponent_captures"] for item in episodes])),
            })
        return metrics

    def _resource_metrics(self) -> dict[str, float]:
        metrics = {
            "memory_rss_mb": self.process.memory_info().rss / (1024.0 * 1024.0),
            "process_cpu_percent": self.process.cpu_percent(None),
        }
        worker_pids = {
            item.pid for env in self.training_envs
            if (item := env.bridge.process) is not None
            and hasattr(item, "poll") and item.poll() is None
        }
        self._simulator_processes = {
            pid: process for pid, process in self._simulator_processes.items() if pid in worker_pids}
        worker_stats: list[psutil.Process] = []
        for pid in worker_pids:
            try:
                worker_stats.append(self._simulator_processes.setdefault(pid, psutil.Process(pid)))
            except psutil.Error:
                continue
        if worker_stats:
            metrics["simulator_workers"] = float(len(worker_stats))
            try:
                metrics["simulator_rss_mb"] = float(sum(
                    item.memory_info().rss for item in worker_stats) / (1024.0 * 1024.0))
                # ``cpu_percent(None)`` needs a previous sample. Keeping the
                # psutil objects makes the first value a warm-up and every
                # following rollout an actual interval measurement.
                metrics["simulator_cpu_percent"] = float(sum(
                    item.cpu_percent(None) for item in worker_stats))
            except psutil.Error:
                pass
        if self.device.type == "cuda" and torch.cuda.is_available():
            metrics["gpu_memory_allocated_mb"] = torch.cuda.memory_allocated(
                self.device) / (1024.0 * 1024.0)
            metrics["gpu_memory_reserved_mb"] = torch.cuda.memory_reserved(
                self.device) / (1024.0 * 1024.0)
        return metrics

    @staticmethod
    def _outcome_stats(values: list[tuple[bool, bool, float]]) -> dict[str, float | int]:
        games = len(values)
        wins = sum(item[0] for item in values)
        draws = sum(item[1] for item in values)
        return {
            "games": games,
            "wins": wins,
            "draws": draws,
            "losses": games - wins - draws,
            "win_rate": wins / games,
            "wilson_lower": wilson_lower(wins, games),
            "loss_rate": (games - wins - draws) / games,
            "non_loss_rate": (wins + draws) / games,
            "non_loss_wilson_lower": wilson_lower(wins + draws, games),
            "mean_margin": float(np.mean([item[2] for item in values])),
        }

    def _observe_health(self, global_step: int, metrics: dict[str, Any], update: int) -> None:
        alerts = self.health.check(global_step, metrics)
        for alert in alerts:
            self.tracker.log_alert(alert.to_dict())
            print(json.dumps({"alert": alert.to_dict()}, ensure_ascii=False))
        critical = self.health.critical(alerts)
        if critical:
            self._save("diagnostic_non_finite.pt", global_step, {}, update)
            raise TrainingHealthError(critical)

    def _record_engine_manifest(self) -> None:
        if self._manifest_has_engine:
            return
        manifests = ([self.batch_env.engine_manifest()] if self.batch_env is not None
                     else [env.bridge.engine_manifest() for env in self.training_envs])
        manifest = manifests[0]
        engine_checksum = hashlib.sha256(json.dumps(
            manifest, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        worker_checksums = [hashlib.sha256(json.dumps(
            item, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            for item in manifests]
        if any(item != engine_checksum for item in worker_checksums):
            raise RuntimeError("les processus Godot ne partagent pas le meme manifeste moteur")
        self.tracker.update_manifest(
            checksums={
                "engine": engine_checksum,
                "catalog": str(manifest.get("catalogue_checksum", "")),
            },
            extra={"engine_manifest": manifest, "environment_count": self.num_envs,
                   "training_backend": self.training_backend,
                   "evaluation_backend": self.evaluation_backend,
                   "worker_engine_checksums": worker_checksums})
        self._manifest_has_engine = True

    def _save(self, name: str, global_step: int, evaluation: dict,
              update: int = 0) -> None:
        target = self.output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_suffix(target.suffix + ".tmp")
        payload = {
            "model": self.model.state_dict(),
            "optimizer": self.optimizer.state_dict(),
            "global_step": int(global_step),
            "update": int(update),
            "curriculum": self.curriculum.state_dict(),
            "evaluation": evaluation,
            "best_win_rate": self.best_win_rate,
            "best_stage_index": self.best_stage_index,
            "config": self.config,
            "rng": {
                "numpy": self.rng.bit_generator.state,
                "torch": torch.get_rng_state(),
            },
            **self._checkpoint_extra(),
        }
        if self.auxiliary_head is not None:
            assert self.auxiliary_optimizer is not None
            payload["auxiliary"] = {
                "model": self.auxiliary_head.state_dict(),
                "optimizer": self.auxiliary_optimizer.state_dict(),
                "target": "final_board_margin",
            }
        if torch.cuda.is_available():
            payload["rng"]["torch_cuda"] = torch.cuda.get_rng_state_all()
        if self.device.type == "privateuseone":
            payload = self._checkpoint_to_cpu(payload)
        torch.save(payload, temporary)
        temporary.replace(target)
        checksum = self._file_checksum(target)
        checksum_path = target.with_suffix(target.suffix + ".sha256")
        checksum_temporary = checksum_path.with_suffix(checksum_path.suffix + ".tmp")
        checksum_temporary.write_text(f"{checksum}  {target.name}\n", encoding="ascii")
        checksum_temporary.replace(checksum_path)

    def load_checkpoint(self, path: str | Path, load_optimizer: bool = True,
                        load_training_state: bool = True) -> dict:
        checkpoint_path = Path(path).resolve()
        checksum_path = checkpoint_path.with_suffix(checkpoint_path.suffix + ".sha256")
        if checksum_path.is_file():
            expected = checksum_path.read_text(encoding="ascii").split()[0]
            actual = self._file_checksum(checkpoint_path)
            if actual != expected:
                raise RuntimeError(f"checksum invalide pour {checkpoint_path}")
        # torch-directml cannot currently be passed directly as map_location.
        # Loading on CPU is portable; load_state_dict then copies tensors to
        # the model and optimizer device.
        load_device = "cpu" if self.device.type == "privateuseone" else self.device
        checkpoint = torch.load(checkpoint_path, map_location=load_device, weights_only=False)
        if not load_training_state and isinstance(self.model, TacticalActorCritic):
            try:
                self.model.load_state_dict(checkpoint["model"])
            except RuntimeError:
                transferred = self.model.import_legacy_state(checkpoint["model"])
                print(json.dumps({"weights_imported": list(transferred),
                                  "actor_initialized": "tactical"}))
        else:
            self.model.load_state_dict(checkpoint["model"])
        if load_optimizer and "optimizer" in checkpoint:
            self.optimizer.load_state_dict(checkpoint["optimizer"])
        auxiliary = checkpoint.get("auxiliary")
        auxiliary_head = getattr(self, "auxiliary_head", None)
        if auxiliary_head is not None and isinstance(auxiliary, dict):
            auxiliary_head.load_state_dict(auxiliary["model"])
            if load_optimizer and self.auxiliary_optimizer is not None:
                auxiliary_optimizer = auxiliary.get("optimizer")
                if auxiliary_optimizer is not None:
                    self.auxiliary_optimizer.load_state_dict(auxiliary_optimizer)
        if not load_training_state:
            return checkpoint
        curriculum = checkpoint.get("curriculum", {})
        self.curriculum.load_state_dict(curriculum)
        self.best_win_rate = float(checkpoint.get(
            "best_win_rate", checkpoint.get("evaluation", {}).get("win_rate", -1.0)))
        self.best_stage_index = int(checkpoint.get(
            "best_stage_index", checkpoint.get("evaluation", {}).get(
                "evaluated_stage_index", -1)))
        self._resume_global_step = int(checkpoint.get("global_step", 0))
        batch_size = (int(self.config["ppo"]["rollout_steps"])
                      * int(self.config["ppo"].get("num_envs", 1)))
        self._resume_update = int(checkpoint.get(
            "update", self._resume_global_step // max(1, batch_size)))
        rng = checkpoint.get("rng", {})
        if "numpy" in rng:
            self.rng.bit_generator.state = rng["numpy"]
        if "torch" in rng:
            torch.set_rng_state(rng["torch"].cpu())
        if torch.cuda.is_available() and "torch_cuda" in rng:
            torch.cuda.set_rng_state_all(rng["torch_cuda"])
        return checkpoint

    @staticmethod
    def _file_checksum(path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        return digest.hexdigest()

    @classmethod
    def _checkpoint_to_cpu(cls, value: Any) -> Any:
        if isinstance(value, torch.Tensor):
            return value.detach().cpu()
        if isinstance(value, dict):
            return {key: cls._checkpoint_to_cpu(item) for key, item in value.items()}
        if isinstance(value, list):
            return [cls._checkpoint_to_cpu(item) for item in value]
        if isinstance(value, tuple):
            return tuple(cls._checkpoint_to_cpu(item) for item in value)
        return value


def main(argv: list[str] | None = None) -> int:
    """Run the canonical PPO training command."""
    parser = argparse.ArgumentParser(description="Entraîne PPO avec suivi local de santé.")
    parser.add_argument("--config", type=Path,
                        default=Path(__file__).resolve().parents[3]
                        / "configs" / "ppo_phase4_tactical.yaml")
    parser.add_argument("--resume", type=Path)
    parser.add_argument("--reset-optimizer", action="store_true",
                        help="charge les poids et le curriculum, mais reinitialise Adam")
    parser.add_argument("--weights-only", action="store_true",
                        help="importe seulement les poids dans un nouveau run")
    arguments = parser.parse_args(argv)
    if arguments.weights_only and arguments.resume is None:
        parser.error("--weights-only exige --resume")
    if arguments.weights_only:
        config_path = arguments.config.resolve()
        with config_path.open(encoding="utf-8") as stream:
            configured_output = Path(yaml.safe_load(stream)["output_dir"])
        output = (configured_output if configured_output.is_absolute()
                  else config_path.parent.parent / configured_output)
        if any((output / name).exists() for name in ("latest.pt", "metrics.jsonl")):
            parser.error(
                "--weights-only initialise un nouveau run, mais le dossier contient deja "
                "un entrainement; utiliser --resume avec son latest.pt")
    trainer = PPOTrainer(arguments.config)
    if arguments.resume is not None:
        trainer.load_checkpoint(
            arguments.resume,
            load_optimizer=not arguments.reset_optimizer and not arguments.weights_only,
            load_training_state=not arguments.weights_only,
        )
    trainer.train()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
