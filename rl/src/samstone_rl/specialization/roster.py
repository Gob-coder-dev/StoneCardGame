from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

BOSS_GODS = ("inari", "izanami", "hachiman", "tsukuyomi", "okuninushi", "susanoo")


def file_checksum(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


@dataclass(frozen=True, slots=True)
class BossDeck:
    god_id: str
    stone_ids: tuple[str, ...]
    deck_hash: str
    win_rate: float
    worst_matchup_win_rate: float

    def to_dict(self) -> dict[str, Any]:
        return {**asdict(self), "stone_ids": list(self.stone_ids)}


@dataclass(frozen=True, slots=True)
class BossRoster:
    catalog_checksum: str
    policy_checksum: str
    phase5_checkpoint: str
    decks: tuple[BossDeck, ...]
    source_checksums: dict[str, str]

    @classmethod
    def load(cls, path: str | Path) -> BossRoster:
        source = Path(path).resolve()
        payload = json.loads(source.read_text(encoding="utf-8"))
        if payload.get("schema_version") != 1:
            raise ValueError("version de registre de boss incompatible")
        decks = tuple(BossDeck(
            str(item["god_id"]), tuple(str(value) for value in item["stone_ids"]),
            str(item["deck_hash"]), float(item["win_rate"]),
            float(item["worst_matchup_win_rate"])) for item in payload["decks"])
        roster = cls(str(payload["catalog_checksum"]), str(payload["policy_checksum"]),
                     str(payload["phase5_checkpoint"]), decks,
                     {str(key): str(value) for key, value in payload["source_checksums"].items()})
        roster.validate()
        return roster

    def validate(self) -> None:
        if tuple(item.god_id for item in self.decks) != BOSS_GODS:
            raise ValueError("le registre doit contenir les six dieux dans l'ordre canonique")
        if not self.catalog_checksum or not self.policy_checksum:
            raise ValueError("checksums catalogue/politique absents")
        if len(self.source_checksums) != len(BOSS_GODS):
            raise ValueError("les six rapports de phase 6 sont requis")
        for item in self.decks:
            if len(item.stone_ids) != 8 or not item.deck_hash:
                raise ValueError(f"deck invalide pour {item.god_id}")

    def deck(self, god_id: str) -> BossDeck:
        try:
            return next(item for item in self.decks if item.god_id == god_id)
        except StopIteration as exc:
            raise KeyError(god_id) from exc

    def checksum(self) -> str:
        payload = json.dumps(self.to_dict(), sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    def to_dict(self) -> dict[str, Any]:
        return {"schema_version": 1, "catalog_checksum": self.catalog_checksum,
                "policy_checksum": self.policy_checksum,
                "phase5_checkpoint": self.phase5_checkpoint,
                "decks": [item.to_dict() for item in self.decks],
                "source_checksums": dict(sorted(self.source_checksums.items()))}


def build_boss_roster(reports_directory: str | Path, phase5_checkpoint: str | Path,
                      output_path: str | Path) -> BossRoster:
    reports = Path(reports_directory).resolve()
    checkpoint = Path(phase5_checkpoint).resolve()
    if not checkpoint.is_file():
        raise FileNotFoundError(checkpoint)
    policy_checksum = file_checksum(checkpoint)
    decks: list[BossDeck] = []
    catalog_checksums: set[str] = set()
    source_checksums: dict[str, str] = {}
    for god_id in BOSS_GODS:
        path = reports / f"phase6_gate_{god_id}.json"
        if not path.is_file():
            raise FileNotFoundError(path)
        payload = json.loads(path.read_text(encoding="utf-8"))
        if (payload.get("version") != 1 or payload.get("god_id") != god_id
                or not payload.get("official") or not payload.get("passed")):
            raise ValueError(f"rapport phase 6 non officiel ou refuse: {god_id}")
        if payload.get("policy_checksum") != policy_checksum:
            raise ValueError(f"politique differente dans le rapport {god_id}")
        finalists = payload.get("finalists", [])
        if not finalists:
            raise ValueError(f"aucun deck finaliste pour {god_id}")
        selected = max(finalists, key=lambda item: (
            float(item["fitness"]), float(item["worst_matchup_win_rate"]),
            float(item["win_rate"])))
        decks.append(BossDeck(
            god_id, tuple(str(value) for value in selected["stone_ids"]),
            str(selected["deck_hash"]), float(selected["win_rate"]),
            float(selected["worst_matchup_win_rate"])))
        catalog_checksums.add(str(payload.get("catalog_checksum", "")))
        source_checksums[god_id] = file_checksum(path)
    if len(catalog_checksums) != 1 or "" in catalog_checksums:
        raise ValueError("les rapports n'utilisent pas le meme catalogue")
    roster = BossRoster(catalog_checksums.pop(), policy_checksum, str(checkpoint),
                        tuple(decks), source_checksums)
    roster.validate()
    target = Path(output_path).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".tmp")
    temporary.write_text(json.dumps(roster.to_dict(), indent=2), encoding="utf-8")
    temporary.replace(target)
    return roster
