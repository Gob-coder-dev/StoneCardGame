"""Phase 5: PPO learner, validated champions and automatic campaign completion."""

from __future__ import annotations

import argparse
import os
import shutil
from contextlib import ExitStack, redirect_stdout
from copy import deepcopy
from pathlib import Path

import yaml

from samstone_rl.models.policy import policy_spec
from samstone_rl.training.league import LeagueOpponent, SelfPlayLeague
from samstone_rl.training.phase_five_arena import PhaseFiveArena
from samstone_rl.training.phase_five_curriculum import ChampionCurriculum
from samstone_rl.training.phase_five_protocol import validate_settings
from samstone_rl.training.ppo_cleanrl import PPOTrainer
from samstone_rl.training.self_play_metrics import log_self_play
from samstone_rl.training.validation import wilson_lower
from samstone_rl.utils.certification import require_certified
from samstone_rl.utils.checkpoints import file_checksum, load_checkpoint
from samstone_rl.utils.provenance import provenance
from samstone_rl.utils.resources import close_on_error


def verify_phase_four(checkpoint, current, allow_python_source_change):
    """Verify the original certificate, then explicitly authorize Python-only migration."""
    recorded = checkpoint.get("provenance", {})
    require_certified(checkpoint, "phase4", recorded)
    changes = {
        key for key in current.keys() | recorded.keys() if current.get(key) != recorded.get(key)
    }
    if changes and not (changes == {"python_source"} and allow_python_source_change):
        raise ValueError(
            "phase 4 incompatible; une migration Python exige --allow-python-source-change"
        )


