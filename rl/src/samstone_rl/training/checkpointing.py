"""CheckpointMixin responsibilities for PPO trainers; no environment ownership."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import torch

from samstone_rl.models import TacticalActorCritic
from samstone_rl.models.policy import policy_spec
from samstone_rl.utils.certification import certify_checkpoint
from samstone_rl.utils.checkpoints import file_checksum, save_checkpoint
from samstone_rl.utils.checkpoints import load_checkpoint as read_checkpoint


class CheckpointMixin:
    def _record_engine_manifest(self) -> None:
        if self._manifest_has_engine:
            return
        manifests = (
            [self.batch_env.engine_manifest()]
            if self.batch_env is not None
            else [env.bridge.engine_manifest() for env in self.training_envs]
        )
        manifest = manifests[0]
        engine_checksum = hashlib.sha256(
            json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest()
        worker_checksums = [
            hashlib.sha256(
                json.dumps(item, sort_keys=True, separators=(",", ":")).encode()
            ).hexdigest()
            for item in manifests
        ]
        if any(item != engine_checksum for item in worker_checksums):
            raise RuntimeError("les processus Godot ne partagent pas le meme manifeste moteur")
        oracle = self._evaluation_manifest()
        self.tracker.update_manifest(
            checksums={
                "oracle": hashlib.sha256(json.dumps(oracle, sort_keys=True).encode()).hexdigest(),
                "engine": engine_checksum,
                "catalog": str(manifest.get("catalogue_checksum", "")),
            },
            extra={
                "oracle_manifest": oracle,
                "provenance": self.provenance,
                "engine_manifest": manifest,
                "environment_count": self.num_envs,
                "training_backend": self.training_backend,
                "evaluation_backend": self.evaluation_backend,
                "worker_engine_checksums": worker_checksums,
            },
        )
        self._manifest_has_engine = True

    def _save(self, name: str, global_step: int, evaluation: dict, update: int = 0) -> None:
        target = self.output / name
        target.parent.mkdir(parents=True, exist_ok=True)
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
            "checkpoint_schema": 2,
            "policy_spec": policy_spec(self.config),
            "weight_source": getattr(self, "_weight_source", None),
            "provenance": self.provenance,
            "oracle_manifest": getattr(self, "_oracle_manifest", None),
            "evaluation_round": self._evaluation_round,
            "bootstrap_round": self._bootstrap_round,
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
        if name == "phase4_validated.pt":
            certify_checkpoint(payload, "phase4", evaluation, self._evaluation_manifest())
        save_checkpoint(target, payload)

    def load_checkpoint(
        self,
        path: str | Path,
        load_optimizer: bool = True,
        load_training_state: bool = True,
        *,
        allow_python_source_change: bool = False,
    ) -> dict:
        checkpoint_path = Path(path).resolve()
        # torch-directml cannot currently be passed directly as map_location.
        # Loading on CPU is portable; load_state_dict then copies tensors to
        # the model and optimizer device.
        checkpoint = read_checkpoint(checkpoint_path)
        source_change = None
        if load_training_state:
            if checkpoint.get("provenance") != self.provenance:
                saved = checkpoint.get("provenance")
                changed = (
                    {
                        key
                        for key in saved.keys() | self.provenance.keys()
                        if saved.get(key) != self.provenance.get(key)
                    }
                    if isinstance(saved, dict)
                    else set()
                )
                source_only = changed == {"python_source"} and all(
                    isinstance(identity.get("python_source"), str)
                    and bool(identity["python_source"])
                    for identity in (saved, self.provenance)
                )
                if not (source_only and allow_python_source_change):
                    detail = (
                        "seul le code Python differe; apres verification des changements, "
                        "utiliser --allow-python-source-change pour conserver la progression"
                        if source_only
                        else "regles/contenu/version incompatibles pour une reprise; "
                        "importer les poids avec --weights-only dans un nouveau run"
                    )
                    raise ValueError(detail)
                source_change = {
                    "checkpoint": str(checkpoint_path),
                    "checkpoint_sha256": file_checksum(checkpoint_path),
                    "previous": saved,
                    "current": self.provenance,
                }
            saved_oracle = checkpoint.get("oracle_manifest")
            if saved_oracle is not None and saved_oracle != self._evaluation_manifest():
                raise ValueError("moteur d evaluation different du checkpoint")
            if checkpoint.get("policy_spec") != policy_spec(self.config):
                raise ValueError("contrat de politique incompatible pour une reprise")
            old_config = checkpoint.get("config", {})
            if (
                old_config.get("environment", {}).get("reward")
                != self.config["environment"]["reward"]
            ):
                raise ValueError("recompenses differentes; importer les poids dans un nouveau run")
            if (
                load_optimizer
                and old_config.get("ppo", {}).get("learning_rate")
                != self.config["ppo"]["learning_rate"]
            ):
                raise ValueError("learning rate different; utiliser --reset-optimizer")
        if not load_training_state and isinstance(self.model, TacticalActorCritic):
            try:
                self.model.load_state_dict(checkpoint["model"])
            except RuntimeError:
                transferred = self.model.import_legacy_state(checkpoint["model"])
                print(
                    json.dumps(
                        {"weights_imported": list(transferred), "actor_initialized": "tactical"}
                    )
                )
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
            self._weight_source = {
                "path": str(checkpoint_path),
                "sha256": file_checksum(checkpoint_path),
                "provenance": checkpoint.get("provenance"),
                "global_step": int(checkpoint.get("global_step", 0)),
            }
            self.tracker.update_manifest(extra={"weight_source": self._weight_source})
            return checkpoint
        self._weight_source = checkpoint.get("weight_source")
        curriculum = checkpoint.get("curriculum", {})
        self.curriculum.load_state_dict(curriculum)
        # Confirmations must use the same promotion contract. Preserve the
        # learned stage and optimizer, but evaluate amended thresholds afresh.
        previous_curriculum = checkpoint.get("config", {}).get("curriculum", {})
        if any(
            previous_curriculum.get(key) != self.config["curriculum"].get(key)
            for key in ("promotion_win_rate", "maximum_loss_rate", "non_loss_confidence_floor")
        ):
            self.curriculum.consecutive_promotion_successes = 0
        self.best_win_rate = float(
            checkpoint.get("best_win_rate", checkpoint.get("evaluation", {}).get("win_rate", -1.0))
        )
        self.best_stage_index = int(
            checkpoint.get(
                "best_stage_index",
                checkpoint.get("evaluation", {}).get("evaluated_stage_index", -1),
            )
        )
        self._resume_global_step = int(checkpoint.get("global_step", 0))
        self._evaluation_round = int(checkpoint.get("evaluation_round", 0))
        self._bootstrap_round = int(checkpoint.get("bootstrap_round", 0))
        batch_size = int(self.config["ppo"]["rollout_steps"]) * int(
            self.config["ppo"].get("num_envs", 1)
        )
        self._resume_update = int(
            checkpoint.get("update", self._resume_global_step // max(1, batch_size))
        )
        rng = checkpoint.get("rng", {})
        if "numpy" in rng:
            self.rng.bit_generator.state = rng["numpy"]
        if "torch" in rng:
            torch.set_rng_state(rng["torch"].cpu())
        if torch.cuda.is_available() and "torch_cuda" in rng:
            torch.cuda.set_rng_state_all(rng["torch_cuda"])
        if source_change is not None:
            self.tracker.update_manifest(extra={"resume_source_change": source_change})
        return checkpoint

    @staticmethod
    def _file_checksum(path: Path) -> str:
        return file_checksum(path)

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
