"""Checkpointed phase-4 lifecycle; a technical error never becomes a gate failure."""

import json
import time
from copy import deepcopy
from pathlib import Path

from samstone_rl.utils.certification import require_certified
from samstone_rl.utils.checkpoints import (
    atomic_text,
    file_checksum,
    load_checkpoint,
    policy_checksum,
    state_checksum,
)


class PhaseFourAutomationMixin:
    def _initialize_phase_four_automation(self):
        settings = self.config.get("phase4_automation", {})
        self._phase4_auto_enabled = bool(settings.get("enabled", False))
        self._phase4_exit_code = 0
        self._phase4_reset_envs = False
        self._phase4_auto = dict(
            status="training",
            attempts=0,
            failures=0,
            retry_after_update=0,
            candidate=None,
            last_failed_policy=None,
        )
        self._phase4_heartbeat = 0.0
        if self._phase4_auto_enabled:
            for key in (
                "minimum_updates_between_attempts",
                "maximum_failed_attempts",
                "seed_stride",
            ):
                if (
                    int(
                        settings.get(
                            key,
                            {
                                "minimum_updates_between_attempts": 100,
                                "maximum_failed_attempts": 3,
                                "seed_stride": 1000000,
                            }[key],
                        )
                    )
                    < 1
                ):
                    raise ValueError(f"phase4_automation.{key} doit etre positif")

    def _automation_setting(self, key, default):
        return int(self.config.get("phase4_automation", {}).get(key, default))

    def _restore_phase_four_automation(self, checkpoint, criteria_changed):
        if not self._phase4_auto_enabled:
            return
        saved = checkpoint.get("phase4_automation")
        if saved:
            candidate = saved.get("candidate")
            if saved["status"] in ("validating", "completed") and candidate:
                if candidate["identity"]["provenance"] != self.provenance:
                    raise ValueError(
                        "sources modifiees pendant la validation figee; reprendre avec les sources de ce candidat"
                    )
                if (
                    candidate["identity"]["config"]["evaluation"]["final_gate"]
                    != self.config["evaluation"]["final_gate"]
                ):
                    raise ValueError("criteres modifies pendant la validation figee")
            if not criteria_changed:
                self._phase4_auto = deepcopy(saved)
                return
            # Keep snapshot numbering and the failure budget across revised
            # criteria; an existing immutable candidate must never be reused.
            self._phase4_auto = deepcopy(saved)
            self._phase4_auto.update(status="training", candidate=None)
        # Legacy checkpoints may already await a manual gate which failed.
        # Train and obtain new confirmations instead of rerolling the same model.
        if self.curriculum.awaiting_final_validation:
            self.curriculum.awaiting_final_validation = False
            self.curriculum.completed = False
            self.curriculum.consecutive_promotion_successes = 0
            self.curriculum.bootstrap_evaluation_completed = True
            self._phase4_auto["retry_after_update"] = (
                self._resume_update
                + self._automation_setting("minimum_updates_between_attempts", 100)
            )

    def _publish_phase_four(self, step, update, **details):
        if not self._phase4_auto_enabled:
            return
        payload = dict(
            phase=self._phase4_auto["status"],
            step=step,
            update=update,
            stage=self.curriculum.current.name,
            attempts=self._phase4_auto["attempts"],
            failed_attempts=self._phase4_auto["failures"],
            retry_after_update=self._phase4_auto["retry_after_update"],
            **details,
        )
        atomic_text(
            self.output / "phase4_status.json", json.dumps(payload, indent=2, allow_nan=False)
        )

    def _automatic_phase_four_gate(self, step, update, evaluation):
        """Return True to stop PPO; leave the latest checkpoint resumable."""
        if not self._phase4_auto_enabled:
            return False
        state = self._phase4_auto
        if state["status"] == "completed" or self.curriculum.completed:
            certified = load_checkpoint(self.output / "phase4_validated.pt")
            require_certified(certified, "phase4", self.provenance)
            if policy_checksum(self.model) != state_checksum(certified["model"]):
                raise ValueError("poids differents du candidat certifie")
            state["status"] = "completed"
            self._publish_phase_four(step, update, checkpoint="phase4_validated.pt")
            return True
        if state["failures"] >= self._automation_setting("maximum_failed_attempts", 3):
            state["status"] = "retry_limit_reached"
            self._phase4_exit_code = 2
            self._save("latest.pt", step, evaluation, update)
            self._publish_phase_four(step, update)
            return True
        if state["status"] != "validating":
            state["status"] = "training"
            self._publish_phase_four(step, update)
            if not self.curriculum.awaiting_final_validation:
                return False
            checksum = policy_checksum(self.model)
            if update < state["retry_after_update"] or checksum == state["last_failed_policy"]:
                self.curriculum.awaiting_final_validation = False
                self.curriculum.consecutive_promotion_successes = 0
                return False
            if self.evaluation_backend != "godot":
                raise ValueError("la validation automatique exige Godot")
            stride = self._automation_setting("seed_stride", 1000000)
            cases = (
                len(self.scenarios)
                * len(self.curriculum.stages)
                * 4
                * int(self.config["evaluation"]["final_gate"]["games_per_slice"])
            )
            if stride < cases:
                raise ValueError("seed_stride doit couvrir toutes les parties de validation")
            state["attempts"] += 1
            state["status"] = "validating"
            candidate_path = (
                self.output / f"evaluations/phase4/candidates/attempt_{state['attempts']:04d}.pt"
            )
            state["candidate"] = dict(
                path=str(candidate_path.resolve()),
                checksum=None,
                seed_offset=state["attempts"] * stride,
                identity=dict(
                    provenance=deepcopy(self.provenance),
                    oracle=self._evaluation_manifest(),
                    policy=checksum,
                    config=deepcopy(self.config),
                ),
            )
            if candidate_path.exists():
                # A crash can commit the snapshot before committing latest.pt.
                # Adopt that orphan only if it is exactly this frozen candidate.
                orphan = load_checkpoint(candidate_path)
                if (
                    orphan.get("global_step") != step
                    or orphan.get("update") != update
                    or state_checksum(orphan["model"]) != checksum
                    or orphan.get("phase4_automation", {}).get("candidate") != state["candidate"]
                ):
                    raise ValueError("un autre candidat immuable existe pour cette tentative")
            else:
                self._save(str(candidate_path), step, evaluation, update)
            state["candidate"]["checksum"] = file_checksum(candidate_path)
            # This is the restart point, committed before any final match.
            self._save("latest.pt", step, evaluation, update)
        candidate = state["candidate"]
        if file_checksum(Path(candidate["path"])) != candidate["checksum"]:
            raise ValueError("checkpoint candidat altere")
        if policy_checksum(self.model) != candidate["identity"]["policy"]:
            raise ValueError("les poids ont change pendant la validation finale")

        def progress(completed, total):
            now = time.monotonic()
            if completed == total or completed % 100 == 0 or now - self._phase4_heartbeat >= 5:
                self._phase4_heartbeat = now
                self._publish_phase_four(step, update, completed_games=completed, total_games=total)
                self.tracker.log(
                    "final_gate_progress",
                    step,
                    dict(completed_games=completed, total_games=total),
                    dict(attempt=state["attempts"], update=update),
                )

        try:
            report = self.run_final_gate(
                seed_offset=candidate["seed_offset"],
                identity=candidate["identity"],
                on_progress=progress,
            )
        except BaseException as error:
            self._publish_phase_four(step, update, error=repr(error), resumable_validation=True)
            raise
        result = report.to_dict()
        atomic_text(
            Path(candidate["path"]).with_suffix(".report.json"), json.dumps(result, indent=2)
        )
        self.tracker.log("final_gate", step, result, dict(attempt=state["attempts"], update=update))
        if report.passed:
            state["status"] = "completed"
            self._save("phase4_validated.pt", step, result, update)
            self._save("latest.pt", step, result, update)
            self._publish_phase_four(step, update, checkpoint="phase4_validated.pt")
            return True
        state["failures"] += 1
        state["last_failed_policy"] = candidate["identity"]["policy"]
        state["candidate"] = None
        state["status"] = "training"
        state["retry_after_update"] = update + self._automation_setting(
            "minimum_updates_between_attempts", 100
        )
        self.curriculum.awaiting_final_validation = False
        self.curriculum.completed = False
        self.curriculum.consecutive_promotion_successes = 0
        self.curriculum.bootstrap_evaluation_completed = True
        self._phase4_reset_envs = self.evaluation_env in self.training_envs
        self._save("latest.pt", step, {"final_gate_failed": result}, update)
        self._publish_phase_four(
            step, update, last_gate_passed=False, failed_slices=result.get("failed_slices", [])
        )
        if state["failures"] >= self._automation_setting("maximum_failed_attempts", 3):
            return self._automatic_phase_four_gate(step, update, evaluation)
        return False
