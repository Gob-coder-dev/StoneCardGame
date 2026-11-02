from __future__ import annotations

import json
import shutil
from collections import Counter
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path

import numpy as np

from samstone_rl.opponents import Opponent
from samstone_rl.opponents.checkpoint import CheckpointOpponent
from samstone_rl.training.curriculum import DEFAULT_STAGES


@dataclass(frozen=True)
class LeagueEntry:
    name: str
    path: str
    category: str
    global_step: int
    score: float


class SelfPlayLeague:
    """Persistent frozen-checkpoint league; one opponent is sampled per episode."""

    def __init__(self, directory: str | Path, weights: dict[str, float], device: str = "cpu") -> None:
        self.directory = Path(directory).resolve()
        self.directory.mkdir(parents=True, exist_ok=True)
        self.manifest_path = self.directory / "manifest.json"
        self.weights = weights
        self.device = device
        self.entries = self._load_manifest()
        self._cache: dict[str, CheckpointOpponent] = {}
        self.selection_counts: Counter[str] = Counter()
        self.ratings_path = self.directory / "ratings.json"
        self.results_path = self.directory / "results.jsonl"
        self.ratings = self._load_ratings()

    def register(self, checkpoint_path: str | Path, global_step: int, score: float,
                 category: str = "recent") -> LeagueEntry:
        if category not in {"current", "recent", "historical", "best"}:
            raise ValueError(f"categorie de ligue inconnue: {category}")
        source = Path(checkpoint_path).resolve()
        if not source.is_file():
            raise FileNotFoundError(source)
        name = f"step_{global_step:012d}_{category}.pt"
        destination = self.directory / name
        if source != destination:
            shutil.copy2(source, destination)
        entry = LeagueEntry(name, name, category, int(global_step), float(score))
        self.entries = [item for item in self.entries if item.name != name]
        if category == "current":
            self.entries = [LeagueEntry(item.name, item.path, "recent", item.global_step, item.score)
                            if item.category == "current" else item for item in self.entries]
        if category == "best":
            self.entries = [item for item in self.entries if item.category != "best"]
        self.entries.append(entry)
        self._save_manifest()
        return entry

    def set_weights(self, weights: dict[str, float]) -> None:
        self.weights = {name: float(value) for name, value in weights.items()}

    def reclassify(self, name: str, category: str) -> None:
        if category not in {"recent", "historical"}:
            raise ValueError(f"categorie de ligue inconnue: {category}")
        if not any(item.name == name for item in self.entries):
            raise KeyError(name)
        self.entries = [LeagueEntry(item.name, item.path, category,
                                    item.global_step, item.score)
                        if item.name == name else item for item in self.entries]
        self._save_manifest()

    def sample(self, rng: np.random.Generator) -> Opponent:
        opponent, _name, _category = self.sample_with_metadata(rng)
        return opponent

    def sample_with_metadata(self, rng: np.random.Generator) -> tuple[Opponent, str, str]:
        pools: dict[str, list[LeagueEntry | None]] = {
            category: [entry for entry in self.entries if entry.category == category]
            for category in ("current", "recent", "historical", "best")
        }
        pools["godot"] = [None]
        available = [(name, members, float(self.weights.get(name, 0.0)))
                     for name, members in pools.items() if members and self.weights.get(name, 0.0) > 0.0]
        if not available:
            raise RuntimeError("la ligue ne contient aucun adversaire echantillonnable")
        probabilities = np.asarray([item[2] for item in available], dtype=np.float64)
        probabilities /= probabilities.sum()
        category, members, _weight = available[int(rng.choice(len(available), p=probabilities))]
        self.selection_counts[category] += 1
        if category == "godot":
            stage = DEFAULT_STAGES[int(rng.integers(len(DEFAULT_STAGES)))]
            return stage.opponent(), f"godot_{stage.name}", category
        entry = members[int(rng.integers(len(members)))]
        assert entry is not None
        checkpoint_path = self.directory / entry.path
        cache_key = str(checkpoint_path)
        if cache_key not in self._cache:
            self._cache[cache_key] = CheckpointOpponent(checkpoint_path, self.device, deterministic=False)
        return self._cache[cache_key], entry.name, category

    def metrics_snapshot(self, reset_samples: bool = False) -> dict:
        categories = ("current", "recent", "historical", "best", "godot")
        metrics = {
            "entries": {category: sum(item.category == category for item in self.entries)
                        for category in categories if category != "godot"},
            "weights": {category: float(self.weights.get(category, 0.0))
                        for category in categories},
            "samples": {category: int(self.selection_counts.get(category, 0))
                        for category in categories},
            "ratings": dict(self.ratings),
        }
        if reset_samples:
            self.selection_counts.clear()
        return metrics

    def record_result(self, agent_id: str, opponent_id: str, score: float,
                      global_step: int, context: dict | None = None,
                      k_factor: float = 32.0) -> dict[str, float]:
        if score not in (0.0, 0.5, 1.0):
            raise ValueError("score Elo doit valoir 0, 0.5 ou 1")
        agent_rating = float(self.ratings.get(agent_id, 1500.0))
        opponent_rating = float(self.ratings.get(opponent_id, 1500.0))
        expected = 1.0 / (1.0 + 10.0 ** ((opponent_rating - agent_rating) / 400.0))
        delta = float(k_factor) * (score - expected)
        self.ratings[agent_id] = agent_rating + delta
        self.ratings[opponent_id] = opponent_rating - delta
        temporary = self.ratings_path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps({"version": 1, "ratings": self.ratings}, indent=2),
                             encoding="utf-8")
        temporary.replace(self.ratings_path)
        event = {
            "version": 1,
            "timestamp": datetime.now(UTC).isoformat(),
            "global_step": int(global_step),
            "agent_id": agent_id,
            "opponent_id": opponent_id,
            "score": score,
            "rating_delta": delta,
            "agent_rating": self.ratings[agent_id],
            "opponent_rating": self.ratings[opponent_id],
            "context": context or {},
        }
        with self.results_path.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(event, ensure_ascii=False) + "\n")
        return {"agent_rating": self.ratings[agent_id],
                "opponent_rating": self.ratings[opponent_id], "rating_delta": delta}

    def _load_manifest(self) -> list[LeagueEntry]:
        if not self.manifest_path.is_file():
            return []
        data = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        return [LeagueEntry(**item) for item in data.get("entries", [])
                if (self.directory / item["path"]).is_file()]

    def _save_manifest(self) -> None:
        temporary = self.manifest_path.with_suffix(".tmp")
        temporary.write_text(json.dumps({"version": 1, "entries": [asdict(item) for item in self.entries]},
                                        indent=2), encoding="utf-8")
        temporary.replace(self.manifest_path)

    def _load_ratings(self) -> dict[str, float]:
        if not self.ratings_path.is_file():
            return {}
        try:
            payload = json.loads(self.ratings_path.read_text(encoding="utf-8"))
            return {str(name): float(value) for name, value in payload.get("ratings", {}).items()}
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            return {}


class LeagueOpponent:
    """Select once at reset, then delegate every move of the episode."""

    def __init__(self, league: SelfPlayLeague) -> None:
        self.league = league
        self.selected: Opponent | None = None
        self.selected_name = ""
        self.selected_category = ""

    def begin_episode(self, rng: np.random.Generator) -> None:
        self.selected, self.selected_name, self.selected_category = self.league.sample_with_metadata(rng)
        self.selected.begin_episode(rng)

    def choose(self, bridge, legal_actions, rng, player):
        if self.selected is None:
            raise RuntimeError("begin_episode doit etre appele avant choose")
        return self.selected.choose(bridge, legal_actions, rng, player)
