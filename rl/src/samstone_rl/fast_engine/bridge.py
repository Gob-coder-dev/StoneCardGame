from __future__ import annotations

from pathlib import Path
from typing import Any

from .catalog import StoneCatalog
from .core import FastSimulator


class FastEngineBridge:
    """GodotProcess-compatible in-process bridge.

    Keeping the same contract lets Gym/PPO switch backends without changing
    observations, action ids, rewards, checkpoints, or opponent classes.
    """

    def __init__(self, project_path: str | Path | None = None, **_unused: Any) -> None:
        root = Path(project_path) if project_path else None
        self.catalog = StoneCatalog(root)
        self.simulator = FastSimulator(self.catalog)
        self.process: bool | None = True  # SamStoneEnv lifecycle marker; no subprocess exists

    def start(self) -> None:
        self.process = True

    def reset(self, config: dict[str, Any], observer: int) -> dict[str, Any]:
        extra = self.simulator.reset(config)
        return self._snapshot(observer, extra)

    def step(self, action: dict[str, Any], observer: int) -> dict[str, Any]:
        return self._snapshot(observer, self.simulator.step(action))

    def get_state(self, observer: int) -> dict[str, Any]:
        return self._snapshot(observer)

    def legal_actions(self) -> list[dict[str, Any]]:
        return self.simulator.legal_actions()

    def choose_profile_action(self, precision: float, anticipation: bool) -> dict[str, Any]:
        return self.simulator.choose_profile_action(float(precision), bool(anticipation))

    def tactical_action_scores(self, observer: int) -> dict[int, tuple[float, ...]]:
        return self.simulator.tactical_action_scores(observer)

    def engine_manifest(self) -> dict[str, Any]:
        return {"protocol_version": 2, "observation_schema": 1,
                "catalogue_checksum": self.catalog.checksum,
                "game_version": "fast-python-1", "godot_version": "in-process",
                "backend": "python"}

    def close(self) -> None:
        self.process = None

    def _snapshot(self, observer: int, extra: dict[str, Any] | None = None) -> dict[str, Any]:
        result = dict(extra or {})
        result["observation"] = self.simulator.serialize_for_player(observer)
        result["legal_actions"] = self.simulator.legal_actions()
        return result
