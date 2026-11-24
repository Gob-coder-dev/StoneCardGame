"""Adaptive training mix driven by held-out bot diagnostics."""

from math import isfinite


def validate_adaptive_opponents(settings):
    initial = float(settings["initial_bot_fraction"])
    minimum = float(settings["minimum_bot_fraction"])
    maximum = float(settings["maximum_bot_fraction"])
    step = float(settings["adjustment"])
    if not (0 < minimum <= initial <= maximum <= 0.5 and 0 < step <= 0.5):
        raise ValueError("ratios adaptatifs invalides")
    if (
        int(settings["every_updates"]) < 1
        or int(settings["consecutive_results"]) < 2
        or not 1 <= int(settings["games_per_slice"]) <= 64
    ):
        raise ValueError("frequence ou taille du suivi adaptatif invalide")


def update_sampling(state, settings, report, maximum_stage_regression):
    """Require consecutive results for the overall mix and smooth profile deficits."""
    direction = -1 if report["passed"] else 1
    previous = state["streak"]
    streak = previous + direction if previous * direction > 0 else direction
    ratio = state["bot_fraction"]
    if abs(streak) >= int(settings["consecutive_results"]):
        ratio = min(
            float(settings["maximum_bot_fraction"]),
            max(
                float(settings["minimum_bot_fraction"]),
                ratio + direction * float(settings["adjustment"]),
            ),
        )
        streak = 0
    deltas = report["win_rate_deltas"]
    weaknesses = {}
    for name, previous_deficit in state["stage_deficits"].items():
        delta = float(deltas[f"stage:{name}"])
        if not isfinite(delta):
            raise ValueError("ecart de victoire non fini dans le suivi adaptatif")
        deficit = max(0.0, -delta - maximum_stage_regression)
        smoothed = (previous_deficit + deficit) / 2
        weaknesses[name] = smoothed if smoothed >= 0.005 else 0.0
    return dict(bot_fraction=ratio, streak=streak, stage_deficits=weaknesses)


class AdaptiveOpponents:
    """Keep the sampling controller in the same checkpoint as the learner."""

    def _initialize_opponent_sampling(self):
        settings = self.config["phase5"].get("adaptive_opponents")
        if settings is None or "opponent_sampling" in self.phase5_state:
            return
        stages = self.curriculum.stages
        focus = {stage.name for stage in stages[-2:]}
        self.phase5_state["opponent_sampling"] = dict(
            bot_fraction=float(settings["initial_bot_fraction"]),
            streak=0,
            stage_deficits={stage.name: 0.10 if stage.name in focus else 0.0 for stage in stages},
            activation_update=self._resume_update,
            next_update=self._resume_update + int(settings["every_updates"]),
        )

    def _apply_opponent_sampling(self):
        weights = dict(self.config["phase5"]["training_weights"])
        state = self.phase5_state.get("opponent_sampling")
        if state is not None:
            categories = {entry.category for entry in self.league.entries}
            active = {name: weights[name] for name in categories if name in weights}
            total = sum(active.values())
            ratio = state["bot_fraction"]
            weights = {name: weight / total * (1 - ratio) for name, weight in active.items()}
            weights["godot"] = ratio
            deficits = state["stage_deficits"]
            total_deficit = sum(deficits.values())
            if total_deficit:
                uniform = 0.5 / len(deficits)
                self.league.bot_stage_weights = [
                    uniform + 0.5 * deficits[stage.name] / total_deficit
                    for stage in self.league.godot_stages
                ]
            else:
                self.league.bot_stage_weights = None
        self.league.set_weights(weights)

    def _evaluate_opponent_sampling(self, step, update, evaluation):
        state = self.phase5_state.get("opponent_sampling")
        if state is None or update < state["next_update"]:
            return
        settings = self.config["phase5"]["adaptive_opponents"]
        # Replaying this update after interruption reuses the same weights,
        # seeds and completed matches in the arena's tournament ledger.
        self._save("latest.pt", step, evaluation, update)
        self._publish_phase5(operation="bot_followup")
        report = self.arena.retention(
            self.arena.live_actor(),
            self.phase4_baseline,
            int(settings["games_per_slice"]),
            self._phase5_seed(7, update),
            "bot_followup",
        )
        state.update(
            update_sampling(
                state,
                settings,
                report,
                float(self.config["phase5"]["retention"]["maximum_stage_regression"]),
            )
        )
        state["next_update"] = update + int(settings["every_updates"])
        self._apply_opponent_sampling()
        self._save("latest.pt", step, evaluation, update)
        self.tracker.log(
            "phase5_bot_followup",
            step,
            dict(
                passed=report["passed"],
                bot_fraction=state["bot_fraction"],
                win_rate_deltas=report["win_rate_deltas"],
                stage_weights=dict(
                    zip(
                        state["stage_deficits"],
                        self.league.bot_stage_weights
                        or [1 / len(state["stage_deficits"])] * len(state["stage_deficits"]),
                        strict=True,
                    )
                ),
            ),
            dict(update=update),
        )
