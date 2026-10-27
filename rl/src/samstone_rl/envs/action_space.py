import numpy as np
from typing import List, Dict, Any


class ActionSpace:
    """Action space for SamStone - place card from hand to board cell"""
    
    def __init__(self, board_size: int = 4, max_hand_size: int = 8):
        self.board_size = board_size
        self.max_hand_size = max_hand_size
        self.total_cells = board_size * board_size
        self.n_actions = max_hand_size * self.total_cells
    
    def action_to_move(self, action: int, hand: List[str]) -> Dict[str, Any]:
        """Convert action index to move dict"""
        card_idx = action // self.total_cells
        cell_idx = action % self.total_cells
        row = cell_idx // self.board_size
        col = cell_idx % self.board_size
        
        stone_id = ""
        if card_idx < len(hand):
            stone_id = hand[card_idx]
        
        return {"row": row, "col": col, "stone_id": stone_id}
    
    def move_to_action(self, move: Dict[str, Any], hand: List[str]) -> int:
        """Convert move dict to action index"""
        stone_id = move.get("stone_id", "")
        row = move.get("row", 0)
        col = move.get("col", 0)
        
        card_idx = 0
        for i, sid in enumerate(hand):
            if sid == stone_id:
                card_idx = i
                break
        
        cell_idx = row * self.board_size + col
        return card_idx * self.total_cells + cell_idx
    
    def get_legal_action_mask(self, legal_moves: List[Dict[str, Any]], hand: List[str]) -> np.ndarray:
        """Create legal action mask"""
        mask = np.zeros(self.n_actions, dtype=bool)
        for move in legal_moves:
            action = self.move_to_action(move, hand)
            if 0 <= action < self.n_actions:
                mask[action] = True
        return mask

