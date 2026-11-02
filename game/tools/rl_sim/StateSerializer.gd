## Observation publique canonique pour n'importe lequel des deux joueurs.
extends RefCounted

const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")


static func serialize_for_player(state: GameState, observer: int) -> Dictionary:
	if state == null:
		return {}
	var board: Array = []
	for cell in state.board:
		var stone = cell.get("stone")
		var stone_data = null
		if stone is BattleStoneModel:
			stone_data = _battle_stone(stone, str(cell.get("stone_id", "")))
		board.append({
			"cell_type": int(cell.get("cell_type", 0)),
			"owner": int(cell.get("owner", 0)),
			"placed_by": int(cell.get("placed_by", 0)),
			"stone": stone_data
		})
	var own_hand := state.hand_of(observer)
	var opponent := GameState.PLAYER_AI if observer == GameState.PLAYER_HUMAN else GameState.PLAYER_HUMAN
	var hand: Array = []
	for stone_id in own_hand:
		hand.append(_definition(str(stone_id)))
	return {
		"schema_version": 1,
		"observer": observer,
		"board_size": GameState.BOARD_SIZE,
		"board": board,
		"hand": hand,
		"opponent_hand_size": state.hand_of(opponent).size(),
		"current_player": state.current_player,
		"empty_playable_cells": state.empty_playable_cells,
		"score_human": state.score_human,
		"score_ai": state.score_ai,
		"is_game_over": state.is_game_over,
		"winner": state.winner,
		"human_god": state.human_god_id,
		"ai_god": state.ai_god_id
	}


static func _definition(stone_id: String) -> Dictionary:
	var definition := StoneLoader.get_stone(stone_id)
	return {
		"stone_id": stone_id,
		"affinity": StoneLoader.stone_affinity(stone_id),
		"level": int(definition.get("level", 1)),
		"blades": definition.get("blades", {}).duplicate(),
		"long_blades": definition.get("long_blades", {}).duplicate(),
		"shields": definition.get("shields", {}).duplicate(),
		"random_blades": int(definition.get("random_blades", 0)),
		"effects": definition.get("effects", []).duplicate(),
		"coin_flip": str(definition.get("coin_flip", ""))
	}


static func _battle_stone(stone: BattleStoneModel, stone_id: String) -> Dictionary:
	var data := _definition(stone_id)
	data.merge({
		"instance_id": stone.instance_id,
		"base_blades": stone.base_blades.duplicate(),
		"random_blade_sides": stone.random_blades.duplicate(),
		"long_blade_sides": stone.long_blades.duplicate(),
		"shield_sides": stone.shields.duplicate(),
		"swarm_blades": stone.swarm_blades.duplicate(),
		"miasma_weakness": stone.miasma_weakness,
		"temporary_weakness": stone.temporary_weakness,
		"temporary_weakness_owner": stone.temporary_weakness_owner,
		"coin_flipped": stone.coin_flipped
	}, true)
	return data
