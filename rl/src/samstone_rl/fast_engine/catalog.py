from __future__ import annotations

import hashlib
import json
from functools import cached_property
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from .anticipation import ReplyThreatCache


class StoneCatalog:
    """Immutable, flattened view of the Godot JSON content catalogue."""

    def __init__(self, game_root: str | Path | None = None) -> None:
        self.game_root = Path(game_root or Path(__file__).resolve().parents[4] / "game")
        stone_data = json.loads((self.game_root / "data" / "stones.json").read_text(
            encoding="utf-8"))
        god_data = json.loads((self.game_root / "data" / "gods.json").read_text(
            encoding="utf-8"))
        self.gods = tuple(str(item["id"]) for item in god_data["gods"])
        self.definitions: dict[str, dict[str, Any]] = {}
        self.lineages: dict[str, tuple[str, ...]] = {}
        for lineage in stone_data["lineages"]:
            lineage_id = str(lineage["id"])
            common = {key: value for key, value in lineage.items() if key != "levels"}
            ids: list[str] = []
            levels = list(lineage["levels"])
            for index, form in enumerate(levels, start=1):
                definition = _deep_merge(common, form)
                stone_id = str(definition["id"])
                definition.update({
                    "lineage_id": lineage_id,
                    "level": index,
                    "max_level": len(levels),
                    "affinity": str(definition.get("god_id", "neutral")),
                })
                self.definitions[stone_id] = definition
                ids.append(stone_id)
            self.lineages[lineage_id] = tuple(ids)

    def definition(self, stone_id: str) -> dict[str, Any]:
        try:
            return self.definitions[stone_id]
        except KeyError as exc:
            raise ValueError(f"pierre inconnue: {stone_id}") from exc

    def has_effect(self, stone_id: str, effect: str) -> bool:
        return effect in self.definition(stone_id).get("effects", ())

    def affinity(self, stone_id: str) -> str:
        return str(self.definition(stone_id)["affinity"])

    def lineage(self, stone_id: str) -> str:
        return str(self.definition(stone_id)["lineage_id"])

    def stones_for_god(self, god: str) -> tuple[str, ...]:
        return tuple(stone_id for stone_id, definition in self.definitions.items()
                     if definition["affinity"] in ("neutral", god))

    @cached_property
    def checksum(self) -> str:
        payload = json.dumps(self.definitions, sort_keys=True, separators=(",", ":"),
                             ensure_ascii=False).encode("utf-8")
        return hashlib.sha256(payload).hexdigest()

    @cached_property
    def reply_threat_cache(self) -> ReplyThreatCache:
        # Local import keeps the catalogue independent from the simulator and
        # creates one cache shared by every environment using this catalogue.
        from .anticipation import ReplyThreatCache
        return ReplyThreatCache(self)


def _deep_merge(common: dict[str, Any], form: dict[str, Any]) -> dict[str, Any]:
    # Godot Dictionary.merge(..., true) replaces complete values at this level.
    result = {key: value for key, value in common.items()}
    result.update(form)
    return result
