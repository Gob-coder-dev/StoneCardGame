from __future__ import annotations

import json
import sqlite3
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Self


@dataclass(frozen=True, slots=True)
class MatchRecord:
    engine_checksum: str
    catalog_checksum: str
    policy_checksum: str
    candidate_hash: str
    candidate_god: str
    candidate_deck: tuple[str, ...]
    opponent_id: str
    opponent_god: str
    opponent_deck: tuple[str, ...]
    seed: int
    agent_player: int
    first_player: int
    winner: int
    score_candidate: int
    score_opponent: int
    blocked: tuple[tuple[int, int], ...] = ()
    turns: int = 0
    candidate_captures: int = 0
    opponent_captures: int = 0
    actions_sampled: bool = False

    @property
    def won(self) -> bool:
        return self.winner == self.agent_player

    @property
    def draw(self) -> bool:
        return self.winner == 0


@dataclass(frozen=True, slots=True)
class MatchAction:
    engine_checksum: str
    catalog_checksum: str
    policy_checksum: str
    candidate_hash: str
    opponent_id: str
    seed: int
    agent_player: int
    first_player: int
    turn: int
    player: int
    stone_id: str
    row: int
    col: int
    captures: int
    effects: tuple[Any, ...] = ()
    placement_effects: tuple[Any, ...] = ()
    hand: tuple[str, ...] = ()


