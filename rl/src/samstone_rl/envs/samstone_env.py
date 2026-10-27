import gymnasium as gym
from gymnasium import spaces
import numpy as np
from samstone_rl.bridge.godot_process import GodotProcess
from .observation import ObservationEncoder
from .action_space import ActionSpace


class SamStoneEnv(gym.Env):
    """Gymnasium environment for SamStone"""
    
    metadata = {"render_modes": ["human"], "render_fps": 4}
    
    def __init__(self, render_mode=None, godot_path=None):
        super().__init__()
        
        self.render_mode = render_mode
        self.encoder = ObservationEncoder()
        self.action_space_handler = ActionSpace()
        
        # Observation space
        self.observation_space = spaces.Box(
            low=0.0, high=1.0, 
            shape=(self.encoder.get_obs_size(),), 
            dtype=np.float32
        )
        
        # Action space
        self.action_space = spaces.Discrete(self.action_space_handler.n_actions)
        
        # Godot process
        self.godot = GodotProcess(godot_path=godot_path)
        self.godot_started = False
        
        self.current_obs_raw = None
        self.current_legal_moves = []
        self.current_hand = []
    
    def reset(self, seed=None, options=None):
        super().reset(seed=seed)
        
        if not self.godot_started:
            self.godot.start()
            self.godot_started = True
        
        # Default config
        config = options.get('config', {}) if options else {}
        if not config:
            config = {
                "human_deck": ["n01_n1", "n02_n1", "n03_n1", "n04_n1", "n05_n1", "n06_n1", "n07_n1", "n08_n1"],
                "ai_deck": ["n09_n1", "n10_n1", "n11_n1", "n12_n1", "n13_n1", "n14_n1", "n15_n1", "n16_n1"],
                "human_god_id": "veskar",
                "ai_god_id": "nerava",
                "seed": seed if seed is not None else 12345,
                "ai_to_move_first": True
            }
        
        result = self.godot.reset(config)
        self.current_obs_raw = result.get('observation', {})
        self.current_legal_moves = result.get('legal_moves', [])
        self.current_hand = self.current_obs_raw.get('ai_hand', [])
        
        obs = self.encoder.encode(self.current_obs_raw)
        info = {
            'legal_moves': self.current_legal_moves,
            'legal_action_mask': self.action_space_handler.get_legal_action_mask(
                self.current_legal_moves, self.current_hand
            )
        }
        
        return obs, info
    
    def step(self, action):
        # Convert action to move
        move = self.action_space_handler.action_to_move(action, self.current_hand)
        
        # If action is illegal, try to find legal action or penalize
        legal_action_mask = self.action_space_handler.get_legal_action_mask(
            self.current_legal_moves, self.current_hand
        )
        if action >= len(legal_action_mask) or not legal_action_mask[action]:
            # Pick random legal action
            legal_actions = np.where(legal_action_mask)[0]
            if len(legal_actions) > 0:
                move = self.action_space_handler.action_to_move(
                    legal_actions[0], self.current_hand
                )
                reward_penalty = -0.01
            else:
                reward_penalty = -0.1
        else:
            reward_penalty = 0.0
        
        result = self.godot.step(move)
        self.current_obs_raw = result.get('observation', {})
        self.current_legal_moves = self.godot.get_legal_moves()
        self.current_hand = self.current_obs_raw.get('ai_hand', [])
        
        obs = self.encoder.encode(self.current_obs_raw)
        reward = result.get('reward', 0.0) + reward_penalty
        terminated = result.get('done', False)
        truncated = False
        
        info = {
            'legal_moves': self.current_legal_moves,
            'legal_action_mask': self.action_space_handler.get_legal_action_mask(
                self.current_legal_moves, self.current_hand
            ),
            'captures': result.get('info', {}).get('captures', 0)
        }
        
        return obs, reward, terminated, truncated, info
    
    def close(self):
        if self.godot_started:
            self.godot.close()
            self.godot_started = False

