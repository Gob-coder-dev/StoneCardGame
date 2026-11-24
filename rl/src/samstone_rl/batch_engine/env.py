from __future__ import annotations

import math
from collections.abc import Sequence
from copy import deepcopy
from dataclasses import dataclass, field
from functools import partial
from pathlib import Path
from typing import Any

import numpy as np

from samstone_rl.envs.action_space import ActionCodec
from samstone_rl.fast_engine import FastSimulator, StoneCatalog
from samstone_rl.fast_engine.core import _weighted_index
from samstone_rl.opponents import GodotProfileOpponent, Opponent, RandomOpponent
from samstone_rl.opponents.checkpoint import CheckpointOpponent
from samstone_rl.tactics import TacticalActionEncoder
from samstone_rl.vector_engine import VectorTacticalEvaluator

from .catalog import NumericStoneCatalog
from .encoding import DirectStateEncoder


class _SimulatorBridge:
    """Expose simulator observations, tactical scores and native action masks."""

    def __init__(self, simulator: FastSimulator, encoder: DirectStateEncoder) -> None:
        self.simulator = simulator
        self.encoder = encoder

    def choose_profile_action(self, precision: float, anticipation: bool) -> dict[str, Any]:
        return self.simulator.choose_profile_action(precision, anticipation)

    def legal_actions(self) -> list[dict[str, Any]]:
        return self.simulator.legal_actions()

    def action_mask(self, observer: int) -> np.ndarray:
        state = self.simulator.state
        assert state is not None
        mask = self.encoder.action_mask(state, observer)
        # ActionCodec resolves a card ID to its first hand slot. Preserve that
        # convention for decks containing repeated IDs.
        seen = set()
        for index, card in enumerate(state.hands[observer]):
            if card in seen:
                mask[index * 16 : (index + 1) * 16] = False
            seen.add(card)
        return mask

    def get_state(self, observer: int) -> dict[str, Any]:
        """Expose the opponent's own hidden hand, never the agent's hand."""
        return {"observation": self.simulator.serialize_for_player(observer)}

    def tactical_action_scores(self, observer: int) -> dict[int, tuple[float, ...]]:
        return self.simulator.tactical_action_scores(observer)


@dataclass(slots=True)
class _Slot:
    simulator: FastSimulator
    bridge: _SimulatorBridge
    opponent: Opponent = field(default_factory=RandomOpponent)
    agent_player: int = 1
    rng: np.random.Generator = field(default_factory=np.random.default_rng)
    episode_seed: int = 0
    episode_return: float = 0.0
    agent_decisions: int = 0
    turns: int = 0
    agent_captures: int = 0
    opponent_captures: int = 0
    blocked: list[list[int]] = field(default_factory=list)
    first_player: int = 0
    config: dict[str, Any] = field(default_factory=dict)


