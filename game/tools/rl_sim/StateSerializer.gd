## StateSerializer.gd
## Sérialise GameState pour l'observation RL avec masquage d'information
extends RefCounted

const GameStateModel := preload("res://scripts/engine/GameState.gd")
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")

static func serialize_state(state: GameState, mask_opponent_hand: bool = true) -> Dictionary:
	if state == null:
		return {}
	
	var board_data = []
	for i in range(state.board.size()):
		var cell = state.board[i]
		var stone = cell.get("stone")
		var stone_info = null
		if stone != null and stone is BattleStoneModel:
			stone_info = {
				"instance_id": stone.instance_id,
				"stone_id": stone.stone_id,
				"base_blades": stone.base_blades.duplicate(),
				"random_blades": stone.random_blades.duplicate(),
				"long_blades": stone.long_blades.duplicate(),
				"shields": stone.shields.duplicate(),
				"swarm_blades": stone.swarm_blades.duplicate(),
				"miasma_weakness": stone.miasma_weakness,
				"temporary_weakness": stone.temporary_weakness
			}
		board_data.append({
			"cell_type": cell.get("cell_type", 0),
			"stone_id": cell.get("stone_id", ""),
			"stone": stone_info,
			"owner": cell.get("owner", 0),
			"placed_by": cell.get("placed_by", 0)
		})
	
	var ai_hand_data = []
	for sid in state.ai_hand:
		ai_hand_data.append(sid)
	
	var human_hand_data = []
	if mask_opponent_hand:
		# Masquer la main humaine - garder uniquement la taille
		human_hand_data = [""] * state.human_hand.size()
	else:
		for sid in state.human_hand:
			human_hand_data.append(sid)
	
	return {
		"board": board_data,
		"ai_hand": ai_hand_data,
		"human_hand": human_hand_data,
		"human_hand_size": state.human_hand.size(),
		"ai_hand_size": state.ai_hand.size(),
		"current_player": state.current_player,
		"empty_playable_cells": state.empty_playable_cells,
		"score_human": state.score_human,
		"score_ai": state.score_ai,
		"is_game_over": state.is_game_over,
		"winner": state.winner,
		"human_god_id": state.human_god_id,
		"ai_god_id": state.ai_god_id,
		"board_size": GameStateModel.BOARD_SIZE
	}
