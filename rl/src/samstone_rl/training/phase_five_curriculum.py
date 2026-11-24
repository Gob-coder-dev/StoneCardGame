"""Checkpoint-authoritative champion/candidate lifecycle, independent of PPO math."""

import json
import time
from copy import deepcopy

from samstone_rl.training.league import LeagueEntry
from samstone_rl.training.phase_five_gate import evaluate_candidate
from samstone_rl.training.phase_five_sampling import AdaptiveOpponents
from samstone_rl.utils.certification import require_certified
from samstone_rl.utils.checkpoints import (
    atomic_text,
    file_checksum,
    load_checkpoint,
    policy_checksum,
    save_checkpoint,
    state_checksum,
)


class ChampionCurriculum(AdaptiveOpponents):
    """Mixin: only a successful frozen tournament can replace the champion."""

    def _initialize_champions(self, source, *, legacy=False):
        saved = source.get("phase5", {}).get("champion_curriculum")
        self._phase5_exit_code = 0
        self._phase5_heartbeat = 0.0
        if saved is not None:
            self.phase5_state = deepcopy(saved)
            if saved.get("schema") != 1:
                raise ValueError("schema du curriculum phase 5 incompatible")
        else:
            if legacy:
                manifest = self.league.manifest_path
                if manifest.exists():
                    archive = self.league_directory / "legacy_manifest.json"
                    if not archive.exists():
                        atomic_text(archive, manifest.read_text(encoding="utf-8"))
                backup = self.output / "checkpoints/legacy_phase5_source.pt"
                if not backup.exists():
                    save_checkpoint(backup, source)
            baseline = load_checkpoint(self.phase4_baseline)
            champion = self._champion_file(baseline, 0, 0, 0.5)
            self.phase5_state = dict(
                schema=1,
                status="training",
                promotions=0,
                attempts=0,
                failed_attempts=0,
                generation_start_update=self._resume_update,
                next_attempt_update=self._resume_update
                + (0 if legacy else int(self.config["phase5"]["minimum_updates_between_attempts"])),
                pending=None,
                last_failed_policy=None,
                champions=[champion],
                reports=[],
                legacy_migration=legacy,
            )
        self._initialize_opponent_sampling()
        self._activate_champions()

    def _champion_file(self, payload, generation, step, score):
        relative = f"league/champion_{generation:04d}.pt"
        path = self.output / relative
        checksum = state_checksum(payload["model"])
        if path.exists():
            if state_checksum(load_checkpoint(path)["model"]) != checksum:
                raise ValueError("un autre champion immuable existe deja")
        else:
            save_checkpoint(path, payload)
        return dict(
            generation=generation,
            path=relative,
            sha256=file_checksum(path),
            policy=checksum,
            global_step=step,
            score=score,
        )

    def _activate_champions(self):
        entries = []
        champions = self.phase5_state["champions"]
        for index, champion in enumerate(champions):
            path = (self.output / champion["path"]).resolve()
            if (
                not path.is_relative_to(self.league_directory)
                or file_checksum(path) != champion["sha256"]
            ):
                raise ValueError("champion absent, deplace ou altere")
            entries.append(
                LeagueEntry(
                    f"champion_{champion['generation']:04d}",
                    path.name,
                    "current" if index == len(champions) - 1 else "historical",
                    int(champion["global_step"]),
                    float(champion["score"]),
                )
            )
        self.league.entries = entries
        self._apply_opponent_sampling()
        self.league._save_manifest()

    def _phase5_history(self):
        older = self.phase5_state["champions"][:-1]
        limit = int(self.config["phase5"]["maximum_history_anchors"])
        if len(older) <= limit:
            return older
        return [older[0], *older[-(limit - 1) :]] if limit > 1 else [older[0]]

    def _phase5_seed(self, domain, attempt, round_index=0):
        return (
            int(self.config["phase5"]["seed_base"])
            + domain * 10_000_000_000
            + attempt * 1_000_000
            + round_index * 10_000
        )

    def _phase5_contract(self):
        settings = deepcopy(self.config["phase5"])
        settings.pop("maximum_updates_without_promotion", None)
        settings.pop("adaptive_opponents", None)
        return dict(
            settings=settings,
            scenarios=self.scenarios,
            stages=self.config["curriculum"]["stages"],
            provenance=self.provenance,
            oracle=self._evaluation_manifest(),
        )

    def _publish_phase5(self, **details):
        state = self.phase5_state
        pending = state.get("pending")
        payload = dict(
            phase=state["status"],
            promotions=state["promotions"],
            target_promotions=int(self.config["phase5"]["target_promotions"]),
            attempts=state["attempts"],
            failed_attempts=state["failed_attempts"],
            step=pending["step"]
            if pending
            else getattr(self, "_current_global_step", self._resume_global_step),
            update=pending["update"]
            if pending
            else getattr(self, "_current_update", self._resume_update),
            champion=state["champions"][-1]["path"],
            **details,
        )
        sampling = state.get("opponent_sampling")
        if sampling is not None:
            payload["bot_fraction"] = sampling["bot_fraction"]
            payload["next_bot_followup_update"] = sampling["next_update"]
        atomic_text(
            self.output / "phase5_status.json", json.dumps(payload, indent=2, allow_nan=False)
        )
        self.tracker.log(
            "phase5_curriculum",
            payload["step"],
            dict(
                promotions=state["promotions"],
                target_promotions=payload["target_promotions"],
                attempts=state["attempts"],
                failed_attempts=state["failed_attempts"],
                updates_since_promotion=max(
                    0, payload["update"] - state["generation_start_update"]
                ),
            ),
            dict(status=state["status"], champion=payload["champion"]),
        )

    def _phase5_progress(self, operation, completed, total):
        now = time.monotonic()
        if completed == total or completed == 0 or now - self._phase5_heartbeat >= 5:
            self._phase5_heartbeat = now
            self._publish_phase5(operation=operation, completed_games=completed, total_games=total)
            self.tracker.log(
                "phase5_progress",
                getattr(self, "_current_global_step", self._resume_global_step),
                dict(completed_games=completed, total_games=total),
                dict(operation=operation),
            )

    def _before_training(self):
        self._activate_champions()
        state = self.phase5_state
        if state["status"] == "completed":
            certificate = load_checkpoint(self.output / "phase5_validated.pt")
            require_certified(certificate, "phase5", self.provenance)
            if state_checksum(certificate["model"]) != policy_checksum(self.model):
                raise ValueError("les poids ne correspondent pas au champion certifie")
            self._publish_phase5(checkpoint="phase5_validated.pt")
            return True
        if state["pending"] is not None:
            return self._resolve_candidate()
        # The immutable snapshot can commit just before latest.pt is replaced.
        # Recover that transaction before allowing another optimizer update.
        orphan_path = (
            self.output / f"evaluations/phase5/candidates/attempt_{state['attempts'] + 1:04d}.pt"
        )
        if orphan_path.exists():
            orphan = load_checkpoint(orphan_path)
            recovered = orphan["phase5"]["champion_curriculum"]
            pending = recovered["pending"]
            if (
                pending["step"] != self._resume_global_step
                or pending["update"] != self._resume_update
                or pending["policy"] != policy_checksum(self.model)
                or recovered["champions"] != state["champions"]
                or pending["contract"] != self._phase5_contract()
            ):
                raise ValueError(
                    "un candidat non termine existe pour d'autres poids; reprendre son latest.pt"
                )
            self.phase5_state = deepcopy(recovered)
            self.phase5_state["pending"]["checksum"] = file_checksum(orphan_path)
            self._save("latest.pt", self._resume_global_step, {}, self._resume_update)
            return self._resolve_candidate()
        self._current_global_step, self._current_update = (
            self._resume_global_step,
            self._resume_update,
        )
        if self._plateau_reached(self._resume_update):
            self._stop_phase5("plateau", self._resume_global_step, self._resume_update)
            return True
        state["status"] = "training"
        self._evaluate_opponent_sampling(
            self._resume_global_step, self._resume_update, self._last_screening
        )
        self._publish_phase5()
        return False

    def _plateau_reached(self, update):
        state = self.phase5_state
        start = max(
            state["generation_start_update"],
            state.get("opponent_sampling", {}).get("activation_update", 0),
        )
        return update - start >= int(self.config["phase5"]["maximum_updates_without_promotion"])

    def _stop_phase5(self, reason, step, update, evaluation=None):
        self.phase5_state["status"] = reason
        self._phase5_exit_code = 2
        self._save("latest.pt", step, evaluation or {}, update)
        self._publish_phase5()

    def _on_training_budget_exhausted(self, step, update, evaluation):
        self._stop_phase5("budget_exhausted", step, update, evaluation)

    def _start_candidate(self, step, update, evaluation):
        if self.evaluation_backend != "godot":
            raise ValueError("les promotions phase 5 exigent Godot")
        state = self.phase5_state
        checksum = policy_checksum(self.model)
        if checksum in (state["champions"][-1]["policy"], state["last_failed_policy"]):
            return False
        attempt = state["attempts"] + 1
        pending = dict(
            attempt=attempt,
            path=f"evaluations/phase5/candidates/attempt_{attempt:04d}.pt",
            checksum=None,
            policy=checksum,
            step=step,
            update=update,
            final=state["promotions"] + 1 >= int(self.config["phase5"]["target_promotions"]),
            contract=self._phase5_contract(),
        )
        state.update(status="evaluating", attempts=attempt, pending=pending)
        path = self.output / pending["path"]
        if path.exists():
            orphan = load_checkpoint(path)
            if (
                state_checksum(orphan["model"]) != checksum
                or orphan["global_step"] != step
                or orphan["update"] != update
                or orphan["phase5"]["champion_curriculum"]["pending"] != pending
            ):
                raise ValueError("un autre candidat immuable existe pour cette tentative")
        else:
            self._save(pending["path"], step, evaluation, update)
        pending["checksum"] = file_checksum(path)
        self._save("latest.pt", step, evaluation, update)
        return self._resolve_candidate()

    def _resolve_candidate(self):
        state, pending = self.phase5_state, self.phase5_state["pending"]
        path = (self.output / pending["path"]).resolve()
        if (
            not path.is_relative_to((self.output / "evaluations/phase5/candidates").resolve())
            or file_checksum(path) != pending["checksum"]
            or policy_checksum(self.model) != pending["policy"]
        ):
            raise ValueError(
                "validation figee incompatible ou alteree; conserver les sources et reprendre latest.pt"
            )
        contract = self._phase5_contract()
        if pending["contract"] != contract:
            migrated = deepcopy(pending["contract"])
            migrated["provenance"]["python_source"] = self.provenance["python_source"]
            if not (getattr(self, "_allow_pending_source_restart", False) and migrated == contract):
                raise ValueError(
                    "validation figee incompatible; reprendre avec les sources d'origine "
                    "ou --allow-python-source-change pour recommencer sous les nouvelles sources"
                )
            # Preserve all previous evidence. A new attempt uses fresh seeds
            # and ledgers, before any further PPO update can change the policy.
            state.setdefault("superseded_attempts", []).append(
                dict(
                    attempt=pending["attempt"],
                    path=pending["path"],
                    checksum=pending["checksum"],
                    provenance=pending["contract"]["provenance"],
                    reason="python_source_change",
                )
            )
            state["pending"] = None
            return self._start_candidate(pending["step"], pending["update"], {})
        try:
            self._phase5_evidence = []
            report = evaluate_candidate(self, pending)
        except BaseException as error:
            self._publish_phase5(error=repr(error), resumable_validation=True)
            raise
        report.update(
            protocol="champion_v1",
            candidate_policy=pending["policy"],
            candidate_sha256=pending["checksum"],
            champion_generation=state["promotions"],
            target_promotions=int(self.config["phase5"]["target_promotions"]),
            independent_final_holdout=bool(pending["final"] and report["passed"]),
            criteria=deepcopy(self.config["phase5"]),
            provenance=self.provenance,
            oracle=self._evaluation_manifest(),
            reference_champions=deepcopy(state["champions"]),
            phase4_reference_sha256=self.phase4_checksum,
            tournaments=self._phase5_evidence,
        )
        report_path = path.with_suffix(".report.json")
        atomic_text(report_path, json.dumps(report, indent=2, allow_nan=False))
        self.tracker.log(
            "phase5_promotion", pending["step"], report, dict(attempt=pending["attempt"])
        )
        state["reports"].append(str(report_path.relative_to(self.output)))
        step, update = pending["step"], pending["update"]
        if report["passed"]:
            champion = self._champion_file(
                load_checkpoint(path), state["promotions"] + 1, step, report["candidate"]["score"]
            )
            state["champions"].append(champion)
            state["promotions"] += 1
            state["generation_start_update"] = update
            self.best_win_rate = -1.0
            self._activate_champions()
            self._training_envs_need_reset = True
        else:
            state["failed_attempts"] += 1
            state["last_failed_policy"] = pending["policy"]
        state["next_attempt_update"] = update + int(
            self.config["phase5"]["minimum_updates_between_attempts"]
        )
        state["pending"] = None
        complete = bool(report["passed"] and pending["final"])
        state["status"] = "completed" if complete else "training"
        self.phase5_completed = complete
        if complete:
            self._save("phase5_validated.pt", step, report, update)
        self._save("latest.pt", step, report, update)
        self._publish_phase5(last_promotion_passed=report["passed"])
        return complete
