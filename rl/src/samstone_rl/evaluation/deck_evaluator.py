from __future__ import annotations

import hashlib
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import torch

from samstone_rl.bridge.process_pool import GodotProcessPool
from samstone_rl.decks import DeckCandidate
from samstone_rl.envs import SamStoneEnv
from samstone_rl.envs.action_space import ActionCodec
from samstone_rl.envs.observation import ObservationEncoder
from samstone_rl.models.actor_critic import ActorCritic
from samstone_rl.opponents import Opponent

from .fitness import CandidateEvaluation, compute_fitness
from .schedule import MatchSpec
from .store import MatchAction, MatchRecord, MatchStore


@dataclass(frozen=True)
class EvaluationOpponent:
    opponent_id: str
    god_id: str
    deck: tuple[str, ...]
    policy: Opponent | None = None


class DeckEvaluator:
    """Evaluate frozen policy/deck pairs on a common, resumable match schedule."""

    def __init__(self, env: SamStoneEnv, checkpoint_path: str | Path,
                 opponents: tuple[EvaluationOpponent, ...], store: MatchStore,
                 engine_checksum: str, catalog_checksum: str,
                 device: str = "cpu") -> None:
        self.env = env
        self.checkpoint_path = Path(checkpoint_path).resolve()
        self.policy_checksum = self._file_checksum(self.checkpoint_path)
        self.opponents = {item.opponent_id: item for item in opponents}
        self.store = store
        self.engine_checksum = engine_checksum
        self.catalog_checksum = catalog_checksum
        self.device = torch.device(device)
        checkpoint = torch.load(self.checkpoint_path, map_location=self.device, weights_only=False)
        hidden = int(checkpoint.get("config", {}).get("model", {}).get("hidden_dim", 256))
        self.model = ActorCritic(env.observation_space.shape[0], env.action_space.n, hidden).to(self.device)
        self.model.load_state_dict(checkpoint["model"])
        self.model.eval()

    def evaluate(self, candidate: DeckCandidate,
                 schedule: tuple[MatchSpec, ...]) -> CandidateEvaluation:
        for spec in schedule:
            opponent = self.opponents[spec.opponent_id]
            cached = self.store.find(
                self.engine_checksum, self.catalog_checksum, self.policy_checksum,
                candidate.deck_hash, opponent.opponent_id, opponent.deck, spec.seed,
                spec.agent_player, spec.first_player)
            if cached is None:
                self.store.insert(self._play(candidate, opponent, spec))
        records = self.store.records_for(
            self.engine_checksum, self.catalog_checksum, self.policy_checksum, candidate.deck_hash)
        schedule_keys = {(item.opponent_id, item.seed, item.agent_player, item.first_player)
                         for item in schedule}
        selected = tuple(record for record in records
                         if (record.opponent_id, record.seed, record.agent_player,
                             record.first_player) in schedule_keys)
        return compute_fitness(selected)

    def _play(self, candidate: DeckCandidate, opponent: EvaluationOpponent,
              spec: MatchSpec) -> MatchRecord:
        if opponent.policy is None:
            raise ValueError(f"aucune politique sequentielle pour {opponent.opponent_id}")
        self.env.agent_player = spec.agent_player
        self.env.opponent = opponent.policy
        config: dict[str, Any] = {
            "first_player": spec.first_player,
            "human_deck": list(candidate.stone_ids if spec.agent_player == 1 else opponent.deck),
            "human_god": candidate.god_id if spec.agent_player == 1 else opponent.god_id,
            "ai_deck": list(candidate.stone_ids if spec.agent_player == 2 else opponent.deck),
            "ai_god": candidate.god_id if spec.agent_player == 2 else opponent.god_id,
        }
        observation, info = self.env.reset(seed=spec.seed, options={"config": config})
        done = False
        while not done:
            with torch.no_grad():
                action, _, _ = self.model.act(
                    torch.as_tensor(observation, dtype=torch.float32, device=self.device).unsqueeze(0),
                    torch.as_tensor(info["action_mask"], dtype=torch.bool, device=self.device).unsqueeze(0),
                    deterministic=True)
            observation, _reward, terminated, truncated, info = self.env.step(int(action.item()))
            done = terminated or truncated
        candidate_score = int(info["score_human"] if spec.agent_player == 1 else info["score_ai"])
        opponent_score = int(info["score_ai"] if spec.agent_player == 1 else info["score_human"])
        return MatchRecord(
            self.engine_checksum, self.catalog_checksum, self.policy_checksum,
            candidate.deck_hash, candidate.god_id, candidate.stone_ids,
            opponent.opponent_id, opponent.god_id, opponent.deck,
            spec.seed, spec.agent_player, spec.first_player, int(info["winner"]),
            candidate_score, opponent_score)

    @staticmethod
    def _file_checksum(path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        return digest.hexdigest()


class BatchedDeckEvaluator:
    """Evaluate a frozen policy on both sides through batched Godot workers."""

    def __init__(self, pool: GodotProcessPool, checkpoint_path: str | Path,
                 opponents: tuple[EvaluationOpponent, ...], store: MatchStore,
                 engine_checksum: str, catalog_checksum: str, batch_size: int = 64,
                 device: str = "cpu", action_sample_rate: float = 1.0) -> None:
        if batch_size <= 0:
            raise ValueError("batch_size doit etre strictement positif")
        if not 0.0 <= action_sample_rate <= 1.0:
            raise ValueError("action_sample_rate doit etre compris entre 0 et 1")
        self.pool = pool
        self.checkpoint_path = Path(checkpoint_path).resolve()
        self.policy_checksum = DeckEvaluator._file_checksum(self.checkpoint_path)
        self.opponents = {item.opponent_id: item for item in opponents}
        self.store = store
        self.engine_checksum = engine_checksum
        self.catalog_checksum = catalog_checksum
        self.batch_size = batch_size
        self.action_sample_rate = float(action_sample_rate)
        self.device = torch.device(device)
        self.encoder = ObservationEncoder()
        self.codec = ActionCodec()
        self._cache_hits = 0
        self._cache_misses = 0
        self._games_played = 0
        self._actions_sampled = 0
        self._evaluation_seconds = 0.0
        checkpoint = torch.load(self.checkpoint_path, map_location=self.device, weights_only=False)
        hidden = int(checkpoint.get("config", {}).get("model", {}).get("hidden_dim", 256))
        self.model = ActorCritic(self.encoder.get_obs_size(), self.codec.n_actions, hidden).to(self.device)
        self.model.load_state_dict(checkpoint["model"])
        self.model.eval()

    def evaluate(self, candidate: DeckCandidate,
                 schedule: tuple[MatchSpec, ...]) -> CandidateEvaluation:
        started = time.perf_counter()
        missing = []
        for spec in schedule:
            opponent = self.opponents[spec.opponent_id]
            cached = self.store.find(
                self.engine_checksum, self.catalog_checksum, self.policy_checksum,
                candidate.deck_hash, opponent.opponent_id, opponent.deck, spec.seed,
                spec.agent_player, spec.first_player)
            needs_hand_telemetry = (
                cached is not None
                and self._sample_actions(self._match_id(candidate, opponent, spec))
                and not self.store.has_hand_telemetry(cached))
            if cached is None or cached.turns <= 0 or needs_hand_telemetry:
                missing.append(spec)
                self._cache_misses += 1
            else:
                self._cache_hits += 1
        for offset in range(0, len(missing), self.batch_size):
            records, actions = self._play_batch(
                candidate, missing[offset:offset + self.batch_size])
            self.store.insert_many(records, actions)
        self._games_played += len(missing)
        self._evaluation_seconds += time.perf_counter() - started
        records = self.store.records_for(
            self.engine_checksum, self.catalog_checksum, self.policy_checksum, candidate.deck_hash)
        schedule_keys = {(item.opponent_id, item.seed, item.agent_player, item.first_player)
                         for item in schedule}
        selected = tuple(record for record in records
                         if (record.opponent_id, record.seed, record.agent_player,
                             record.first_player) in schedule_keys)
        return compute_fitness(selected)

    def metrics_snapshot(self, reset: bool = False) -> dict[str, float]:
        requests = self._cache_hits + self._cache_misses
        metrics = {
            "cache_hits": float(self._cache_hits),
            "cache_misses": float(self._cache_misses),
            "cache_hit_rate": self._cache_hits / requests if requests else 0.0,
            "games_played": float(self._games_played),
            "action_sampled_matches": float(self._actions_sampled),
            "action_sample_rate_actual": (self._actions_sampled / self._games_played
                                          if self._games_played else 0.0),
            "evaluation_seconds": self._evaluation_seconds,
            "games_per_second": (self._games_played / self._evaluation_seconds
                                 if self._evaluation_seconds > 0 else 0.0),
        }
        if reset:
            self._cache_hits = 0
            self._cache_misses = 0
            self._games_played = 0
            self._actions_sampled = 0
            self._evaluation_seconds = 0.0
        return metrics

    def _play_batch(self, candidate: DeckCandidate,
                    specs: list[MatchSpec]) -> tuple[tuple[MatchRecord, ...], tuple[MatchAction, ...]]:
        contexts: dict[str, tuple[MatchSpec, EvaluationOpponent]] = {}
        blocked: dict[str, tuple[tuple[int, int], ...]] = {}
        traces: dict[str, list[MatchAction]] = {}
        turn_counts: dict[str, int] = {}
        sampled: dict[str, bool] = {}
        capture_totals: dict[str, list[int]] = {}
        resets = []
        for spec in specs:
            opponent = self.opponents[spec.opponent_id]
            match_id = self._match_id(candidate, opponent, spec)
            contexts[match_id] = (spec, opponent)
            traces[match_id] = []
            turn_counts[match_id] = 0
            sampled[match_id] = self._sample_actions(match_id)
            capture_totals[match_id] = [0, 0]
            resets.append({
                "match_id": match_id,
                "observer": spec.first_player,
                "config": self._match_config(candidate, opponent, spec),
            })
        active: dict[str, dict[str, Any]] = {}
        records: list[MatchRecord] = []
        actions: list[MatchAction] = []
        try:
            for item in self.pool.batch_reset(resets):
                if not item["ok"]:
                    raise RuntimeError(f"reset batche refuse: {item}")
                match_id = str(item["match_id"])
                active[match_id] = item["result"]
                blocked[match_id] = tuple(
                    tuple(int(value) for value in cell)
                    for cell in item["result"].get("blocked", []))
            while active:
                steps = self._policy_steps(active)
                steps_by_id = {str(item["match_id"]): item for item in steps}
                finished = []
                for item in self.pool.batch_step(steps):
                    if not item["ok"]:
                        raise RuntimeError(f"action batchee refusee: {item}")
                    match_id = str(item["match_id"])
                    state = item["result"]
                    spec, opponent = contexts[match_id]
                    player = int(state.get("player", 0))
                    captures = len(state.get("captures", []))
                    turn_counts[match_id] += 1
                    side_index = 0 if player == spec.agent_player else 1
                    capture_totals[match_id][side_index] += captures
                    move = steps_by_id[match_id]["action"]
                    if sampled[match_id]:
                        action_record = MatchAction(
                            self.engine_checksum, self.catalog_checksum, self.policy_checksum,
                            candidate.deck_hash, opponent.opponent_id, spec.seed,
                            spec.agent_player, spec.first_player, turn_counts[match_id],
                            player, str(move.get("stone_id", "")), int(move.get("row", -1)),
                            int(move.get("col", -1)), captures,
                            tuple(state.get("effects", [])),
                            tuple(state.get("placement_effects", [])),
                            tuple(str(value) for value in steps_by_id[match_id]["hand_before"]))
                        traces[match_id].append(action_record)
                    if state["observation"]["is_game_over"]:
                        records.append(self._record(
                            candidate, opponent, spec, state["observation"],
                            blocked[match_id], turn_counts[match_id],
                            capture_totals[match_id][0], capture_totals[match_id][1],
                            sampled[match_id]))
                        self._actions_sampled += int(sampled[match_id])
                        actions.extend(traces[match_id])
                        finished.append(match_id)
                    else:
                        active[match_id] = state
                for match_id in finished:
                    del active[match_id]
            return tuple(records), tuple(actions)
        finally:
            self.pool.release_matches(list(contexts))

    def _policy_steps(self, active: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
        match_ids = list(active)
        observations = []
        masks = []
        for match_id in match_ids:
            state = active[match_id]
            raw = state["observation"]
            observations.append(self.encoder.encode(raw))
            masks.append(self.codec.legal_mask(state["legal_actions"], raw["hand"]))
        with torch.no_grad():
            actions, _log_prob, _value = self.model.act(
                torch.as_tensor(np.stack(observations), dtype=torch.float32, device=self.device),
                torch.as_tensor(np.stack(masks), dtype=torch.bool, device=self.device),
                deterministic=True)
        steps = []
        for match_id, action in zip(match_ids, actions.cpu().tolist(), strict=True):
            state = active[match_id]
            raw = state["observation"]
            current_player = int(raw["current_player"])
            steps.append({
                "match_id": match_id,
                "observer": 3 - current_player,
                "action": self.codec.action_to_move(int(action), raw["hand"]),
                "hand_before": list(raw["hand"]),
            })
        return steps

    @staticmethod
    def _match_config(candidate: DeckCandidate, opponent: EvaluationOpponent,
                      spec: MatchSpec) -> dict[str, Any]:
        return {
            "seed": spec.seed,
            "first_player": spec.first_player,
            "human_deck": list(candidate.stone_ids if spec.agent_player == 1 else opponent.deck),
            "human_god": candidate.god_id if spec.agent_player == 1 else opponent.god_id,
            "ai_deck": list(candidate.stone_ids if spec.agent_player == 2 else opponent.deck),
            "ai_god": candidate.god_id if spec.agent_player == 2 else opponent.god_id,
        }

    def _record(self, candidate: DeckCandidate, opponent: EvaluationOpponent,
                spec: MatchSpec, observation: dict[str, Any],
                blocked: tuple[tuple[int, int], ...] = (), turns: int = 0,
                candidate_captures: int = 0, opponent_captures: int = 0,
                actions_sampled: bool = False) -> MatchRecord:
        candidate_score = int(observation["score_human"] if spec.agent_player == 1
                              else observation["score_ai"])
        opponent_score = int(observation["score_ai"] if spec.agent_player == 1
                             else observation["score_human"])
        return MatchRecord(
            self.engine_checksum, self.catalog_checksum, self.policy_checksum,
            candidate.deck_hash, candidate.god_id, candidate.stone_ids,
            opponent.opponent_id, opponent.god_id, opponent.deck,
            spec.seed, spec.agent_player, spec.first_player, int(observation["winner"]),
            candidate_score, opponent_score, blocked, turns,
            candidate_captures, opponent_captures, actions_sampled)

    def _sample_actions(self, match_id: str) -> bool:
        if self.action_sample_rate >= 1.0:
            return True
        if self.action_sample_rate <= 0.0:
            return False
        digest = hashlib.sha256(match_id.encode("utf-8")).digest()
        value = int.from_bytes(digest[:8], "big") / float(2**64)
        return value < self.action_sample_rate

    @staticmethod
    def _match_id(candidate: DeckCandidate, opponent: EvaluationOpponent,
                  spec: MatchSpec) -> str:
        return (f"{candidate.deck_hash[:12]}-{opponent.opponent_id}-{spec.seed}-"
                f"{spec.agent_player}-{spec.first_player}")
