from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from typing import Any, ClassVar

import gymnasium as gym
import numpy as np
from gymnasium import spaces

from samstone_rl.bridge.godot_process import GodotProcess
from samstone_rl.fast_engine import FastEngineBridge
from samstone_rl.opponents import Opponent, RandomOpponent
from samstone_rl.tactics import TacticalActionEncoder

from .action_space import ActionCodec
from .observation import ObservationEncoder

DEFAULT_CONFIG: dict[str, Any] = {
    "human_deck": ["devoracle_n3", "griffe_a_jetons_n3", "sou_ricanant_n3", "croupier_manchot_n2", "jumeau_de_cuivre_n2", "valet_a_lenvers_n2", "avortons_des_caves_n2", "le_voyeur_n1"],
    "ai_deck": ["devoracle_n3", "griffe_a_jetons_n3", "sou_ricanant_n3", "croupier_manchot_n2", "jumeau_de_cuivre_n2", "valet_a_lenvers_n2", "avortons_des_caves_n2", "le_voyeur_n1"],
    "human_god": "veskar",
    "ai_god": "veskar",
}


@dataclass(frozen=True)
class RewardScheme:
    """Dense guidance kept deliberately smaller than the match result."""

    capture: float = 0.10
    multi_capture: float = 0.025
    terminal: float = 2.0
    final_margin: float = 0.0
    final_margin_scale: float = 5.0
    board_control_delta: float = 0.0
    board_control_delta_limit: int = 4

    def captures(self, count: int) -> float:
        return self.capture * count + self.multi_capture * max(0, count - 1)

    def board_margin(self, own_score: int, opponent_score: int) -> float:
        """Return bounded terminal shaping from the final score difference."""
        if self.final_margin == 0.0:
            return 0.0
        scale = max(float(self.final_margin_scale), 1e-6)
        return float(self.final_margin * np.tanh((own_score - opponent_score) / scale))

    def control_delta(self, previous_margin: int, current_margin: int) -> float:
        """Reward durable board control gained over a complete Gym transition.

        A Gym transition includes the agent action *and* all immediate opponent
        replies.  Rewarding the margin difference here therefore does not pay
        for a card which is captured and immediately lost again.
        """
        if self.board_control_delta == 0.0:
            return 0.0
        limit = max(int(self.board_control_delta_limit), 1)
        delta = int(np.clip(current_margin - previous_margin, -limit, limit))
        return float(self.board_control_delta * delta)


class MaskedDiscrete(spaces.Discrete):
    """Discrete space whose default sampler follows the environment's live mask."""

    def __init__(self, n: int) -> None:
        super().__init__(n)
        self.current_mask: np.ndarray | None = None

    def sample(self, mask=None, probability=None):
        if mask is None:
            mask = self.current_mask
        return super().sample(mask=mask, probability=probability)

    def set_mask(self, mask: np.ndarray) -> None:
        self.current_mask = np.asarray(mask, dtype=np.int8)


