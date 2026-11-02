from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import asdict, dataclass
from typing import Any

import numpy as np

from samstone_rl.opponents import GodotProfileOpponent
from samstone_rl.training.validation import wilson_lower


@dataclass(frozen=True)
class CurriculumStage:
    name: str
    precision: float
    anticipation: bool
    anticipation_probability: float | None = None

    def __post_init__(self) -> None:
        if not self.name:
            raise ValueError("le nom du palier ne peut pas etre vide")
        if not 0.0 <= self.precision <= 1.0:
            raise ValueError("la precision doit etre comprise entre 0 et 1")
        if (self.anticipation_probability is not None
                and not 0.0 <= self.anticipation_probability <= 1.0):
            raise ValueError("la probabilite d'anticipation doit etre comprise entre 0 et 1")

    def opponent(self) -> GodotProfileOpponent:
        return GodotProfileOpponent(
            self.precision, self.anticipation, self.anticipation_probability)

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any]) -> CurriculumStage:
        probability = value.get("anticipation_probability")
        return cls(
            name=str(value.get("name", "")),
            precision=float(value.get("precision", 0.0)),
            anticipation=bool(value.get("anticipation", False)),
            anticipation_probability=(None if probability is None else float(probability)),
        )


DEFAULT_STAGES = (
    CurriculumStage("precision_0", 0.0, False),
    CurriculumStage("precision_025", 0.25, False),
    CurriculumStage("precision_050", 0.5, False),
    CurriculumStage("precision_100", 1.0, False),
    CurriculumStage("precision_100_anticipation", 1.0, True),
)


def stages_from_config(values: Sequence[Mapping[str, Any]] | None) -> tuple[CurriculumStage, ...]:
    """Build an explicit curriculum while keeping legacy configs unchanged."""
    if values is None:
        return DEFAULT_STAGES
    stages = tuple(CurriculumStage.from_mapping(value) for value in values)
    if not stages:
        raise ValueError("curriculum.stages doit contenir au moins un palier")
    names = [stage.name for stage in stages]
    if len(names) != len(set(names)):
        raise ValueError("les noms des paliers du curriculum doivent etre uniques")
    return stages


