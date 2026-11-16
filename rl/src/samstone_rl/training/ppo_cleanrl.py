from __future__ import annotations

import argparse
import json
import math
import os
import time
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack, redirect_stdout
from pathlib import Path
from threading import Lock
from typing import Any

import numpy as np
import psutil
import torch
import yaml

from samstone_rl.batch_engine import BatchSamStoneEnv
from samstone_rl.envs.samstone_env import RewardScheme, SamStoneEnv
from samstone_rl.models import ActorCritic, TacticalActorCritic
from samstone_rl.models.policy import build_policy
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
)
from samstone_rl.training.checkpointing import CheckpointMixin
from samstone_rl.training.curriculum import CurriculumManager, stages_from_config
from samstone_rl.training.evaluation import EvaluationMixin
from samstone_rl.training.optimization import PPOOptimizer
from samstone_rl.training.rollout import RolloutMixin
from samstone_rl.training.validation import (
    wilson_lower,
)
from samstone_rl.utils.device import resolve_torch_device
from samstone_rl.utils.optim import DirectMLAdam
from samstone_rl.utils.provenance import provenance
from samstone_rl.utils.run_lock import RunLock
from samstone_rl.utils.seeding import set_seed


class PPOTrainer(RolloutMixin, EvaluationMixin, CheckpointMixin):
    def __init__(
        self,
        config_path: str | Path,
        output_override: str | Path | None = None,
        *,
        mode: str = "create",
    ) -> None:
        self._resources = ExitStack()
        self._rollout_executor = None
        try:
            self._initialize(config_path, output_override, mode)
        except BaseException:
            self.close()
            raise

    def __enter__(self):
        return self

    def __exit__(self, *_exc):
        self.close()

    def close(self) -> None:
        executor = self._rollout_executor
        self._rollout_executor = None
        if executor is not None:
            executor.shutdown(wait=True)
        self._resources.close()

    def _initialize(
        self, config_path: str | Path, output_override: str | Path | None, mode: str
    ) -> None:
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
        self.output = (
            configured_output
            if configured_output.is_absolute()
            else config_path.parent.parent / configured_output
        )
        self.output.mkdir(parents=True, exist_ok=True)
        self._resources.callback(RunLock(self.output).close)
        if mode not in ("create", "resume", "evaluate"):
            raise ValueError("mode de run inconnu")
        if mode == "create" and any(
            (self.output / name).exists()
            for name in ("latest.pt", "best.pt", "metrics.jsonl", "run_manifest.json")
        ):
            raise ValueError("run deja initialise; utiliser --resume ou un nouveau output_dir")
        self.provenance = provenance()
        monitoring = self.config.get("monitoring", {})
        self.tracker = RunTracker(
            self.output, "ppo", tensorboard=bool(monitoring.get("tensorboard", True))
        )
        self._resources.callback(self.tracker.close)
        self.tracker.initialize_manifest(
            build_run_manifest(
                "ppo",
                self.config,
                config_path,
                seed,
                extra={
                    "device": str(self.device),
                    "observation": 1,
                    "action_space": 128,
                    "model_architecture": self.model_architecture,
                    "action_feature_size": (
                        self.tactical_feature_dim if self.tactical_features_enabled else 0
                    ),
                },
            ),
            mutable_config_paths=(
                ("ppo", "total_timesteps"),
                ("ppo", "learning_rate"),
                ("monitoring",),
                ("device",),
                ("environment", "godot_path"),
                ("environment", "profile_backend"),
                ("environment", "python_profile_workers"),
                ("curriculum", "promotion_win_rate"),
                ("curriculum", "maximum_loss_rate"),
                ("curriculum", "non_loss_confidence_floor"),
                ("evaluation", "final_gate", "overall_win_rate"),
                ("evaluation", "final_gate", "maximum_loss_rate"),
                ("evaluation", "final_gate", "non_loss_confidence_floor"),
            )
            if mode in ("resume", "evaluate")
            else (),
        )
        self.health = HealthMonitor(self.output, monitoring.get("alerts", {}))
        curriculum = self.config["curriculum"]
        self.curriculum = CurriculumManager(
            curriculum["promotion_win_rate"],
            curriculum["confidence_floor"],
            curriculum["replay_probability"],
            stages=stages_from_config(curriculum.get("stages")),
            god_sampling=curriculum.get("god_sampling"),
            terrain_sampling=curriculum.get("terrain_sampling"),
            maximum_loss_rate=curriculum.get("maximum_loss_rate"),
            non_loss_confidence_floor=curriculum.get("non_loss_confidence_floor"),
            promotion_confirmations=curriculum.get("promotion_confirmations", 1),
        )
        if self.curriculum.god_sampling_enabled:
            self.curriculum.initialize_god_sampling(
                [str(scenario["god"]) for scenario in self.scenarios]
            )
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
        self.evaluation_backend = str(
            environment.get(
                "evaluation_backend",
                "python" if self.training_backend == "python_batch" else self.training_backend,
            )
        )
        scalar_training_backend = (
            "python" if self.training_backend == "python_batch" else self.training_backend
        )
        self.env = self._make_env(scalar_training_backend)
        self.batch_env: BatchSamStoneEnv | None = None
        if self.training_backend == "python_batch":
            self.batch_env = BatchSamStoneEnv(
                self.num_envs,
                self.reward_scheme,
                tactical_features=self.tactical_features_enabled,
                vector_tactical=bool(environment.get("vector_tactical", True)),
                vector_effects=bool(environment.get("vector_effects", True)),
                tactical_workers=int(environment.get("tactical_workers", 1)),
                profile_backend=str(environment.get("profile_backend", "python")),
                profile_workers=int(environment.get("profile_workers", 10)),
                python_profile_workers=int(environment.get("python_profile_workers", 1)),
                godot_path=environment.get("godot_path"),
            )
            self._resources.callback(self.batch_env.close)
            self.training_envs: list[SamStoneEnv] = []
        else:
            # Environment zero may be shared with evaluation only when both
            # workflows deliberately select the same scalar backend.
            self.training_envs = [
                self.env,
                *[self._make_env(self.training_backend) for _ in range(self.num_envs - 1)],
            ]
        self.evaluation_env = (
            self.env
            if self.batch_env is None and self.evaluation_backend == self.training_backend
            else self._make_env(self.evaluation_backend)
        )
        self.evaluation_num_envs = int(self.config["evaluation"].get("num_envs", 1))
        self.evaluation_envs = [
            self.evaluation_env,
            *[self._make_env(self.evaluation_backend) for _ in range(self.evaluation_num_envs - 1)],
        ]
        self.model = build_policy(self.config, self.device)
        optimizer_type = DirectMLAdam if self.device.type == "privateuseone" else torch.optim.Adam
        self.optimizer = optimizer_type(
            self.model.parameters(), lr=self.config["ppo"]["learning_rate"], eps=1e-5
        )
        self.auxiliary_config = AuxiliaryConfig.from_mapping(self.config.get("auxiliary"))
        self.auxiliary_head: FinalMarginHead | None = None
        self.auxiliary_optimizer: torch.optim.Optimizer | None = None
        if self.auxiliary_config.enabled:
            self.auxiliary_head = FinalMarginHead(self.model.hidden_dim).to(self.device)
            auxiliary_lr = self.auxiliary_config.learning_rate or float(
                self.config["ppo"]["learning_rate"]
            )
            self.auxiliary_optimizer = optimizer_type(
                self.auxiliary_head.parameters(), lr=auxiliary_lr, eps=1e-5
            )
        self.best_win_rate = -1.0
        self.best_stage_index = -1
        self._resume_global_step = 0
        self._resume_update = 0
        self._manifest_has_engine = False
        self._evaluation_round = 0
        self._bootstrap_round = 0
        self._simulator_processes: dict[int, psutil.Process] = {}

    def _make_env(self, backend: str) -> SamStoneEnv:
        env = SamStoneEnv(
            godot_path=self.config["environment"].get("godot_path"),
            opponent=self.curriculum.current.opponent(),
            agent_player=1,
            reward_scheme=self.reward_scheme,
            backend=backend,
            tactical_features=self.tactical_features_enabled,
        )
        self._resources.callback(env.close)
        return env

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
            raise ValueError("environment.backend doit valoir 'godot', 'python' ou 'python_batch'")
        evaluation_backend = self.config["environment"].get(
            "evaluation_backend",
            "python" if training_backend == "python_batch" else training_backend,
        )
        if evaluation_backend not in ("godot", "python"):
            raise ValueError("environment.evaluation_backend doit valoir 'godot' ou 'python'")
        architecture = str(self.config.get("model", {}).get("architecture", "actor_critic"))
        if architecture not in ("actor_critic", "tactical_actor_critic"):
            raise ValueError("model.architecture inconnu")
        evaluation = self.config["evaluation"]
        if int(evaluation["games"]) <= 0 or int(evaluation["every_updates"]) <= 0:
            raise ValueError(
                "la fréquence et le nombre de matchs d'évaluation doivent être positifs"
            )
        if int(evaluation.get("num_envs", 1)) <= 0:
            raise ValueError("evaluation.num_envs doit etre strictement positif")
        if int(evaluation.get("confirmation_seed_stride", 10000)) < int(evaluation["games"]):
            raise ValueError("les echantillons de confirmation doivent etre disjoints")
        bootstrap = self.config.get("curriculum", {}).get("bootstrap_evaluation", {})
        if not isinstance(bootstrap, dict):
            raise TypeError("curriculum.bootstrap_evaluation doit etre un objet")
        if int(bootstrap.get("seed_stride", 100000)) <= 0:
            raise ValueError("curriculum.bootstrap_evaluation.seed_stride doit etre positif")

    def train(self) -> None:
        try:
            self._train_vectorized()
        finally:
            self.close()

    def _action_features_tensor(self, infos: list[dict[str, Any]]) -> torch.Tensor | None:
        if not self.tactical_features_enabled:
            return None
        missing = [index for index, info in enumerate(infos) if "action_features" not in info]
        if missing:
            raise RuntimeError(f"features tactiques absentes pour les slots {missing}")
        values = (
            self.batch_env.action_features
            if self.batch_env is not None and len(infos) == self.num_envs
            else np.asarray([info["action_features"] for info in infos], dtype=np.float32)
        )
        expected = (len(infos), self.env.action_space.n, self.tactical_feature_dim)
        if values.shape != expected:
            raise RuntimeError(f"lot tactique {values.shape}, dimensions attendues {expected}")
        return torch.as_tensor(values, dtype=torch.float32, device=self.device)

    def _act(
        self,
        observations: torch.Tensor,
        masks: torch.Tensor,
        action_features: torch.Tensor | None,
        deterministic: bool = False,
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        if self.tactical_features_enabled:
            if action_features is None or not isinstance(self.model, TacticalActorCritic):
                raise RuntimeError("modele tactique sans features d'action")
            return self.model.act(observations, masks, action_features, deterministic)
        if not isinstance(self.model, ActorCritic):
            raise TypeError("architecture de modele incoherente")
        return self.model.act(observations, masks, deterministic)

    def _train_vectorized(self) -> None:
        """Collect PPO experience from one or more independent environments.

        ``rollout_steps`` is the number of decisions per environment. The
        optimizer always receives ``rollout_steps * num_envs`` transitions.
        """
        ppo = self.config["ppo"]
        if self._resume_global_step >= int(ppo["total_timesteps"]):
            print(json.dumps({"training_complete": True, "steps": self._resume_global_step}))
            return
        steps = int(ppo["rollout_steps"])
        total = int(ppo["total_timesteps"])
        batch_size = steps * self.num_envs
        self._evaluation_manifest()
        self._rollout_executor = (
            None if self.batch_env is not None else ThreadPoolExecutor(max_workers=self.num_envs)
        )
        last_evaluation = self._run_bootstrap_evaluation()
        observations, infos = self._reset_training_episodes(
            list(range(self.num_envs)), initial=self._resume_update == 0
        )
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
                rollout = self._collect_rollout(observations, infos, steps, global_step, update)
                storage, profile = rollout.storage, rollout.profile
                observations, infos = rollout.observations, rollout.infos
                global_step, episodes = rollout.global_step, rollout.episodes
                phase_started = time.perf_counter()
                with torch.no_grad():
                    next_values = self.model.value(
                        torch.as_tensor(
                            np.asarray(observations), dtype=torch.float32, device=self.device
                        )
                    )
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
                metrics.update(
                    self._rollout_metrics(
                        storage,
                        advantages,
                        returns,
                        episodes,
                        rollout.capture_rewards,
                        rollout.terminal_rewards,
                        rollout.final_margin_rewards,
                        rollout.control_delta_rewards,
                        batch_size / elapsed,
                    )
                )
                metrics.update(self._resource_metrics())
                metrics.update(
                    {
                        "environment_count": float(self.num_envs),
                        "rollout_batch_size": float(batch_size),
                        "profile": dict(profile),
                    }
                )
                if self.batch_env is not None:
                    metrics["vector_engine"] = self.batch_env.vector_metrics(reset=True)
                if sampling := self.curriculum.god_sampling_metrics(rollout.sampled_gods):
                    metrics["god_sampling"] = sampling
                if sampling := self.curriculum.terrain_sampling_metrics(
                    rollout.sampled_terrains, rollout.terrain_attempts
                ):
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
                    self._save("latest.pt", global_step, last_evaluation or {}, update)
                if snapshot_every > 0 and update % snapshot_every == 0:
                    self._save(
                        f"checkpoints/step_{global_step:012d}.pt",
                        global_step,
                        last_evaluation or {},
                        update,
                    )

                evaluation_result = None
                if update % int(self.config["evaluation"]["every_updates"]) == 0:
                    evaluation_started = time.perf_counter()
                    self._evaluation_round += 1
                    results = self.evaluate(
                        seed_offset=self._evaluation_round
                        * int(self.config["evaluation"].get("confirmation_seed_stride", 10000))
                    )
                    results["evaluation_round"] = self._evaluation_round
                    evaluation_result = results
                    evaluation_seconds = max(time.perf_counter() - evaluation_started, 1e-9)
                    evaluated_games = int(results["games"]) + sum(
                        int(item["games"]) for item in results["anchors"].values()
                    )
                    for key in ("mixed_vs_phase4", "specialist_vs_universal"):
                        evaluated_games += int(results.get(key, {}).get("games", 0))
                    results["evaluation_seconds"] = evaluation_seconds
                    results["games_per_second"] = evaluated_games / evaluation_seconds
                    evaluated_stage_index = self.curriculum.stage_index
                    promoted = self.curriculum.consider_promotion(
                        int(results["wins"]), int(results["games"]), int(results["draws"])
                    )
                    results["promotion"] = self.curriculum.promotion_metrics(
                        int(results["wins"]), int(results["draws"]), int(results["games"])
                    )
                    results["promotion"]["consecutive_promotion_successes"] = (
                        self.curriculum.consecutive_promotion_successes
                    )
                    if sampling := self.curriculum.update_god_sampling(results["by_god"]):
                        results["god_sampling"] = sampling
                    if sampling := self.curriculum.update_terrain_sampling(
                        results["by_blocked_count"]
                    ):
                        results["terrain_sampling"] = sampling
                    results["promoted"] = promoted
                    results["evaluated_stage_index"] = evaluated_stage_index
                    results["next_stage_index"] = self.curriculum.stage_index
                    score = self._evaluation_score(results)
                    results["selection_score"] = score
                    last_evaluation = results
                    self.tracker.log("evaluation", global_step, results, context)
                    health_metrics = {
                        "evaluation_stage": str(context["stage"]),
                        "evaluation_win_rate": float(results["win_rate"]),
                        "evaluation_wilson_lower": float(results["wilson_lower"]),
                    }
                    if results["anchors"]:
                        health_metrics["historical_win_rate"] = min(
                            float(item["win_rate"]) for item in results["anchors"].values()
                        )
                    self._observe_health(global_step, health_metrics, update)
                    self._save("latest.pt", global_step, results, update)
                    if evaluated_stage_index > self.best_stage_index or (
                        evaluated_stage_index == self.best_stage_index
                        and score > self.best_win_rate
                    ):
                        self.best_stage_index = evaluated_stage_index
                        self.best_win_rate = score
                        self._save("best.pt", global_step, results, update)
                    print(
                        json.dumps(
                            {
                                "update": update,
                                "steps": global_step,
                                "stage": self.curriculum.current.name,
                                **results,
                            },
                            ensure_ascii=False,
                        )
                    )
                    # A shared backend lets evaluation replace environment
                    # zero's partial match, so the whole vector is reset.
                    if self.evaluation_env in self.training_envs:
                        observations, infos = self._reset_training_episodes(
                            list(range(self.num_envs))
                        )
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
            self.close()

    def _reset_training_episodes(
        self,
        indices: list[int],
        initial: bool = False,
        sampled_gods: dict[str, int] | None = None,
        sampled_terrains: dict[str, int] | None = None,
        terrain_attempts: list[int] | None = None,
    ):
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
                seed = (
                    int(self.config["seed"]) + index
                    if initial
                    else int(self.rng.integers(1, 2**31 - 1))
                )
                scenario_index = self.curriculum.sample_scenario_index(self.scenarios, self.rng)
                god = str(self.scenarios[scenario_index]["god"])
                target_terrain = self.curriculum.sample_blocked_count(self.rng)
                if sampled_gods is not None:
                    sampled_gods[god] = sampled_gods.get(god, 0) + 1
                options = self._training_scenario_options(
                    scenario_index,
                    agent_player,
                    blocked=self._sample_training_blocked(target_terrain),
                )
                assert options is not None
                seeds.append(seed)
                opponents.append(opponent)
                agent_players.append(agent_player)
                options_batch.append(options)
                requested_terrains.append(target_terrain)
            observations, infos = self.batch_env.reset_many(
                indices,
                seeds=seeds,
                opponents=opponents,
                agent_players=agent_players,
                options=options_batch,
            )
            for target_terrain, info in zip(requested_terrains, infos, strict=True):
                if target_terrain is not None and len(info.get("blocked", [])) != target_terrain:
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
            seed = (
                int(self.config["seed"]) + index
                if initial
                else int(self.rng.integers(1, 2**31 - 1))
            )
            scenario_index = self.curriculum.sample_scenario_index(self.scenarios, self.rng)
            god = str(self.scenarios[scenario_index]["god"])
            target_terrain = self.curriculum.sample_blocked_count(self.rng)
            if sampled_gods is not None:
                sampled_gods[god] = sampled_gods.get(god, 0) + 1
            requests.append(
                (
                    env,
                    [seed],
                    self._training_scenario_options(
                        scenario_index,
                        env.agent_player,
                        blocked=self._sample_training_blocked(target_terrain),
                    ),
                    target_terrain,
                    god,
                )
            )
        executor = getattr(self, "_rollout_executor", None)
        if executor is None:
            with ThreadPoolExecutor(max_workers=len(requests)) as temporary_executor:
                responses = list(
                    temporary_executor.map(
                        lambda request: self._reset_env_for_terrain(
                            request[0], request[1], request[2], request[3]
                        ),
                        requests,
                    )
                )
        else:
            responses = list(
                executor.map(
                    lambda request: self._reset_env_for_terrain(
                        request[0], request[1], request[2], request[3]
                    ),
                    requests,
                )
            )
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
                return list(
                    temporary_executor.map(lambda request: request[0].step(request[1]), requests)
                )
        return list(executor.map(lambda request: request[0].step(request[1]), requests))

    def _gae_vectorized(
        self, storage: dict[str, torch.Tensor], next_values: torch.Tensor, steps: int
    ) -> tuple[torch.Tensor, torch.Tensor]:
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
        if (
            not bool(settings.get("enabled", False))
            or self.curriculum.bootstrap_evaluation_completed
        ):
            return None
        seed_stride = int(settings.get("seed_stride", 100000))
        progress_every = max(1, int(settings.get("progress_every_games", 1)))
        attempt = self._bootstrap_round
        last_result: dict[str, Any] | None = None
        while not self.curriculum.awaiting_final_validation and not self.curriculum.completed:
            evaluated_stage_index = self.curriculum.stage_index
            evaluated_stage = self.curriculum.current.name
            attempt += 1
            self._bootstrap_round = attempt
            started = time.perf_counter()
            last_reported = 0
            progress_lock = Lock()

            def report_progress(completed: int, total: int) -> None:
                """Write a compact, thread-safe heartbeat for the initial Godot scan."""
                nonlocal last_reported
                if completed != total and completed % progress_every:
                    return
                with progress_lock:
                    if completed <= last_reported:
                        return
                    last_reported = completed
                    elapsed = max(time.perf_counter() - started, 1e-9)
                    metrics = {
                        "completed_games": completed,
                        "total_games": total,
                        "completion": completed / total,
                        "elapsed_seconds": elapsed,
                        "games_per_second": completed / elapsed,
                    }
                    context = {
                        "stage": evaluated_stage,
                        "bootstrap_attempt": attempt,
                        "bootstrap_evaluation": True,
                    }
                    self.tracker.log("bootstrap_progress", completed, metrics, context)
                    print(
                        json.dumps(
                            {"bootstrap_progress": True, "stage": evaluated_stage, **metrics},
                            ensure_ascii=False,
                        ),
                        flush=True,
                    )

            self.tracker.log(
                "bootstrap_progress",
                0,
                {
                    "completed_games": 0,
                    "total_games": int(self.config["evaluation"]["games"]),
                    "completion": 0.0,
                },
                {
                    "stage": evaluated_stage,
                    "bootstrap_attempt": attempt,
                    "bootstrap_evaluation": True,
                    "state": "started",
                },
            )
            print(
                json.dumps(
                    {
                        "bootstrap_progress": True,
                        "stage": evaluated_stage,
                        "completed_games": 0,
                        "total_games": int(self.config["evaluation"]["games"]),
                        "state": "started",
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )
            self._evaluation_progress_callback = report_progress
            try:
                results = self.evaluate(seed_offset=400000000 + attempt * seed_stride)
            finally:
                self._evaluation_progress_callback = None
            evaluation_seconds = max(time.perf_counter() - started, 1e-9)
            evaluated_games = int(results["games"]) + sum(
                int(item["games"]) for item in results["anchors"].values()
            )
            results["evaluation_seconds"] = evaluation_seconds
            results["games_per_second"] = evaluated_games / evaluation_seconds
            promoted = self.curriculum.consider_promotion(
                int(results["wins"]), int(results["games"]), int(results["draws"])
            )
            promotion = self.curriculum.promotion_metrics(
                int(results["wins"]), int(results["draws"]), int(results["games"])
            )
            results.update(
                {
                    "promotion": promotion,
                    "promoted": promoted,
                    "evaluated_stage_index": evaluated_stage_index,
                    "next_stage_index": self.curriculum.stage_index,
                    "selection_score": self._evaluation_score(results),
                    "bootstrap": {
                        "enabled": True,
                        "attempt": attempt,
                        "seed_offset": 400000000 + attempt * seed_stride,
                        "stage": evaluated_stage,
                        "eligible": bool(promotion["eligible"]),
                    },
                }
            )
            results["promotion"]["consecutive_promotion_successes"] = (
                self.curriculum.consecutive_promotion_successes
            )
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
            self._observe_health(
                0,
                {
                    "evaluation_win_rate": float(results["win_rate"]),
                    "evaluation_wilson_lower": float(results["wilson_lower"]),
                    "evaluation_stage": evaluated_stage,
                },
                0,
            )
            score = float(results["selection_score"])
            if evaluated_stage_index > self.best_stage_index or (
                evaluated_stage_index == self.best_stage_index and score > self.best_win_rate
            ):
                self.best_stage_index = evaluated_stage_index
                self.best_win_rate = score
                self._save("best.pt", 0, results, 0)
            # Persist every confirmation. Ctrl+C or a Godot interruption can
            # therefore resume the scan at the exact remaining confirmation.
            self._save("latest.pt", 0, results, 0)
            print(
                json.dumps(
                    {
                        "update": 0,
                        "steps": 0,
                        "stage": evaluated_stage,
                        "bootstrap_evaluation": True,
                        **results,
                    },
                    ensure_ascii=False,
                )
            )
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

    @staticmethod
    def _reset_env_for_terrain(
        env: SamStoneEnv, seeds: list[int], options: dict | None, target_terrain: int | None
    ):
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

    def _training_scenario_options(
        self, scenario_index: int, agent_player: int, blocked: list[list[int]] | None = None
    ) -> dict | None:
        del agent_player
        options = self._scenario_options(scenario_index)
        if options is not None and blocked is not None:
            options["config"]["blocked"] = blocked
        return options

    def _after_training_update(
        self, global_step: int, update: int, episodes: list[dict], evaluation: dict | None
    ) -> None:
        del global_step, update, episodes, evaluation

    def _evaluation_score(self, results: dict[str, Any]) -> float:
        return float(results["win_rate"])

    def _checkpoint_extra(self) -> dict[str, Any]:
        return {}

    def _optimize(self, storage, advantages, returns):
        return PPOOptimizer(
            self.model,
            self.optimizer,
            self.config,
            self.rng,
            self.device,
            self.auxiliary_head,
            self.auxiliary_optimizer,
            self.auxiliary_config,
        ).optimize(storage, advantages, returns)

    def _empty_storage(self, steps: int) -> dict[str, Any]:
        cached = getattr(self, "_rollout_storage", None)
        if cached is not None and len(cached["rewards"]) == steps:
            return cached
        obs_dim, action_dim = self.env.observation_space.shape[0], self.env.action_space.n
        storage = {
            "obs": torch.zeros((steps, obs_dim), device=self.device),
            "masks": torch.zeros((steps, action_dim), dtype=torch.bool, device=self.device),
            "actions": torch.zeros(steps, dtype=torch.long, device=self.device),
            "log_probs": torch.zeros(steps, device=self.device),
            "values": torch.zeros(steps, device=self.device),
            "rewards": torch.zeros(steps, device=self.device),
            "dones": torch.zeros(steps, device=self.device),
        }
        if self.tactical_features_enabled:
            storage["action_features"] = torch.zeros(
                (steps, action_dim, self.tactical_feature_dim), device=self.device
            )
        self._rollout_storage = storage
        return storage

    def _rollout_metrics(
        self,
        storage: dict[str, torch.Tensor],
        advantages: torch.Tensor,
        returns: torch.Tensor,
        episodes: list[dict],
        capture_rewards: list[float],
        terminal_rewards: list[float],
        final_margin_rewards: list[float],
        control_delta_rewards: list[float],
        steps_per_second: float,
    ) -> dict[str, Any]:
        update_seconds = len(storage["rewards"]) / max(steps_per_second, 1e-9)
        metrics: dict[str, Any] = {
            "rollout_reward_mean": float(storage["rewards"].mean()),
            "rollout_reward_std": float(
                (storage["rewards"] - storage["rewards"].mean()).square().mean().sqrt()
            ),
            "capture_reward_mean": float(np.mean(capture_rewards)),
            "terminal_reward_mean": float(np.mean(terminal_rewards)),
            "final_margin_reward_mean": float(np.mean(final_margin_rewards)),
            "control_delta_reward_mean": float(np.mean(control_delta_rewards)),
            "advantage_mean": float(advantages.mean()),
            "advantage_std": float((advantages - advantages.mean()).square().mean().sqrt()),
            "return_mean": float(returns.mean()),
            "value_mean": float(storage["values"].mean()),
            "steps_per_second": float(steps_per_second),
            "update_seconds": float(update_seconds),
            "training_games_per_second": float(len(episodes) / update_seconds),
            "episodes_completed": float(len(episodes)),
            "illegal_actions": 0.0,
        }
        if episodes:
            for dimension, key in (
                ("by_opponent_stage", "opponent_stage"),
                ("by_god", "god"),
                ("by_blocked_count", "blocked_count"),
            ):
                groups: dict[str, list[dict]] = {}
                for episode in episodes:
                    groups.setdefault(str(episode.get(key) or "unknown"), []).append(episode)
                metrics[dimension] = {
                    name: {
                        "games": len(group),
                        "win_rate": float(np.mean([item["won"] for item in group])),
                        "draw_rate": float(np.mean([item["draw"] for item in group])),
                        "return_mean": float(np.mean([item["return"] for item in group])),
                    }
                    for name, group in groups.items()
                }
            metrics.update(
                {
                    "episode_return_mean": float(np.mean([item["return"] for item in episodes])),
                    "episode_return_std": float(np.std([item["return"] for item in episodes])),
                    "episode_turns_mean": float(np.mean([item["turns"] for item in episodes])),
                    "episode_margin_mean": float(np.mean([item["margin"] for item in episodes])),
                    "training_win_rate": float(np.mean([item["won"] for item in episodes])),
                    "training_draw_rate": float(np.mean([item["draw"] for item in episodes])),
                    "agent_captures_mean": float(
                        np.mean([item["agent_captures"] for item in episodes])
                    ),
                    "opponent_captures_mean": float(
                        np.mean([item["opponent_captures"] for item in episodes])
                    ),
                }
            )
        return metrics

    def _resource_metrics(self) -> dict[str, float]:
        metrics = {
            "memory_rss_mb": self.process.memory_info().rss / (1024.0 * 1024.0),
            "process_cpu_percent": self.process.cpu_percent(None),
        }
        worker_pids = {
            item.pid
            for env in self.training_envs
            if (item := env.bridge.process) is not None
            and hasattr(item, "poll")
            and item.poll() is None
        }
        self._simulator_processes = {
            pid: process for pid, process in self._simulator_processes.items() if pid in worker_pids
        }
        worker_stats: list[psutil.Process] = []
        for pid in worker_pids:
            try:
                worker_stats.append(self._simulator_processes.setdefault(pid, psutil.Process(pid)))
            except psutil.Error:
                continue
        if worker_stats:
            metrics["simulator_workers"] = float(len(worker_stats))
            try:
                metrics["simulator_rss_mb"] = float(
                    sum(item.memory_info().rss for item in worker_stats) / (1024.0 * 1024.0)
                )
                # ``cpu_percent(None)`` needs a previous sample. Keeping the
                # psutil objects makes the first value a warm-up and every
                # following rollout an actual interval measurement.
                metrics["simulator_cpu_percent"] = float(
                    sum(item.cpu_percent(None) for item in worker_stats)
                )
            except psutil.Error:
                pass
        if self.device.type == "cuda" and torch.cuda.is_available():
            metrics["gpu_memory_allocated_mb"] = torch.cuda.memory_allocated(self.device) / (
                1024.0 * 1024.0
            )
            metrics["gpu_memory_reserved_mb"] = torch.cuda.memory_reserved(self.device) / (
                1024.0 * 1024.0
            )
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
            payload = {
                **alert.to_dict(),
                "stage": metrics.get("evaluation_stage", self.curriculum.current.name),
            }
            self.tracker.log_alert(payload)
            print(json.dumps({"alert": payload}, ensure_ascii=False))
        critical = self.health.critical(alerts)
        if critical:
            self._save("diagnostic_non_finite.pt", global_step, {}, update)
            raise TrainingHealthError(critical)


def main(argv: list[str] | None = None) -> int:
    """Run the canonical PPO training command."""
    parser = argparse.ArgumentParser(description="Entraîne PPO avec suivi local de santé.")
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(__file__).resolve().parents[3] / "configs" / "ppo_phase4_vectorized.yaml",
    )
    parser.add_argument("--resume", type=Path)
    parser.add_argument(
        "--allow-python-source-change",
        action="store_true",
        help="autorise explicitement une reprise apres modification du seul code Python",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="masque la sortie du terminal, conserve les erreurs et les metriques sur disque",
    )
    parser.add_argument(
        "--reset-optimizer",
        action="store_true",
        help="charge les poids et le curriculum, mais reinitialise Adam",
    )
    parser.add_argument(
        "--weights-only",
        action="store_true",
        help="importe seulement les poids dans un nouveau run",
    )
    arguments = parser.parse_args(argv)
    if arguments.weights_only and arguments.resume is None:
        parser.error("--weights-only exige --resume")
    if arguments.allow_python_source_change and (
        arguments.resume is None or arguments.weights_only
    ):
        parser.error("--allow-python-source-change exige --resume sans --weights-only")
    recover_empty_run = False
    if arguments.weights_only:
        config_path = arguments.config.resolve()
        with config_path.open(encoding="utf-8") as stream:
            configured_output = Path(yaml.safe_load(stream)["output_dir"])
        output = (
            configured_output
            if configured_output.is_absolute()
            else config_path.parent.parent / configured_output
        )
        checkpoints = tuple(output.glob("*.pt")) if output.is_dir() else ()
        metrics = output / "metrics.jsonl"
        metric_lines = (
            [line for line in metrics.read_text(encoding="utf-8").splitlines() if line.strip()]
            if metrics.is_file()
            else []
        )
        has_events = bool(metric_lines)
        # A run interrupted while Godot workers are merely starting has no
        # checkpoint and only bootstrap heartbeat events.  It is equivalent
        # to an empty shell: no learning or curriculum state was persisted.
        bootstrap_only = bool(metric_lines)
        for line in metric_lines:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                bootstrap_only = False
                break
            if not isinstance(event, dict) or event.get("stream") != "bootstrap_progress":
                bootstrap_only = False
                break
        # A startup failure can occur after the manifest and empty logs have
        # been created but before the first checkpoint. It is safe to resume
        # this empty shell and import the same weights again.
        recover_empty_run = (
            (output / "run_manifest.json").is_file()
            and not checkpoints
            and (not has_events or bootstrap_only)
        )
        if (checkpoints or has_events) and not recover_empty_run:
            parser.error(
                "--weights-only initialise un nouveau run, mais le dossier contient deja "
                "un entrainement; utiliser --resume avec son latest.pt"
            )
    mode = (
        "resume"
        if (arguments.resume is not None and not arguments.weights_only) or recover_empty_run
        else "create"
    )
    with ExitStack() as resources:
        if arguments.quiet:
            output_sink = resources.enter_context(open(os.devnull, "w", encoding="utf-8"))
            resources.enter_context(redirect_stdout(output_sink))
        trainer = resources.enter_context(PPOTrainer(arguments.config, mode=mode))
        if arguments.resume is not None:
            trainer.load_checkpoint(
                arguments.resume,
                load_optimizer=not arguments.reset_optimizer and not arguments.weights_only,
                load_training_state=not arguments.weights_only,
                allow_python_source_change=arguments.allow_python_source_change,
            )
        trainer.train()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