class BatchSamStoneEnv:
    """Manage many scalar rule states through one allocation-stable batch API.

    The rules are intentionally delegated to ``FastSimulator``.  That engine
    is already checked against Godot, so this backend optimizes data movement
    while preserving a single authoritative Python rules implementation.
    """

    backend_name = "python_batch"

    def __init__(
        self,
        num_envs: int,
        reward_scheme: Any,
        game_root: str | Path | None = None,
        tactical_features: bool = False,
        vector_tactical: bool = True,
        vector_effects: bool = True,
        tactical_workers: int = 1,
        profile_backend: str = "python",
        profile_workers: int = 10,
        godot_path: str | None = None,
        python_profile_workers: int = 1,
    ) -> None:
        if num_envs <= 0:
            raise ValueError("num_envs doit etre strictement positif")
        if not 1 <= tactical_workers <= num_envs:
            raise ValueError("tactical_workers doit etre entre 1 et num_envs")
        self.num_envs = int(num_envs)
        if profile_backend not in ("godot", "python", "python_approximate"):
            raise ValueError("profile_backend inconnu")
        self.profile_backend = profile_backend
        self.profile_oracle = None
        if profile_backend == "godot":
            from samstone_rl.bridge.profile_oracle import ProfileOracle

            self.profile_oracle = ProfileOracle(profile_workers, godot_path, game_root)
        self.reward_scheme = reward_scheme
        self.catalog = StoneCatalog(game_root)
        self.python_profile_pool = None
        if python_profile_workers <= 0:
            raise ValueError("python_profile_workers doit etre positif")
        if profile_backend == "python" and python_profile_workers > 1:
            from samstone_rl.fast_engine.profile_pool import PythonProfilePool

            self.python_profile_pool = PythonProfilePool(self.catalog, python_profile_workers)
        self.numeric_catalog = NumericStoneCatalog.from_catalog(self.catalog)
        self.encoder = DirectStateEncoder(self.numeric_catalog)
        self.tactical_features_enabled = bool(tactical_features)
        self.tactical_encoder = TacticalActionEncoder()
        self.vector_tactical_enabled = bool(vector_tactical and tactical_features)
        self.vector_tactical = (
            VectorTacticalEvaluator(self.numeric_catalog, vector_effects=vector_effects)
            if self.vector_tactical_enabled and tactical_workers == 1
            else None
        )
        if self.vector_tactical_enabled and tactical_workers > 1:
            from samstone_rl.vector_engine.parallel import ParallelTacticalEvaluator

            self.vector_tactical = ParallelTacticalEvaluator(
                self.numeric_catalog, workers=tactical_workers, vector_effects=vector_effects
            )
        self.codec = ActionCodec()
        self.slots: list[_Slot] = []
        for _ in range(self.num_envs):
            simulator = FastSimulator(self.catalog)
            self.slots.append(_Slot(simulator, _SimulatorBridge(simulator, self.encoder)))
        self.observations = np.zeros(
            (self.num_envs, self.encoder.observation_size), dtype=np.float32
        )
        self.action_masks = np.zeros((self.num_envs, self.codec.n_actions), dtype=np.bool_)
        self.action_features = np.zeros(
            (self.num_envs, self.codec.n_actions, self.tactical_encoder.feature_size),
            dtype=np.float32,
        )
        self.closed = False

    def reset_one(
        self,
        index: int,
        *,
        seed: int,
        opponent: Opponent,
        agent_player: int,
        options: dict[str, Any] | None = None,
    ) -> tuple[np.ndarray, dict[str, Any]]:
        self._reset_slot(
            index, seed=seed, opponent=opponent, agent_player=agent_player, options=options
        )
        self._encode_many([index])
        return self.observations[index], self._info(index)

    def _reset_slot(
        self,
        index: int,
        *,
        seed: int,
        opponent: Opponent,
        agent_player: int,
        options: dict[str, Any] | None = None,
        play_opponent: bool = True,
    ) -> None:
        slot = self._slot(index)
        if agent_player not in (1, 2):
            raise ValueError("agent_player doit valoir 1 ou 2")
        config = deepcopy((options or {}).get("config", {}))
        if not config:
            raise ValueError("une configuration de match complete est obligatoire")
        config["seed"] = int(seed)
        slot.opponent = opponent
        slot.agent_player = int(agent_player)
        slot.rng = np.random.default_rng(int(seed))
        slot.episode_seed = int(seed)
        slot.episode_return = 0.0
        slot.agent_decisions = 0
        slot.turns = 0
        slot.agent_captures = 0
        slot.opponent_captures = 0
        slot.config = deepcopy(config)
        slot.opponent.begin_episode(slot.rng)
        reset_result = slot.simulator.reset(config)
        slot.blocked = deepcopy(reset_result.get("blocked", []))
        slot.first_player = int(reset_result["first_player"])
        if play_opponent:
            slot.opponent_captures += self._play_opponent_turns(slot)

    def reset_many(
        self,
        indices: Sequence[int],
        *,
        seeds: Sequence[int],
        opponents: Sequence[Opponent],
        agent_players: Sequence[int],
        options: Sequence[dict[str, Any] | None],
    ) -> tuple[list[np.ndarray], list[dict[str, Any]]]:
        lengths = {len(indices), len(seeds), len(opponents), len(agent_players), len(options)}
        if len(lengths) != 1:
            raise ValueError("les lots de reset doivent avoir la meme taille")
        for index, seed, opponent, player, item_options in zip(
            indices, seeds, opponents, agent_players, options, strict=True
        ):
            self._reset_slot(
                index,
                seed=int(seed),
                opponent=opponent,
                agent_player=int(player),
                options=item_options,
                play_opponent=False,
            )
        captures = self._play_opponents_batch(indices)
        for index in indices:
            self.slots[index].opponent_captures += captures.get(int(index), 0)
        self._encode_many(indices)
        return (
            [self.observations[index] for index in indices],
            [self._info(index) for index in indices],
        )

    def step(
        self, actions: Sequence[int], *, encode_terminal: bool = True
    ) -> list[tuple[np.ndarray | None, float, bool, bool, dict[str, Any]]]:
        """Optionally omit terminal observations when PPO immediately resets them."""
        if len(actions) != self.num_envs:
            raise ValueError(f"{self.num_envs} actions attendues, {len(actions)} recues")
        pending = [
            self._play_agent_action(index, int(action)) for index, action in enumerate(actions)
        ]
        opponent_captures = self._play_opponents_batch(range(self.num_envs))
        advanced = [
            self._finish_transition(
                index, pending[index][0], pending[index][1], opponent_captures.get(index, 0)
            )
            for index in range(self.num_envs)
        ]
        self._encode_many(
            [index for index, values in enumerate(advanced) if encode_terminal or not values[1]]
        )
        return [
            (
                self.observations[index] if encode_terminal or not values[1] else None,
                float(values[0]),
                values[1],
                False,
                self._info(index, *values[2], include_observation=encode_terminal or not values[1]),
            )
            for index, values in enumerate(advanced)
        ]

    def step_one(
        self, index: int, action: int
    ) -> tuple[np.ndarray, float, bool, bool, dict[str, Any]]:
        reward, terminated, details = self._advance_one(index, action)
        self._encode_many([index])
        return (
            self.observations[index],
            float(reward),
            terminated,
            False,
            self._info(index, *details),
        )

    def _advance_one(
        self, index: int, action: int
    ) -> tuple[float, bool, tuple[int, int, float, float, float, float]]:
        previous_margin, agent_captures = self._play_agent_action(index, action)
        opponent_captures = self._play_opponent_turns(self._slot(index))
        return self._finish_transition(index, previous_margin, agent_captures, opponent_captures)

    def _play_agent_action(self, index: int, action: int) -> tuple[int, int]:
        slot = self._slot(index)
        state = slot.simulator.state
        if state is None:
            raise RuntimeError("environnement non initialise")
        if action < 0 or action >= self.codec.n_actions or not self.action_masks[index, action]:
            raise ValueError(f"action illegale: {action}")
        previous_margin = self._score_margin(slot)
        hand_slot, cell = divmod(action, 16)
        hand = state.hands[slot.agent_player]
        move = {"row": cell // 4, "col": cell % 4, "stone_id": hand[hand_slot]}
        result = slot.simulator.step(move)
        agent_captures = len(result.get("captures", ()))
        slot.agent_decisions += 1
        slot.turns += 1
        slot.agent_captures += agent_captures
        return previous_margin, agent_captures

    def _finish_transition(
        self, index: int, previous_margin: int, agent_captures: int, opponent_captures: int
    ) -> tuple[float, bool, tuple[int, int, float, float, float, float]]:
        slot = self._slot(index)
        slot.opponent_captures += opponent_captures
        state = slot.simulator.state
        assert state is not None
        terminated = bool(state.is_game_over)
        capture_reward = self.reward_scheme.captures(agent_captures) - self.reward_scheme.captures(
            opponent_captures
        )
        terminal_reward = self._terminal_reward(slot) if terminated else 0.0
        final_margin_reward = self._final_margin_reward(slot) if terminated else 0.0
        control_delta_reward = self.reward_scheme.control_delta(
            previous_margin, self._score_margin(slot), state.gods[slot.agent_player]
        )
        reward = capture_reward + terminal_reward + final_margin_reward + control_delta_reward
        slot.episode_return += reward
        details = (
            agent_captures,
            opponent_captures,
            capture_reward,
            terminal_reward,
            final_margin_reward,
            control_delta_reward,
        )
        return float(reward), terminated, details

    def _play_opponents_batch(self, indices: Sequence[int]) -> dict[int, int]:
        """Play checkpoint opponents in batches and compute teacher scores separately.

        The Python backend uses native exact scores, optionally in persistent
        CPU workers. The Godot backend is retained for conformity diagnostics;
        the legacy envelope is explicitly named python_approximate.
        """
        captures = {int(index): 0 for index in indices}
        profile_requests: list[tuple[int, bool, GodotProfileOpponent]] = []
        checkpoint_groups: dict[CheckpointOpponent, list[int]] = {}
        for raw_index in indices:
            index = int(raw_index)
            slot = self._slot(index)
            state = slot.simulator.state
            assert state is not None
            if state.is_game_over or state.current_player == slot.agent_player:
                continue
            opponent = getattr(slot.opponent, "selected", None) or slot.opponent
            if isinstance(opponent, CheckpointOpponent):
                checkpoint_groups.setdefault(opponent, []).append(index)
                continue
            if isinstance(opponent, GodotProfileOpponent):
                if (
                    self.vector_tactical is None and self.profile_oracle is None
                ) or opponent.precision <= 0.0:
                    moves = slot.simulator.legal_actions()
                    move = opponent.choose(slot.bridge, moves, slot.rng, state.current_player)
                    result = slot.simulator.step(move)
                    captures[index] += len(result.get("captures", ()))
                    slot.turns += 1
                    continue
                probability = opponent.anticipation_probability
                if probability is None:
                    anticipation = opponent.anticipation
                elif probability <= 0.0:
                    anticipation = False
                elif probability >= 1.0:
                    anticipation = True
                else:
                    anticipation = bool(slot.rng.random() < probability)
                profile_requests.append((index, anticipation, opponent))
                continue
            moves = slot.simulator.legal_actions()
            move = opponent.choose(slot.bridge, moves, slot.rng, state.current_player)
            result = slot.simulator.step(move)
            captures[index] += len(result.get("captures", ()))
            slot.turns += 1
        # League entries share cached opponent instances. Group by instance so
        # different checkpoints and sampling settings keep separate forwards.
        for opponent, group in checkpoint_groups.items():
            requests = []
            for index in group:
                slot = self.slots[index]
                requests.append(
                    (
                        slot.bridge,
                        None,
                        slot.rng,
                        slot.simulator.state.current_player,
                    )
                )
            evaluate_tactics = None
            if self.vector_tactical is not None:
                evaluate_tactics = partial(
                    self.vector_tactical.evaluate,
                    [self.slots[index].simulator for index in group],
                    [player for _, _, _, player in requests],
                )
            moves = opponent.choose_many(requests, evaluate_tactics=evaluate_tactics)
            for index, move in zip(group, moves, strict=True):
                slot = self.slots[index]
                result = slot.simulator.step(move)
                captures[index] += len(result.get("captures", ()))
                slot.turns += 1
        if not profile_requests:
            return captures
        request_indices = [item[0] for item in profile_requests]
        simulators = [self.slots[index].simulator for index in request_indices]
        observers = [
            int(simulator.state.current_player)  # type: ignore[union-attr]
            for simulator in simulators
        ]
        masks = np.zeros((len(simulators), self.codec.n_actions), dtype=np.bool_)
        for row, (simulator, observer) in enumerate(zip(simulators, observers, strict=True)):
            state = simulator.state
            assert state is not None
            self.encoder.action_mask(state, observer, masks[row])
        if self.profile_oracle is not None:
            teacher_scores = self.profile_oracle.scores(
                [
                    {
                        "snapshot": simulator.serialize_for_player(observer),
                        "anticipation": request[1],
                    }
                    for simulator, observer, request in zip(
                        simulators, observers, profile_requests, strict=True
                    )
                ]
            )
        else:
            if self.profile_backend == "python":
                teacher_scores = (
                    self.python_profile_pool.scores(simulators, [r[1] for r in profile_requests])
                    if self.python_profile_pool is not None
                    else [
                        simulator.profile_action_scores(request[1])
                        for simulator, request in zip(simulators, profile_requests, strict=True)
                    ]
                )
            else:
                assert self.vector_tactical is not None
                score_batches = self.vector_tactical.evaluate(simulators, observers, masks)
        for row, ((index, anticipation, opponent), observer) in enumerate(
            zip(profile_requests, observers, strict=True)
        ):
            slot = self.slots[index]
            assert isinstance(opponent, GodotProfileOpponent)
            simulator = slot.simulator
            moves = simulator.legal_actions()
            if not moves:
                raise RuntimeError("l'adversaire n'a aucun coup legal")
            rng = simulator.opponent_rng
            precision = opponent.precision
            if precision <= 0.0:
                move = moves[rng.randrange(len(moves))]
            else:
                plays_best = rng.random() < precision
                hand = simulator.state.hands[observer]  # type: ignore[union-attr]
                values: list[float] = []
                for candidate in moves:
                    cell = int(candidate["row"]) * 4 + int(candidate["col"])
                    action = hand.index(str(candidate["stone_id"])) * 16 + cell
                    values.append(
                        teacher_scores[row][action]
                        if self.profile_backend != "python_approximate"
                        else float(score_batches[row, action, 1 if anticipation else 0])
                    )
                best = max(values)
                temperature = (1.0 - precision) / precision
                weights = [1.0 if best - value <= 1e-6 else 0.0 for value in values]
                if not plays_best:
                    weights = [
                        math.exp(-(best - value) / temperature) if temperature > 0 else 0.0
                        for value in values
                    ]
                move = moves[_weighted_index(weights, rng)]
            result = simulator.step(move)
            captures[index] += len(result.get("captures", ()))
            slot.turns += 1
        return captures

    def engine_manifest(self) -> dict[str, Any]:
        return {
            "protocol_version": 2,
            "observation_schema": 1,
            "action_feature_schema": (
                self.tactical_encoder.SCHEMA_VERSION if self.tactical_features_enabled else 0
            ),
            "action_feature_size": (
                self.tactical_encoder.feature_size if self.tactical_features_enabled else 0
            ),
            "catalogue_checksum": self.catalog.checksum,
            "game_version": "fast-python-batch-1",
            "godot_version": "in-process",
            "backend": self.backend_name,
            "batch_size": self.num_envs,
            "profile_backend": self.profile_backend,
            "vector_tactical": self.vector_tactical_enabled,
            "vector_effects": bool(self.vector_tactical and self.vector_tactical.vector_effects),
        }

    def vector_metrics(self, *, reset: bool = False) -> dict[str, float]:
        if self.vector_tactical is None:
            return {"enabled": 0.0, "coverage": 0.0}
        return {"enabled": 1.0, **self.vector_tactical.metrics(reset=reset)}

    def close(self) -> None:
        if self.python_profile_pool is not None:
            self.python_profile_pool.close()
            self.python_profile_pool = None
        if self.profile_oracle is not None:
            self.profile_oracle.close()
            self.profile_oracle = None
        if self.vector_tactical is not None:
            self.vector_tactical.close()
        self.closed = True

    def _slot(self, index: int) -> _Slot:
        if self.closed:
            raise RuntimeError("environnement batch ferme")
        if index < 0 or index >= self.num_envs:
            raise IndexError(index)
        return self.slots[index]

    def _play_opponent_turns(self, slot: _Slot) -> int:
        captures = 0
        state = slot.simulator.state
        assert state is not None
        while not state.is_game_over and state.current_player != slot.agent_player:
            moves = slot.simulator.legal_actions()
            move = slot.opponent.choose(slot.bridge, moves, slot.rng, state.current_player)
            result = slot.simulator.step(move)
            captures += len(result.get("captures", ()))
            slot.turns += 1
            state = slot.simulator.state
            assert state is not None
        return captures

    def _encode_many(self, indices: Sequence[int]) -> None:
        if not indices:
            return
        selected = [int(index) for index in indices]
        for index in selected:
            slot = self.slots[index]
            state = slot.simulator.state
            assert state is not None
            self.encoder.encode(state, slot.agent_player, self.observations[index])
            self.encoder.action_mask(state, slot.agent_player, self.action_masks[index])
        if not self.tactical_features_enabled:
            self.action_features[selected] = 0.0
            return
        simulators = [self.slots[index].simulator for index in selected]
        observers = [self.slots[index].agent_player for index in selected]
        masks = self.action_masks[selected]
        if self.vector_tactical is not None:
            scores = self.vector_tactical.evaluate(simulators, observers, masks)
            self.action_features[selected] = self.tactical_encoder.encode_batch(
                self.observations[selected], masks, scores
            )
            return
        for index, simulator, observer in zip(selected, simulators, observers, strict=True):
            scores = simulator.tactical_action_scores(observer)
            self.tactical_encoder.encode(
                self.observations[index],
                self.action_masks[index],
                scores,
                self.action_features[index],
            )

    @staticmethod
    def _scores(slot: _Slot) -> tuple[int, int]:
        state = slot.simulator.state
        assert state is not None
        if slot.agent_player == 1:
            return state.score_human, state.score_ai
        return state.score_ai, state.score_human

    def _score_margin(self, slot: _Slot) -> int:
        own, opponent = self._scores(slot)
        return own - opponent

    def _terminal_reward(self, slot: _Slot) -> float:
        state = slot.simulator.state
        assert state is not None
        return self.reward_scheme.terminal_reward(
            state.winner, slot.agent_player, state.gods[slot.agent_player]
        )

    def _final_margin_reward(self, slot: _Slot) -> float:
        own, opponent = self._scores(slot)
        state = slot.simulator.state
        assert state is not None
        return float(self.reward_scheme.board_margin(own, opponent, state.gods[slot.agent_player]))

    def _info(
        self,
        index: int,
        agent_captures: int = 0,
        opponent_captures: int = 0,
        capture_reward: float = 0.0,
        terminal_reward: float = 0.0,
        final_margin_reward: float = 0.0,
        control_delta_reward: float = 0.0,
        *,
        include_observation: bool = True,
    ) -> dict[str, Any]:
        slot = self.slots[index]
        state = slot.simulator.state
        assert state is not None
        info: dict[str, Any] = {
            "winner": int(state.winner),
            "score_human": int(state.score_human),
            "score_ai": int(state.score_ai),
            "seed": slot.episode_seed,
            "agent_captures": int(agent_captures),
            "opponent_captures": int(opponent_captures),
            "capture_reward": float(capture_reward),
            "terminal_reward": float(terminal_reward),
            "final_margin_reward": float(final_margin_reward),
            "control_delta_reward": float(control_delta_reward),
            "first_player": slot.first_player,
            "blocked": deepcopy(slot.blocked),
        }
        if include_observation:
            info["action_mask"] = self.action_masks[index]
            if self.tactical_features_enabled:
                info["action_features"] = self.action_features[index]
        if state.is_game_over:
            own, opponent = self._scores(slot)
            god_key = "human_god" if slot.agent_player == 1 else "ai_god"
            opponent_key = "ai_god" if slot.agent_player == 1 else "human_god"
            info["episode"] = {
                "return": float(slot.episode_return),
                "agent_decisions": slot.agent_decisions,
                "turns": slot.turns,
                "agent_captures": slot.agent_captures,
                "opponent_captures": slot.opponent_captures,
                "winner": int(state.winner),
                "won": state.winner == slot.agent_player,
                "draw": state.winner == 0,
                "score": int(own),
                "opponent_score": int(opponent),
                "margin": int(own - opponent),
                "seed": slot.episode_seed,
                "agent_player": slot.agent_player,
                "first_player": slot.first_player,
                "blocked_count": len(slot.blocked),
                "god": str(slot.config.get(god_key, "")),
                "opponent_god": str(slot.config.get(opponent_key, "")),
                "opponent_id": str(getattr(slot.opponent, "selected_name", "")),
                "opponent_category": str(getattr(slot.opponent, "selected_category", "")),
                "opponent_stage": str(getattr(slot.opponent, "stage_name", "")),
            }
        return info
