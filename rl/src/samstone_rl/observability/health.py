from __future__ import annotations

import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from statistics import median
from typing import Any, ClassVar


@dataclass(frozen=True, slots=True)
class HealthAlert:
    step: int
    severity: str
    code: str
    message: str
    recommendation: str
    value: float | None = None
    threshold: float | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class TrainingHealthError(RuntimeError):
    def __init__(self, alerts: tuple[HealthAlert, ...]) -> None:
        self.alerts = alerts
        super().__init__("; ".join(alert.message for alert in alerts))


class HealthMonitor:
    DEFAULTS: ClassVar[dict[str, float | int]] = {
        "target_kl": 0.02,
        "maximum_clip_fraction": 0.30,
        "minimum_normalized_entropy": 0.08,
        "minimum_explained_variance": -0.10,
        "maximum_throughput_drop": 0.35,
        "maximum_eval_regression": 0.05,
        "maximum_reward_divergence": 0.25,
        "minimum_anchor_win_rate": 0.80,
        "plateau_evaluations": 5,
        "consecutive_updates": 3,
    }

    def __init__(self, directory: str | Path, settings: dict[str, Any] | None = None) -> None:
        self.directory = Path(directory).resolve()
        self.directory.mkdir(parents=True, exist_ok=True)
        self.path = self.directory / "health_state.json"
        self.settings = {**self.DEFAULTS, **(settings or {})}
        self.best_eval = -1.0
        self.no_improvement = 0
        self.sps_baseline: list[float] = []
        self.consecutive: dict[str, int] = {}
        self.last_training_return: float | None = None
        self.return_at_best_eval: float | None = None
        self._load()

    def check(self, step: int, metrics: dict[str, Any]) -> tuple[HealthAlert, ...]:
        alerts: list[HealthAlert] = []
        numeric = {key: float(value) for key, value in metrics.items()
                   if isinstance(value, (bool, int, float))}
        for key, value in numeric.items():
            if not math.isfinite(value):
                alerts.append(HealthAlert(
                    step, "critical", "non_finite_metric",
                    f"La métrique {key} n'est pas finie.",
                    "Arrêter le run, restaurer le dernier checkpoint sain et vérifier récompenses et gradients."))
        illegal = numeric.get("illegal_actions", 0.0)
        if illegal > 0:
            alerts.append(HealthAlert(
                step, "critical", "illegal_action",
                "Une action illégale a été observée.",
                "Vérifier immédiatement le masque d'actions et le codec Python/Godot.", illegal, 0.0))
        if "episode_return_mean" in numeric:
            self.last_training_return = numeric["episode_return_mean"]

        self._consecutive_warning(
            alerts, step, "high_kl", numeric.get("approx_kl"),
            lambda value: value > float(self.settings["target_kl"]),
            float(self.settings["target_kl"]),
            "La divergence KL est durablement trop élevée.",
            "Réduire le learning rate ou le nombre d'époques PPO.")
        self._consecutive_warning(
            alerts, step, "high_clip_fraction", numeric.get("clip_fraction"),
            lambda value: value > float(self.settings["maximum_clip_fraction"]),
            float(self.settings["maximum_clip_fraction"]),
            "Une part trop importante des mises à jour PPO est tronquée.",
            "Réduire le learning rate, les époques PPO ou augmenter la taille des rollouts.")
        self._consecutive_warning(
            alerts, step, "entropy_collapse", numeric.get("normalized_entropy"),
            lambda value: value < float(self.settings["minimum_normalized_entropy"]),
            float(self.settings["minimum_normalized_entropy"]),
            "L'exploration de la politique s'est effondrée.",
            "Augmenter légèrement entropy_coef et vérifier que la promotion n'est pas trop rapide.")
        self._consecutive_warning(
            alerts, step, "poor_value_fit", numeric.get("explained_variance"),
            lambda value: value < float(self.settings["minimum_explained_variance"]),
            float(self.settings["minimum_explained_variance"]),
            "Le critique prédit mal les retours.",
            "Vérifier l'échelle des récompenses, value_coef et la longueur des rollouts.")

        sps = numeric.get("steps_per_second")
        if sps is not None and sps > 0:
            if len(self.sps_baseline) < 5:
                self.sps_baseline.append(sps)
            else:
                baseline = median(self.sps_baseline)
                floor = baseline * (1.0 - float(self.settings["maximum_throughput_drop"]))
                if sps < floor:
                    alerts.append(HealthAlert(
                        step, "warning", "throughput_drop",
                        "Le débit du simulateur a fortement baissé.",
                        "Contrôler les processus Godot, la mémoire, la température CPU et la taille des logs.",
                        sps, floor))

        eval_rate = numeric.get("evaluation_win_rate")
        if eval_rate is not None:
            if eval_rate > self.best_eval + 1e-12:
                self.best_eval = eval_rate
                self.no_improvement = 0
                self.return_at_best_eval = self.last_training_return
            else:
                self.no_improvement += 1
            regression = self.best_eval - eval_rate
            if regression > float(self.settings["maximum_eval_regression"]):
                alerts.append(HealthAlert(
                    step, "warning", "evaluation_regression",
                    "La politique régresse sur les seeds d'évaluation.",
                    "Comparer au meilleur checkpoint et réintroduire davantage d'adversaires historiques.",
                    regression, float(self.settings["maximum_eval_regression"])))
            if self.no_improvement >= int(self.settings["plateau_evaluations"]):
                alerts.append(HealthAlert(
                    step, "warning", "evaluation_plateau",
                    "Le taux de victoire d'évaluation ne progresse plus.",
                    "Inspecter entropie, KL et matchups avant d'augmenter la durée du run.",
                    float(self.no_improvement), float(self.settings["plateau_evaluations"])))
                self.no_improvement = 0
            if (self.last_training_return is not None and self.return_at_best_eval is not None
                    and self.last_training_return - self.return_at_best_eval
                    > float(self.settings["maximum_reward_divergence"])
                    and eval_rate < self.best_eval + 1e-12):
                alerts.append(HealthAlert(
                    step, "warning", "reward_misalignment",
                    "La récompense d'entraînement augmente sans gain d'évaluation.",
                    "Inspecter séparément captures et victoire; réduire le shaping s'il est exploité.",
                    self.last_training_return - self.return_at_best_eval,
                    float(self.settings["maximum_reward_divergence"])))
        anchor_rate = numeric.get("historical_win_rate")
        if (anchor_rate is not None
                and anchor_rate < float(self.settings["minimum_anchor_win_rate"])):
            alerts.append(HealthAlert(
                step, "warning", "historical_regression",
                "La politique oublie au moins un ancien palier.",
                "Augmenter replay_probability ou le poids des adversaires historiques.",
                anchor_rate, float(self.settings["minimum_anchor_win_rate"])))
        self._save()
        return tuple(alerts)

    @staticmethod
    def critical(alerts: tuple[HealthAlert, ...]) -> tuple[HealthAlert, ...]:
        return tuple(alert for alert in alerts if alert.severity == "critical")

    def _consecutive_warning(self, alerts: list[HealthAlert], step: int, code: str,
                             value: float | None, predicate, threshold: float,
                             message: str, recommendation: str) -> None:
        if value is None:
            return
        self.consecutive[code] = self.consecutive.get(code, 0) + 1 if predicate(value) else 0
        if self.consecutive[code] >= int(self.settings["consecutive_updates"]):
            alerts.append(HealthAlert(step, "warning", code, message, recommendation,
                                      value, threshold))
            self.consecutive[code] = 0

    def _load(self) -> None:
        if not self.path.is_file():
            return
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
            if payload.get("schema_version") != 1:
                return
            self.best_eval = float(payload.get("best_eval", -1.0))
            self.no_improvement = int(payload.get("no_improvement", 0))
            self.sps_baseline = [float(value) for value in payload.get("sps_baseline", [])]
            self.consecutive = {str(key): int(value)
                                for key, value in payload.get("consecutive", {}).items()}
            raw_return = payload.get("last_training_return")
            self.last_training_return = None if raw_return is None else float(raw_return)
            raw_best_return = payload.get("return_at_best_eval")
            self.return_at_best_eval = None if raw_best_return is None else float(raw_best_return)
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            return

    def _save(self) -> None:
        payload = {
            "schema_version": 1,
            "best_eval": self.best_eval,
            "no_improvement": self.no_improvement,
            "sps_baseline": self.sps_baseline,
            "consecutive": self.consecutive,
            "last_training_return": self.last_training_return,
            "return_at_best_eval": self.return_at_best_eval,
        }
        temporary = self.path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        temporary.replace(self.path)