class CurriculumManager:
    """Promote only on held-out evaluation and replay older opponents."""

    def __init__(self, target_win_rate: float = 0.95, confidence_floor: float = 0.90,
                 replay_probability: float = 0.20,
                 stages: tuple[CurriculumStage, ...] = DEFAULT_STAGES,
                 god_sampling: Mapping[str, Any] | None = None,
                 terrain_sampling: Mapping[str, Any] | None = None,
                 maximum_loss_rate: float | None = None,
                 non_loss_confidence_floor: float | None = None,
                 promotion_confirmations: int = 1) -> None:
        self.target_win_rate = target_win_rate
        self.confidence_floor = confidence_floor
        self.replay_probability = replay_probability
        self.stages = stages
        self.stage_index = 0
        self.awaiting_final_validation = False
        self.completed = False
        self.promotion_confirmations = int(promotion_confirmations)
        self.consecutive_promotion_successes = 0
        self.maximum_loss_rate = (None if maximum_loss_rate is None
                                  else float(maximum_loss_rate))
        self.non_loss_confidence_floor = (None if non_loss_confidence_floor is None
                                          else float(non_loss_confidence_floor))
        if self.maximum_loss_rate is not None and not 0 <= self.maximum_loss_rate <= 1:
            raise ValueError("maximum_loss_rate doit etre entre 0 et 1")
        if self.non_loss_confidence_floor is not None and not 0 < self.non_loss_confidence_floor <= 1:
            raise ValueError("non_loss_confidence_floor doit etre entre 0 et 1")
        if self.promotion_confirmations <= 0:
            raise ValueError("promotion_confirmations doit etre strictement positif")
        sampling = dict(god_sampling or {})
        self.god_sampling_enabled = bool(sampling.get("enabled", False))
        self.god_sampling_target = float(sampling.get("target_wilson", confidence_floor))
        self.god_sampling_minimum = float(sampling.get("minimum_multiplier", 0.60))
        self.god_sampling_maximum = float(sampling.get("maximum_multiplier", 2.20))
        self.god_sampling_exponent = float(sampling.get("deficit_exponent", 1.0))
        self.god_sampling_smoothing = float(sampling.get("smoothing", 0.35))
        if self.god_sampling_enabled:
            if not 0 < self.god_sampling_target <= 1:
                raise ValueError("god_sampling.target_wilson doit etre entre 0 et 1")
            if not 0 < self.god_sampling_minimum <= self.god_sampling_maximum:
                raise ValueError("les multiplicateurs god_sampling sont invalides")
            if self.god_sampling_exponent <= 0 or not 0 < self.god_sampling_smoothing <= 1:
                raise ValueError("deficit_exponent et smoothing doivent etre strictement positifs")
        self._god_names: tuple[str, ...] = ()
        self._god_weights: dict[str, float] = {}
        self._god_wilson: dict[str, float] = {}
        terrain = dict(terrain_sampling or {})
        self.terrain_sampling_enabled = bool(terrain.get("enabled", False))
        self.terrain_sampling_target = float(terrain.get("target_wilson", confidence_floor))
        self.terrain_sampling_minimum = float(terrain.get("minimum_multiplier", 0.70))
        self.terrain_sampling_maximum = float(terrain.get("maximum_multiplier", 1.80))
        self.terrain_sampling_exponent = float(terrain.get("deficit_exponent", 1.0))
        self.terrain_sampling_smoothing = float(terrain.get("smoothing", 0.35))
        self.terrain_sampling_max_attempts = int(terrain.get("max_reset_attempts", 12))
        values = terrain.get("blocked_counts", (0, 1, 2))
        self._terrain_values = tuple(dict.fromkeys(int(value) for value in values))
        if self.terrain_sampling_enabled:
            if not self._terrain_values or min(self._terrain_values) < 0:
                raise ValueError("terrain_sampling.blocked_counts est invalide")
            if not 0 < self.terrain_sampling_target <= 1:
                raise ValueError("terrain_sampling.target_wilson doit etre entre 0 et 1")
            if not 0 < self.terrain_sampling_minimum <= self.terrain_sampling_maximum:
                raise ValueError("les multiplicateurs terrain_sampling sont invalides")
            if self.terrain_sampling_exponent <= 0 or not 0 < self.terrain_sampling_smoothing <= 1:
                raise ValueError("deficit_exponent et smoothing terrain_sampling sont invalides")
            if self.terrain_sampling_max_attempts <= 0:
                raise ValueError("max_reset_attempts doit etre strictement positif")
        self._terrain_weights = self._normalize_weights(
            {str(value): 1.0 for value in self._terrain_values})
        self._terrain_wilson = {str(value): 0.0 for value in self._terrain_values}

    @property
    def current(self) -> CurriculumStage:
        return self.stages[self.stage_index]

    @property
    def phase_five_ready(self) -> bool:
        return self.completed

    def training_stage(self, rng: np.random.Generator) -> CurriculumStage:
        if self.stage_index > 0 and rng.random() < self.replay_probability:
            return self.stages[int(rng.integers(0, self.stage_index))]
        return self.current

    def initialize_god_sampling(self, gods: Sequence[str]) -> None:
        names = tuple(dict.fromkeys(str(god) for god in gods if str(god)))
        if not names:
            raise ValueError("god_sampling requiert au moins un dieu")
        self._god_names = names
        self._god_weights = self._normalize_weights({
            name: self._god_weights.get(name, 1.0) for name in names})
        self._god_wilson = {name: self._god_wilson.get(name, 0.0) for name in names}

    def sample_scenario_index(self, scenarios: Sequence[Mapping[str, Any]],
                              rng: np.random.Generator) -> int:
        if not scenarios:
            raise ValueError("au moins un scenario est requis")
        if not self.god_sampling_enabled:
            return int(rng.integers(len(scenarios)))
        by_god: dict[str, list[int]] = {}
        for index, scenario in enumerate(scenarios):
            god = str(scenario.get("god", ""))
            if god:
                by_god.setdefault(god, []).append(index)
        self.initialize_god_sampling(tuple(by_god))
        gods = tuple(by_god)
        weights = np.asarray([self._god_weights[god] for god in gods], dtype=np.float64)
        selected_god = gods[int(rng.choice(len(gods), p=weights / weights.sum()))]
        candidates = by_god[selected_god]
        return candidates[int(rng.integers(len(candidates)))]

    def update_god_sampling(self, by_god: Mapping[str, Mapping[str, Any]]) -> dict[str, Any]:
        """Raise exposure only for gods whose held-out Wilson score is weakest."""
        if not self.god_sampling_enabled:
            return {}
        self.initialize_god_sampling(tuple(by_god))
        observed = {
            god: float(by_god.get(god, {}).get("wilson_lower", self._god_wilson.get(god, 0.0)))
            for god in self._god_names
        }
        deficits = {god: max(0.0, self.god_sampling_target - score)
                    for god, score in observed.items()}
        largest = max(deficits.values(), default=0.0)
        if largest <= 1e-12:
            desired = {god: 1.0 for god in self._god_names}
        else:
            spread = self.god_sampling_maximum - self.god_sampling_minimum
            desired = {
                god: self.god_sampling_minimum + spread * (deficit / largest) ** self.god_sampling_exponent
                for god, deficit in deficits.items()
            }
        desired = self._normalize_weights(desired)
        self._god_weights = self._normalize_weights({
            god: (1.0 - self.god_sampling_smoothing) * self._god_weights[god]
            + self.god_sampling_smoothing * desired[god]
            for god in self._god_names
        })
        self._god_wilson = observed
        return self.god_sampling_metrics()

    def god_sampling_metrics(self, sampled: Mapping[str, int] | None = None) -> dict[str, Any]:
        if not self.god_sampling_enabled:
            return {}
        metrics: dict[str, Any] = {
            "weights": dict(sorted(self._god_weights.items())),
            "wilson_lower": dict(sorted(self._god_wilson.items())),
        }
        if sampled is not None:
            metrics["episodes"] = {god: int(sampled.get(god, 0)) for god in self._god_names}
        return metrics

    def sample_blocked_count(self, rng: np.random.Generator) -> int | None:
        if not self.terrain_sampling_enabled:
            return None
        values = tuple(str(value) for value in self._terrain_values)
        weights = np.asarray([self._terrain_weights[value] for value in values], dtype=np.float64)
        return int(values[int(rng.choice(len(values), p=weights / weights.sum()))])

    def update_terrain_sampling(self, by_blocked_count: Mapping[str, Mapping[str, Any]]) -> dict[str, Any]:
        if not self.terrain_sampling_enabled:
            return {}
        names = tuple(str(value) for value in self._terrain_values)
        observed = {
            name: float(by_blocked_count.get(name, {}).get(
                "wilson_lower", self._terrain_wilson.get(name, 0.0)))
            for name in names
        }
        desired = self._adaptive_weights(
            names, observed, self.terrain_sampling_target,
            self.terrain_sampling_minimum, self.terrain_sampling_maximum,
            self.terrain_sampling_exponent)
        self._terrain_weights = self._normalize_weights({
            name: (1.0 - self.terrain_sampling_smoothing) * self._terrain_weights[name]
            + self.terrain_sampling_smoothing * desired[name]
            for name in names
        })
        self._terrain_wilson = observed
        return self.terrain_sampling_metrics()

    def terrain_sampling_metrics(self, sampled: Mapping[str, int] | None = None,
                                 reset_attempts: int = 0) -> dict[str, Any]:
        if not self.terrain_sampling_enabled:
            return {}
        metrics: dict[str, Any] = {
            "weights": dict(sorted(self._terrain_weights.items())),
            "wilson_lower": dict(sorted(self._terrain_wilson.items())),
        }
        if sampled is not None:
            metrics["episodes"] = {
                str(value): int(sampled.get(str(value), 0)) for value in self._terrain_values}
            metrics["reset_attempts"] = int(reset_attempts)
        return metrics

    def promotion_metrics(self, wins: int, draws: int, games: int) -> dict[str, float | bool | int]:
        losses = games - wins - draws
        if games <= 0 or losses < 0:
            return {"win_rate": 0.0, "loss_rate": 1.0, "non_loss_rate": 0.0,
                    "non_loss_wilson_lower": 0.0, "eligible": False,
                    "promotion_confirmations": self.promotion_confirmations,
                    "consecutive_promotion_successes": self.consecutive_promotion_successes}
        win_rate = wins / games
        loss_rate = losses / games
        non_losses = wins + draws
        non_loss_rate = non_losses / games
        non_loss_lower = wilson_lower(non_losses, games)
        if self.maximum_loss_rate is None or self.non_loss_confidence_floor is None:
            eligible = win_rate >= self.target_win_rate and wilson_lower(wins, games) >= self.confidence_floor
        else:
            eligible = (win_rate >= self.target_win_rate
                        and loss_rate <= self.maximum_loss_rate
                        and non_loss_lower >= self.non_loss_confidence_floor)
        return {"win_rate": win_rate, "loss_rate": loss_rate, "non_loss_rate": non_loss_rate,
                "non_loss_wilson_lower": non_loss_lower, "eligible": eligible,
                "promotion_confirmations": self.promotion_confirmations,
                "consecutive_promotion_successes": self.consecutive_promotion_successes}

    def consider_promotion(self, wins: int, games: int, draws: int = 0) -> bool:
        if games <= 0 or self.completed or self.awaiting_final_validation:
            return False
        if not bool(self.promotion_metrics(wins, draws, games)["eligible"]):
            # A failed held-out evaluation breaks the confirmation streak. This
            # prevents an old good result from validating a later regression.
            self.consecutive_promotion_successes = 0
            return False
        self.consecutive_promotion_successes += 1
        if self.consecutive_promotion_successes < self.promotion_confirmations:
            return False
        self.consecutive_promotion_successes = 0
        if self.stage_index == len(self.stages) - 1:
            self.awaiting_final_validation = True
        else:
            self.stage_index += 1
        return True

    def accept_final_validation(self, passed: bool) -> bool:
        if not self.awaiting_final_validation or self.stage_index != len(self.stages) - 1:
            return False
        if passed:
            self.completed = True
            self.awaiting_final_validation = False
        return self.completed

    def state_dict(self) -> dict:
        return {"stage_index": self.stage_index, "awaiting_final_validation": self.awaiting_final_validation,
                "completed": self.completed, "current": asdict(self.current),
                "target_win_rate": self.target_win_rate,
                "confidence_floor": self.confidence_floor,
                "maximum_loss_rate": self.maximum_loss_rate,
                "non_loss_confidence_floor": self.non_loss_confidence_floor,
                "promotion_confirmations": self.promotion_confirmations,
                "consecutive_promotion_successes": self.consecutive_promotion_successes,
                "replay_probability": self.replay_probability,
                "god_sampling": {
                    "weights": self._god_weights,
                    "wilson_lower": self._god_wilson,
                },
                "terrain_sampling": {
                    "weights": self._terrain_weights,
                    "wilson_lower": self._terrain_wilson,
                }}

    def load_state_dict(self, state: Mapping[str, Any]) -> None:
        self.stage_index = int(state.get("stage_index", 0))
        self.awaiting_final_validation = bool(state.get("awaiting_final_validation", False))
        self.completed = bool(state.get("completed", False))
        self.consecutive_promotion_successes = min(
            max(0, int(state.get("consecutive_promotion_successes", 0))),
            self.promotion_confirmations - 1)
        sampling = state.get("god_sampling", {})
        if self.god_sampling_enabled and isinstance(sampling, Mapping):
            weights = sampling.get("weights", {})
            lower = sampling.get("wilson_lower", {})
            if isinstance(weights, Mapping):
                self._god_weights = {str(key): float(value) for key, value in weights.items()}
            if isinstance(lower, Mapping):
                self._god_wilson = {str(key): float(value) for key, value in lower.items()}
        terrain = state.get("terrain_sampling", {})
        if self.terrain_sampling_enabled and isinstance(terrain, Mapping):
            weights = terrain.get("weights", {})
            lower = terrain.get("wilson_lower", {})
            expected = {str(value) for value in self._terrain_values}
            if isinstance(weights, Mapping):
                self._terrain_weights = self._normalize_weights({
                    name: float(weights.get(name, 1.0)) for name in expected})
            if isinstance(lower, Mapping):
                self._terrain_wilson = {name: float(lower.get(name, 0.0)) for name in expected}

    @staticmethod
    def _normalize_weights(weights: Mapping[str, float]) -> dict[str, float]:
        if not weights:
            return {}
        positive = {str(name): max(float(value), 1e-12) for name, value in weights.items()}
        mean = sum(positive.values()) / len(positive)
        return {name: value / mean for name, value in positive.items()}

    @classmethod
    def _adaptive_weights(cls, names: Sequence[str], observed: Mapping[str, float], target: float,
                          minimum: float, maximum: float, exponent: float) -> dict[str, float]:
        deficits = {name: max(0.0, target - observed[name]) for name in names}
        largest = max(deficits.values(), default=0.0)
        if largest <= 1e-12:
            return {name: 1.0 for name in names}
        spread = maximum - minimum
        return cls._normalize_weights({
            name: minimum + spread * (deficit / largest) ** exponent
            for name, deficit in deficits.items()
        })