class SamStoneEnv(gym.Env[np.ndarray, int]):
    """One agent decision followed by opponent replies is one Gym transition."""

    metadata: ClassVar[dict[str, list[str]]] = {"render_modes": []}

    def __init__(self, godot_path: str | None = None, project_path: str | None = None,
                 opponent: Opponent | None = None, agent_player: int = 1,
                 match_config: dict[str, Any] | None = None,
                 reward_scheme: RewardScheme | None = None,
                 backend: str = "godot", tactical_features: bool = False) -> None:
        super().__init__()
        if agent_player not in (1, 2):
            raise ValueError("agent_player doit valoir 1 ou 2")
        self.agent_player = agent_player
        self.opponent: Opponent = opponent or RandomOpponent()
        self.match_config = deepcopy(match_config or DEFAULT_CONFIG)
        self.reward_scheme = reward_scheme or RewardScheme()
        self.encoder = ObservationEncoder()
        self.codec = ActionCodec()
        self.tactical_features_enabled = bool(tactical_features)
        self.tactical_encoder = TacticalActionEncoder()
        self.observation_space = spaces.Box(-1.0, 1.0, (self.encoder.get_obs_size(),), dtype=np.float32)
        self.action_space = MaskedDiscrete(self.codec.n_actions)
        if backend not in ("godot", "python"):
            raise ValueError("backend doit valoir 'godot' ou 'python'")
        self.backend = backend
        self.bridge = (FastEngineBridge(project_path=project_path) if backend == "python"
                       else GodotProcess(project_path=project_path, godot_path=godot_path))
        self._raw: dict[str, Any] = {}
        self._legal: list[dict[str, Any]] = []
        self._episode_seed = 0
        self._episode_return = 0.0
        self._episode_agent_decisions = 0
        self._episode_turns = 0
        self._episode_agent_captures = 0
        self._episode_opponent_captures = 0
        self._blocked: list[list[int]] = []
        self._first_player = 0
        self._episode_config: dict[str, Any] = {}
        self._trace_enabled = False
        self._trace: list[dict[str, Any]] = []

    def reset(self, *, seed: int | None = None, options: dict[str, Any] | None = None):
        super().reset(seed=seed)
        if self.bridge.process is None:
            self.bridge.start()
        self._episode_seed = int(seed if seed is not None else self.np_random.integers(1, 2**31 - 1))
        config = deepcopy(self.match_config)
        config.update(deepcopy((options or {}).get("config", {})))
        config["seed"] = self._episode_seed
        self._episode_return = 0.0
        self._episode_agent_decisions = 0
        self._episode_turns = 0
        self._episode_agent_captures = 0
        self._episode_opponent_captures = 0
        self._trace_enabled = bool((options or {}).get("trace", False))
        self._trace = []
        self._episode_config = deepcopy(config)
        self.opponent.begin_episode(self.np_random)
        result = self.bridge.reset(config, self.agent_player)
        self._blocked = deepcopy(result.get("blocked", []))
        self._first_player = int(result.get("first_player", config.get("first_player", 0)))
        self._consume(result)
        opening_captures = self._play_opponent_turns()
        self._episode_opponent_captures += opening_captures
        return self.encoder.encode(self._raw), self._info()

    def step(self, action: int):
        mask = self.codec.legal_mask(self._legal, self._raw["hand"])
        if action < 0 or action >= len(mask) or not bool(mask[action]):
            raise ValueError(f"action illegale: {action}")
        previous_margin = self._score_margin()
        move = self.codec.action_to_move(int(action), self._raw["hand"])
        result = self.bridge.step(move, self.agent_player)
        agent_captures = len(result.get("captures", []))
        self._record_action(self.agent_player, move, result)
        self._episode_agent_decisions += 1
        self._episode_agent_captures += agent_captures
        self._consume(result)
        opponent_captures = self._play_opponent_turns()
        self._episode_opponent_captures += opponent_captures
        terminated = bool(self._raw["is_game_over"])
        capture_reward = (self.reward_scheme.captures(agent_captures)
                          - self.reward_scheme.captures(opponent_captures))
        terminal_reward = self._terminal_reward() if terminated else 0.0
        final_margin_reward = self._final_margin_reward() if terminated else 0.0
        control_delta_reward = self.reward_scheme.control_delta(
            previous_margin, self._score_margin())
        reward = capture_reward + terminal_reward + final_margin_reward + control_delta_reward
        self._episode_return += reward
        return self.encoder.encode(self._raw), float(reward), terminated, False, self._info(
            agent_captures, opponent_captures, capture_reward, terminal_reward,
            final_margin_reward, control_delta_reward)

    def close(self) -> None:
        self.bridge.close()

    def _play_opponent_turns(self) -> int:
        captures = 0
        while not self._raw["is_game_over"] and int(self._raw["current_player"]) != self.agent_player:
            player = int(self._raw["current_player"])
            move = self.opponent.choose(self.bridge, self._legal, self.np_random, player)
            result = self.bridge.step(move, self.agent_player)
            captures += len(result.get("captures", []))
            self._record_action(player, move, result)
            self._consume(result)
        return captures

    def _consume(self, result: dict[str, Any]) -> None:
        self._raw = result["observation"]
        self._legal = result.get("legal_actions", [])
        if not self._raw["is_game_over"] and int(self._raw["current_player"]) == self.agent_player:
            self.action_space.set_mask(self.codec.legal_mask(self._legal, self._raw["hand"]))

    def _terminal_reward(self) -> float:
        winner = int(self._raw["winner"])
        return self.reward_scheme.terminal if winner == self.agent_player else (
            -self.reward_scheme.terminal if winner else 0.0)

    def _final_margin_reward(self) -> float:
        return self.reward_scheme.board_margin(self._own_score(), self._opponent_score())

    def _own_score(self) -> int:
        return int(self._raw["score_human"] if self.agent_player == 1
                   else self._raw["score_ai"])

    def _opponent_score(self) -> int:
        return int(self._raw["score_ai"] if self.agent_player == 1
                   else self._raw["score_human"])

    def _score_margin(self) -> int:
        return self._own_score() - self._opponent_score()

    def _info(self, agent_captures: int = 0, opponent_captures: int = 0,
              capture_reward: float = 0.0, terminal_reward: float = 0.0,
              final_margin_reward: float = 0.0,
              control_delta_reward: float = 0.0) -> dict[str, Any]:
        action_mask = self.codec.legal_mask(self._legal, self._raw["hand"])
        info: dict[str, Any] = {
            "action_mask": action_mask,
            "winner": int(self._raw.get("winner", 0)),
            "score_human": int(self._raw.get("score_human", 0)),
            "score_ai": int(self._raw.get("score_ai", 0)),
            "seed": self._episode_seed,
            "agent_captures": agent_captures,
            "opponent_captures": opponent_captures,
            "capture_reward": float(capture_reward),
            "terminal_reward": float(terminal_reward),
            "final_margin_reward": float(final_margin_reward),
            "control_delta_reward": float(control_delta_reward),
            "first_player": self._first_player,
            "blocked": deepcopy(self._blocked),
        }
        if self.tactical_features_enabled:
            if not hasattr(self.bridge, "tactical_action_scores"):
                raise RuntimeError(
                    "ce backend ne fournit pas encore les features tactiques")
            scores = self.bridge.tactical_action_scores(self.agent_player)
            observation = self.encoder.encode(self._raw)
            info["action_features"] = self.tactical_encoder.encode(
                observation, action_mask, scores)
        if bool(self._raw.get("is_game_over", False)):
            own_score = int(self._raw["score_human"] if self.agent_player == 1
                            else self._raw["score_ai"])
            opponent_score = int(self._raw["score_ai"] if self.agent_player == 1
                                 else self._raw["score_human"])
            episode = {
                "return": float(self._episode_return),
                "agent_decisions": self._episode_agent_decisions,
                "turns": self._episode_turns,
                "agent_captures": self._episode_agent_captures,
                "opponent_captures": self._episode_opponent_captures,
                "winner": int(self._raw.get("winner", 0)),
                "won": int(self._raw.get("winner", 0)) == self.agent_player,
                "draw": int(self._raw.get("winner", 0)) == 0,
                "score": own_score,
                "opponent_score": opponent_score,
                "margin": own_score - opponent_score,
                "seed": self._episode_seed,
                "agent_player": self.agent_player,
                "first_player": self._first_player,
                "blocked_count": len(self._blocked),
                "god": str(self._episode_config.get(
                    "human_god" if self.agent_player == 1 else "ai_god", "")),
                "opponent_god": str(self._episode_config.get(
                    "ai_god" if self.agent_player == 1 else "human_god", "")),
                "opponent_id": str(getattr(self.opponent, "selected_name", "")),
                "opponent_category": str(getattr(self.opponent, "selected_category", "")),
            }
            if self._trace_enabled:
                episode["actions"] = deepcopy(self._trace)
            info["episode"] = episode
        return info

    def _record_action(self, player: int, move: dict[str, Any], result: dict[str, Any]) -> None:
        self._episode_turns += 1
        if not self._trace_enabled:
            return
        self._trace.append({
            "turn": self._episode_turns,
            "player": int(player),
            "stone_id": str(move.get("stone_id", "")),
            "row": int(move.get("row", -1)),
            "col": int(move.get("col", -1)),
            "captures": len(result.get("captures", [])),
            "effects": deepcopy(result.get("effects", [])),
            "placement_effects": deepcopy(result.get("placement_effects", [])),
        })
