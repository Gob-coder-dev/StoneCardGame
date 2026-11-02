from __future__ import annotations

import hashlib
import json
from collections.abc import Iterable
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .catalog import DeckCatalog


@dataclass(frozen=True, slots=True)
class DeckCandidate:
    god_id: str
    stone_ids: tuple[str, ...]

    @classmethod
    def build(cls, god_id: str, stone_ids: Iterable[str], catalog: DeckCatalog) -> DeckCandidate:
        return cls(god_id, catalog.canonicalize(tuple(stone_ids)))

    @property
    def deck_hash(self) -> str:
        payload = json.dumps({"god_id": self.god_id, "stone_ids": self.stone_ids},
                             separators=(",", ":"), ensure_ascii=True)
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    def to_dict(self) -> dict:
        return {"god_id": self.god_id, "stone_ids": list(self.stone_ids), "deck_hash": self.deck_hash}
