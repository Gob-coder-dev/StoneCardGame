from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol

import numpy as np


class Opponent(Protocol):
    def begin_episode(self, rng: np.random.Generator) -> None: ...

    def choose(self, bridge: Any, legal_actions: list[dict[str, Any]],
               rng: np.random.Generator, player: int) -> dict[str, Any]: ...


@dataclass(frozen=True)
class RandomOpponent:
    def begin_episode(self, rng: np.random.Generator) -> None:
        del rng

    def choose(self, bridge: Any, legal_actions: list[dict[str, Any]],
               rng: np.random.Generator, player: int) -> dict[str, Any]:
        del bridge, player
        if not legal_actions:
            raise RuntimeError("l'adversaire n'a aucun coup legal")
        return legal_actions[int(rng.integers(len(legal_actions)))]


@dataclass(frozen=True)
class GodotProfileOpponent:
    precision: float
    anticipation: bool = False
    anticipation_probability: float | None = None

    def __post_init__(self) -> None:
        if not 0.0 <= self.precision <= 1.0:
            raise ValueError("precision doit etre comprise entre 0 et 1")
        if (self.anticipation_probability is not None
                and not 0.0 <= self.anticipation_probability <= 1.0):
            raise ValueError("anticipation_probability doit etre comprise entre 0 et 1")

    def begin_episode(self, rng: np.random.Generator) -> None:
        del rng

    def choose(self, bridge: Any, legal_actions: list[dict[str, Any]],
               rng: np.random.Generator, player: int) -> dict[str, Any]:
        del legal_actions, player
        probability = self.anticipation_probability
        if probability is None:
            use_anticipation = self.anticipation
        elif probability <= 0.0:
            use_anticipation = False
        elif probability >= 1.0:
            use_anticipation = True
        else:
            use_anticipation = bool(rng.random() < probability)
        return bridge.choose_profile_action(self.precision, use_anticipation)
