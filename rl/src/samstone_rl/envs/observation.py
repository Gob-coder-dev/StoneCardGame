import numpy as np
from typing import Dict, Any


class ObservationEncoder:
    """Encode GameState observation for RL agent"""
    
    def __init__(self):
        self.board_size = 4
        self.max_hand_size = 8
    
    def encode(self, obs: Dict[str, Any]) -> np.ndarray:
        """
        Encode observation into a flat numpy array
        Respects info masking - opponent hand is masked
        """
        features = []
        
        # Board state (16 cells * features)
        board = obs.get('board', [])
        for cell in board:
            # Owner: 0=none, 1=human, 2=ai
            features.append(float(cell.get('owner', 0)) / 2.0)
            # Cell type: 0=empty, -1=blocked
            cell_type = cell.get('cell_type', 0)
            features.append(1.0 if cell_type == -1 else 0.0)  # blocked
            features.append(1.0 if cell_type == 0 and cell.get('owner', 0) == 0 else 0.0)  # empty
            # Has stone
            has_stone = 1.0 if cell.get('stone') is not None else 0.0
            features.append(has_stone)
            # Stone owner relative to AI (1 if AI owns)
            stone_owner = cell.get('owner', 0)
            features.append(1.0 if stone_owner == 2 else 0.0)  # AI owns
            features.append(1.0 if stone_owner == 1 else 0.0)  # Human owns
        
        # Game state
        features.append(float(obs.get('current_player', 2)) / 2.0)
        features.append(float(obs.get('empty_playable_cells', 0)) / 16.0)
        features.append(float(obs.get('score_ai', 0)) / 16.0)
        features.append(float(obs.get('score_human', 0)) / 16.0)
        features.append(float(obs.get('ai_hand_size', 0)) / 8.0)
        features.append(float(obs.get('human_hand_size', 0)) / 8.0)
        features.append(1.0 if obs.get('is_game_over', False) else 0.0)
        
        # God info
        ai_god = obs.get('ai_god_id', '')
        human_god = obs.get('human_god_id', '')
        god_features = self._encode_gods(ai_god, human_god)
        features.extend(god_features)
        
        return np.array(features, dtype=np.float32)
    
    def _encode_gods(self, ai_god: str, human_god: str) -> list:
        gods = ['veskar', 'nerava', 'kharun', 'ilyr', 'sylkha', 'enigma']
        features = []
        for g in gods:
            features.append(1.0 if ai_god == g else 0.0)
        for g in gods:
            features.append(1.0 if human_god == g else 0.0)
        return features
    
    def get_obs_size(self) -> int:
        # 16 cells * 6 features + 7 game state + 12 god features
        return 16 * 6 + 7 + 12