class MatchStore:
    def __init__(self, path: str | Path) -> None:
        self.path = Path(path).resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(self.path)
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute("PRAGMA synchronous=FULL")
        self._create_schema()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def close(self) -> None:
        self.connection.close()

    def find(self, engine_checksum: str, catalog_checksum: str, policy_checksum: str,
             candidate_hash: str, opponent_id: str, opponent_deck: tuple[str, ...], seed: int,
             agent_player: int, first_player: int) -> MatchRecord | None:
        row = self.connection.execute(
            """SELECT * FROM matches WHERE engine_checksum=? AND catalog_checksum=?
               AND policy_checksum=? AND candidate_hash=? AND opponent_id=?
               AND seed=? AND agent_player=? AND first_player=?""",
            (engine_checksum, catalog_checksum, policy_checksum, candidate_hash,
             opponent_id, seed, agent_player, first_player)).fetchone()
        if row is None or tuple(json.loads(row["opponent_deck"])) != opponent_deck:
            return None
        return self._from_row(row)

    def insert(self, record: MatchRecord) -> None:
        self._insert_record(record)
        self.connection.commit()

    def insert_many(self, records: Iterable[MatchRecord],
                    actions: Iterable[MatchAction] = ()) -> None:
        with self.connection:
            for record in records:
                self._insert_record(record)
            for action in actions:
                self._insert_action(action)

    def records_for(self, engine_checksum: str, catalog_checksum: str,
                    policy_checksum: str, candidate_hash: str) -> tuple[MatchRecord, ...]:
        rows = self.connection.execute(
            """SELECT * FROM matches WHERE engine_checksum=? AND catalog_checksum=?
               AND policy_checksum=? AND candidate_hash=? ORDER BY opponent_id, seed,
               agent_player, first_player""",
            (engine_checksum, catalog_checksum, policy_checksum, candidate_hash)).fetchall()
        return tuple(self._from_row(row) for row in rows)

    def all_records(self) -> tuple[MatchRecord, ...]:
        rows = self.connection.execute(
            """SELECT * FROM matches ORDER BY policy_checksum, candidate_god,
               candidate_hash, opponent_id, seed, agent_player, first_player""").fetchall()
        return tuple(self._from_row(row) for row in rows)

    def actions_for(self, record: MatchRecord) -> tuple[MatchAction, ...]:
        rows = self.connection.execute(
            """SELECT * FROM match_actions WHERE engine_checksum=? AND catalog_checksum=?
               AND policy_checksum=? AND candidate_hash=? AND opponent_id=? AND seed=?
               AND agent_player=? AND first_player=? ORDER BY turn""",
            (record.engine_checksum, record.catalog_checksum, record.policy_checksum,
             record.candidate_hash, record.opponent_id, record.seed,
             record.agent_player, record.first_player)).fetchall()
        return tuple(self._action_from_row(row) for row in rows)

    def has_hand_telemetry(self, record: MatchRecord) -> bool:
        """Return whether a cached sampled match contains v3 hand telemetry."""
        row = self.connection.execute(
            """SELECT 1 FROM match_actions WHERE engine_checksum=? AND catalog_checksum=?
               AND policy_checksum=? AND candidate_hash=? AND opponent_id=? AND seed=?
               AND agent_player=? AND first_player=? AND hand != '[]' LIMIT 1""",
            (record.engine_checksum, record.catalog_checksum, record.policy_checksum,
             record.candidate_hash, record.opponent_id, record.seed,
             record.agent_player, record.first_player)).fetchone()
        return row is not None

    def all_actions(self) -> tuple[MatchAction, ...]:
        rows = self.connection.execute(
            """SELECT * FROM match_actions ORDER BY policy_checksum, candidate_hash,
               opponent_id, seed, agent_player, first_player, turn""").fetchall()
        return tuple(self._action_from_row(row) for row in rows)

    def _create_schema(self) -> None:
        self.connection.execute(
            """CREATE TABLE IF NOT EXISTS metadata (
               key TEXT PRIMARY KEY, value TEXT NOT NULL)""")
        self.connection.execute(
            "INSERT OR REPLACE INTO metadata (key, value) VALUES ('schema_version', '3')")
        self.connection.execute(
            """CREATE TABLE IF NOT EXISTS matches (
               engine_checksum TEXT NOT NULL,
               catalog_checksum TEXT NOT NULL,
               policy_checksum TEXT NOT NULL,
               candidate_hash TEXT NOT NULL,
               candidate_god TEXT NOT NULL,
               candidate_deck TEXT NOT NULL,
               opponent_id TEXT NOT NULL,
               opponent_god TEXT NOT NULL,
               opponent_deck TEXT NOT NULL,
               seed INTEGER NOT NULL,
               agent_player INTEGER NOT NULL,
               first_player INTEGER NOT NULL,
               winner INTEGER NOT NULL,
               score_candidate INTEGER NOT NULL,
               score_opponent INTEGER NOT NULL,
               blocked TEXT NOT NULL DEFAULT '[]',
               turns INTEGER NOT NULL DEFAULT 0,
               candidate_captures INTEGER NOT NULL DEFAULT 0,
               opponent_captures INTEGER NOT NULL DEFAULT 0,
               actions_sampled INTEGER NOT NULL DEFAULT 0,
               PRIMARY KEY (engine_checksum, catalog_checksum, policy_checksum,
                            candidate_hash, opponent_id, seed, agent_player, first_player))""")
        columns = {str(row[1]) for row in self.connection.execute("PRAGMA table_info(matches)")}
        migrations = {
            "blocked": "TEXT NOT NULL DEFAULT '[]'",
            "turns": "INTEGER NOT NULL DEFAULT 0",
            "candidate_captures": "INTEGER NOT NULL DEFAULT 0",
            "opponent_captures": "INTEGER NOT NULL DEFAULT 0",
            "actions_sampled": "INTEGER NOT NULL DEFAULT 0",
        }
        for name, declaration in migrations.items():
            if name not in columns:
                self.connection.execute(f"ALTER TABLE matches ADD COLUMN {name} {declaration}")
        self.connection.execute(
            """CREATE TABLE IF NOT EXISTS match_actions (
               engine_checksum TEXT NOT NULL,
               catalog_checksum TEXT NOT NULL,
               policy_checksum TEXT NOT NULL,
               candidate_hash TEXT NOT NULL,
               opponent_id TEXT NOT NULL,
               seed INTEGER NOT NULL,
               agent_player INTEGER NOT NULL,
               first_player INTEGER NOT NULL,
               turn INTEGER NOT NULL,
               player INTEGER NOT NULL,
               stone_id TEXT NOT NULL,
               row INTEGER NOT NULL,
               col INTEGER NOT NULL,
               captures INTEGER NOT NULL,
               effects TEXT NOT NULL,
               placement_effects TEXT NOT NULL,
               hand TEXT NOT NULL DEFAULT '[]',
               PRIMARY KEY (engine_checksum, catalog_checksum, policy_checksum,
                            candidate_hash, opponent_id, seed, agent_player,
                            first_player, turn))""")
        action_columns = {
            str(row[1]) for row in self.connection.execute("PRAGMA table_info(match_actions)")}
        if "hand" not in action_columns:
            self.connection.execute(
                "ALTER TABLE match_actions ADD COLUMN hand TEXT NOT NULL DEFAULT '[]'")
        self.connection.commit()

    def _insert_record(self, record: MatchRecord) -> None:
        self.connection.execute(
            """DELETE FROM match_actions WHERE engine_checksum=? AND catalog_checksum=?
               AND policy_checksum=? AND candidate_hash=? AND opponent_id=? AND seed=?
               AND agent_player=? AND first_player=?""",
            (record.engine_checksum, record.catalog_checksum, record.policy_checksum,
             record.candidate_hash, record.opponent_id, record.seed,
             record.agent_player, record.first_player))
        self.connection.execute(
            """INSERT OR REPLACE INTO matches (
               engine_checksum, catalog_checksum, policy_checksum, candidate_hash,
               candidate_god, candidate_deck, opponent_id, opponent_god, opponent_deck,
               seed, agent_player, first_player, winner, score_candidate, score_opponent,
               blocked, turns, candidate_captures, opponent_captures, actions_sampled)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (record.engine_checksum, record.catalog_checksum, record.policy_checksum,
             record.candidate_hash, record.candidate_god, json.dumps(record.candidate_deck),
             record.opponent_id, record.opponent_god, json.dumps(record.opponent_deck),
             record.seed, record.agent_player, record.first_player, record.winner,
             record.score_candidate, record.score_opponent, json.dumps(record.blocked),
             record.turns, record.candidate_captures, record.opponent_captures,
             int(record.actions_sampled)))

    def _insert_action(self, action: MatchAction) -> None:
        self.connection.execute(
            """INSERT OR REPLACE INTO match_actions (
               engine_checksum, catalog_checksum, policy_checksum, candidate_hash,
               opponent_id, seed, agent_player, first_player, turn, player,
               stone_id, row, col, captures, effects, placement_effects, hand)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (action.engine_checksum, action.catalog_checksum, action.policy_checksum,
             action.candidate_hash, action.opponent_id, action.seed,
             action.agent_player, action.first_player, action.turn, action.player,
             action.stone_id, action.row, action.col, action.captures,
             json.dumps(action.effects), json.dumps(action.placement_effects),
             json.dumps(action.hand)))

    @staticmethod
    def _from_row(row: sqlite3.Row) -> MatchRecord:
        return MatchRecord(
            row["engine_checksum"], row["catalog_checksum"], row["policy_checksum"],
            row["candidate_hash"], row["candidate_god"], tuple(json.loads(row["candidate_deck"])),
            row["opponent_id"], row["opponent_god"], tuple(json.loads(row["opponent_deck"])),
            int(row["seed"]), int(row["agent_player"]), int(row["first_player"]),
            int(row["winner"]), int(row["score_candidate"]), int(row["score_opponent"]),
            tuple(tuple(int(value) for value in cell) for cell in json.loads(row["blocked"])),
            int(row["turns"]), int(row["candidate_captures"]),
            int(row["opponent_captures"]), bool(row["actions_sampled"]))

    @staticmethod
    def _action_from_row(row: sqlite3.Row) -> MatchAction:
        return MatchAction(
            row["engine_checksum"], row["catalog_checksum"], row["policy_checksum"],
            row["candidate_hash"], row["opponent_id"], int(row["seed"]),
            int(row["agent_player"]), int(row["first_player"]), int(row["turn"]),
            int(row["player"]), row["stone_id"], int(row["row"]), int(row["col"]),
            int(row["captures"]), tuple(json.loads(row["effects"])),
            tuple(json.loads(row["placement_effects"])), tuple(json.loads(row["hand"])))