class PhaseFiveTrainer(ChampionCurriculum, PPOTrainer):
    @close_on_error
    def __init__(
        self,
        config_path: str | Path,
        *,
        phase4_checkpoint: str | Path | None = None,
        resume: str | Path | None = None,
        allow_python_source_change: bool = False,
        migrate_legacy_phase5: bool = False,
        output_override: str | Path | None = None,
    ) -> None:
        if (phase4_checkpoint is None) == (resume is None):
            raise ValueError("fournir soit phase4_checkpoint, soit resume")
        source_path = Path(phase4_checkpoint or resume).resolve()
        source = load_checkpoint(source_path)
        original = source.get("phase5", {})
        if phase4_checkpoint is not None and not source.get("curriculum", {}).get("completed"):
            raise ValueError("la phase 5 exige phase4_validated.pt")
        if resume is not None and not original.get("initial_policy_checksum"):
            raise ValueError("resume exige un checkpoint de phase 5")
        legacy = resume is not None and "champion_curriculum" not in original
        if legacy and not migrate_legacy_phase5:
            raise ValueError(
                "ancien plan phase 5 : utiliser --migrate-legacy-phase5 pour conserver poids et Adam"
            )
        requested = yaml.safe_load(Path(config_path).read_text(encoding="utf-8"))
        validate_settings(requested["phase5"])
        if requested.get("phase4_automation", {}).get("enabled", False):
            raise ValueError("la phase 5 ne doit pas activer phase4_automation")
        if phase4_checkpoint is not None:
            verify_phase_four(source, provenance(), allow_python_source_change)
            if policy_spec(source.get("config", {})) != policy_spec(requested):
                raise ValueError("contrat du modele different de la phase 4")
            for key in ("scenarios", "reward"):
                before = source.get("config", {}).get("environment", {}).get(key)
                if before is not None and before != requested["environment"][key]:
                    raise ValueError(f"phase 5 et phase 4 n'utilisent pas les memes {key}")
        self.phase5_state = {}
        self._allow_pending_source_restart = allow_python_source_change
        self.phase5_completed = False
        super().__init__(
            config_path,
            output_override=output_override,
            mode="resume" if resume else "create",
            resume_config_paths=(("phase5",), ("evaluation",))
            if legacy
            else (("phase5", "maximum_updates_without_promotion"),),
        )
        self.phase4_baseline = self.output / "phase4_baseline.pt"
        self.league_directory = self.output / "league"
        if phase4_checkpoint is not None:
            self.phase4_checksum = file_checksum(source_path)
            if self.phase4_baseline.exists() or self.league_directory.exists():
                raise ValueError("run de phase 5 deja initialise; utiliser --resume")
            shutil.copy2(source_path, self.phase4_baseline)
        else:
            self.phase4_checksum = str(original["initial_policy_checksum"])
            if (
                not self.phase4_baseline.exists()
                or file_checksum(self.phase4_baseline) != self.phase4_checksum
            ):
                raise ValueError("politique initiale absente ou alteree")
            verify_phase_four(
                load_checkpoint(self.phase4_baseline),
                self.provenance,
                allow_python_source_change
                or (
                    source.get("provenance") == self.provenance
                    and "champion_curriculum" in original
                ),
            )
        self.tracker.update_manifest(checksums={"initial_policy": self.phase4_checksum})
        self.league = SelfPlayLeague(
            self.league_directory,
            self.config["phase5"]["training_weights"],
            "cpu",
            self.curriculum.stages,
        )
        self._resources.callback(self.league.flush_results)
        if resume is not None:
            self.load_checkpoint(source_path, allow_python_source_change=allow_python_source_change)
            self.curriculum.completed = True
            self.curriculum.awaiting_final_validation = False
            self.curriculum.bootstrap_evaluation_completed = True
        else:
            self.model.load_state_dict(source["model"])
            self.curriculum.load_state_dict(source["curriculum"])
        self._initialize_champions(source, legacy=legacy)
        self.arena = PhaseFiveArena(self)
        self.phase5_completed = self.phase5_state["status"] == "completed"
        if resume is None or legacy:
            self._save("latest.pt", self._resume_global_step, {}, self._resume_update)
            self._publish_phase5()

    def _training_opponent(self):
        return LeagueOpponent(self.league)

    def _evaluation_game_count(self):
        return (
            4
            * len(self.config["environment"]["scenarios"]) ** 2
            * int(self.config["phase5"]["screen_games_per_slice"])
        )

    def _evaluation_stage_name(self):
        return f"champion_{self.phase5_state['promotions']:04d}"

    def _training_scenario_options(self, scenario_index, agent_player, blocked=None):
        own = self.scenarios[scenario_index]
        choices = list(range(len(self.scenarios)))
        mirror = float(self.config["phase5"].get("mirror_probability", 0.1))
        if len(choices) > 1 and self.rng.random() >= mirror:
            choices.remove(scenario_index)
        else:
            choices = [scenario_index]
        other = self.scenarios[choices[int(self.rng.integers(len(choices)))]]
        home, away = (own, other) if agent_player == 1 else (other, own)
        config = dict(
            human_god=home["god"],
            ai_god=away["god"],
            human_deck=list(home["deck"]),
            ai_deck=list(away["deck"]),
        )
        if blocked is not None:
            config["blocked"] = blocked
        return {"config": config}

    def evaluate(self, seed_offset=0):
        del seed_offset
        state, settings = self.phase5_state, self.config["phase5"]
        actor = self.arena.live_actor()
        _, _, result = self.arena.duels(
            actor,
            self.output / state["champions"][-1]["path"],
            int(settings["screen_games_per_slice"]),
            self._phase5_seed(0, self._evaluation_round),
            "screening",
        )
        result.update(
            anchors={},
            by_blocked_count={},
            mean_margin=0.0,
            mean_turns=0.0,
            wilson_lower=wilson_lower(result["wins"], result["games"]),
            champion_generation=state["promotions"],
            screening_eligible=result["score"] >= float(settings["screen_minimum_score"]),
        )
        return result

    def _evaluation_score(self, results):
        return float(results["score"])

    def _consider_evaluation_promotion(self, results):
        # A screening score never promotes a champion by itself.
        results["promotion"] = dict(
            eligible=False,
            screening_eligible=results["screening_eligible"],
            champion_generation=self.phase5_state["promotions"],
        )
        return False

    def _after_training_update(self, global_step, update, episodes, evaluation):
        self._current_global_step, self._current_update = global_step, update
        log_self_play(self, global_step, update, episodes)
        state = self.phase5_state
        if (
            evaluation
            and evaluation["screening_eligible"]
            and update >= state["next_attempt_update"]
        ):
            if self._start_candidate(global_step, update, evaluation):
                return True
        if self._plateau_reached(update):
            self._stop_phase5("plateau", global_step, update, evaluation)
            return True
        self._publish_phase5()
        return False

    def _checkpoint_extra(self):
        return {
            "phase5": dict(
                completed=self.phase5_completed,
                initial_policy_checksum=self.phase4_checksum,
                champion_curriculum=deepcopy(self.phase5_state),
            )
        }


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Phase 5 : candidat PPO et paliers de champions valides."
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(__file__).resolve().parents[3] / "configs/ppo_self_play_v2.yaml",
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--phase4", type=Path)
    source.add_argument("--resume", type=Path)
    parser.add_argument("--allow-python-source-change", action="store_true")
    parser.add_argument("--migrate-legacy-phase5", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)
    if args.migrate_legacy_phase5 and args.resume is None:
        parser.error("--migrate-legacy-phase5 exige --resume")
    with ExitStack() as resources:
        if args.quiet:
            sink = resources.enter_context(open(os.devnull, "w", encoding="utf-8"))
            resources.enter_context(redirect_stdout(sink))
        trainer = resources.enter_context(
            PhaseFiveTrainer(
                args.config,
                phase4_checkpoint=args.phase4,
                resume=args.resume,
                allow_python_source_change=args.allow_python_source_change,
                migrate_legacy_phase5=args.migrate_legacy_phase5,
            )
        )
        trainer.train()
        return trainer._phase5_exit_code


if __name__ == "__main__":
    raise SystemExit(main())
