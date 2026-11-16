from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from functools import cached_property
from pathlib import Path
from types import MappingProxyType
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from .anticipation import ReplyThreatCache


class StoneCatalog:
    """Immutable, flattened view of the Godot JSON content catalogue."""

    def __init__(self, game_root: str | Path | None = None) -> None:
        self.game_root = Path(game_root or Path(__file__).resolve().parents[4] / "game")
        stone_data = {"lineages": self._load_families()}
        god_data = json.loads(
            (self.game_root / "data" / "gods.json").read_text(encoding="utf-8-sig")
        )
        self.gods = tuple(str(item["id"]) for item in god_data["gods"])
        definitions: dict[str, dict[str, Any]] = {}
        lineages: dict[str, tuple[str, ...]] = {}
        for lineage in stone_data["lineages"]:
            lineage_id = str(lineage["id"])
            if lineage_id in lineages:
                raise ValueError(f"lignee dupliquee: {lineage_id}")
            common = {key: value for key, value in lineage.items() if key != "levels"}
            ids: list[str] = []
            levels = list(lineage["levels"])
            if not levels:
                raise ValueError(f"lignee sans niveaux: {lineage_id}")
            for index, form in enumerate(levels, start=1):
                definition = _deep_merge(common, form)
                stone_id = str(definition["id"])
                if not stone_id or stone_id in definitions:
                    raise ValueError(f"identifiant de pierre absent ou duplique: {stone_id}")
                definition.update(
                    {
                        "lineage_id": lineage_id,
                        "level": index,
                        "max_level": len(levels),
                        "affinity": str(definition.get("god_id", "neutral")),
                    }
                )
                self._validate_stone(definition)
                definitions[stone_id] = definition
                ids.append(stone_id)
            lineages[lineage_id] = tuple(ids)
        self.definitions: Mapping[str, Mapping[str, Any]] = MappingProxyType(
            {key: _freeze(value) for key, value in definitions.items()}
        )
        self.lineages: Mapping[str, tuple[str, ...]] = MappingProxyType(lineages)

    def _validate_stone(self, stone: dict[str, Any]) -> None:
        """Reject unsupported content instead of silently dropping new powers."""
        effects = {"weaken_adjacent", "weaken_on_failed_attack", "swarm", "shield_theft"}
        if (
            set(stone.get("effects", ())) - effects
            or stone["affinity"] not in ("neutral", *self.gods)
            or stone.get("coin_flip", "") not in ("", "horizontal", "vertical")
            or not 1 <= stone["level"] <= stone["max_level"] <= 4
        ):
            raise ValueError(f"contenu incompatible avec le contrat RL: {stone['id']}")
        for side in ("top", "bottom", "left", "right"):
            counts = [
                stone.get(key, {}).get(side, 0) for key in ("blades", "long_blades", "shields")
            ]
            if any(type(value) is not int or value < 0 for value in counts) or sum(counts) > 4:
                raise ValueError(f"symboles invalides: {stone['id']}:{side}")
        random_blades = stone.get("random_blades", 0)
        if type(random_blades) is not int or not 0 <= random_blades <= 16:
            raise ValueError(f"lames aleatoires invalides: {stone['id']}")

    def _load_families(self) -> list[dict[str, Any]]:
        manifest = json.loads(
            (self.game_root / "data/monsters/manifest.json").read_text(encoding="utf-8-sig")
        )
        if manifest.get("catalogue_version") != 1:
            raise ValueError("version du manifeste de pierres incompatible")
        result: list[dict[str, Any]] = []
        seen: set[str] = set()
        for family in manifest["families"]:
            family_id, resource = str(family["id"]), str(family["path"])
            if (
                not family_id
                or family_id in seen
                or not resource.startswith("res://data/monsters/")
            ):
                raise ValueError(f"famille invalide: {family_id}")
            seen.add(family_id)
            path = (self.game_root / resource.removeprefix("res://")).resolve()
            if not path.is_relative_to((self.game_root / "data/monsters").resolve()):
                raise ValueError("chemin de famille hors du catalogue")
            payload = json.loads(path.read_text(encoding="utf-8-sig"))
            if payload.get("family_id") != family_id:
                raise ValueError(f"identite de famille incompatible: {resource}")
            for lineage in payload["lineages"]:
                if lineage.get("god_id", "neutral") != family_id:
                    raise ValueError(f"lignee hors de sa famille: {lineage.get('id')}")
                result.append(lineage)
        return result

    def definition(self, stone_id: str) -> Mapping[str, Any]:
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
        return tuple(
            stone_id
            for stone_id, definition in self.definitions.items()
            if definition["affinity"] in ("neutral", god)
        )

    @cached_property
    def checksum(self) -> str:
        # A line format avoids JSON float/order differences across runtimes.
        # Cosmetic fields deliberately do not invalidate a combat policy.
        rows = ["beastpact-content-v2", ",".join(sorted(self.gods))]
        for stone_id, stone in sorted(self.definitions.items()):
            fields = [
                stone_id,
                stone["lineage_id"],
                str(stone["level"]),
                str(stone["max_level"]),
                stone["affinity"],
            ]
            fields.extend(
                ",".join(
                    str(int(stone.get(key, {}).get(side, 0)))
                    for side in ("top", "bottom", "left", "right")
                )
                for key in ("blades", "long_blades", "shields")
            )
            fields.extend(
                (
                    str(int(stone.get("random_blades", 0))),
                    str(stone.get("coin_flip", "")),
                    ",".join(sorted(stone.get("effects", ()))),
                )
            )
            rows.append("|".join(fields))
        return hashlib.sha256("\n".join(rows).encode("utf-8")).hexdigest()

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


def _freeze(value: Any) -> Any:
    if isinstance(value, dict):
        return MappingProxyType({key: _freeze(item) for key, item in value.items()})
    if isinstance(value, list):
        return tuple(_freeze(item) for item in value)
    return value
