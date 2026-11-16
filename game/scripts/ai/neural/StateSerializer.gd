## Observation publique canonique pour n'importe lequel des deux joueurs.
extends RefCounted

const BattleMonsterModel := preload("res://scripts/engine/BattleMonster.gd")


static func serialize_for_player(state: GameState, observer: int) -> Dictionary:
	if state == null:
		return {}
	var board: Array = []
	for cell in state.board:
		var monster = cell.get("monster")
		var monster_data = null
		if monster is BattleMonsterModel:
			monster_data = _battle_monster(monster, str(cell.get("monster_id", "")))
		board.append({
			"cell_type": int(cell.get("cell_type", 0)),
			"owner": int(cell.get("owner", 0)),
			"placed_by": int(cell.get("placed_by", 0)),
			"monster": monster_data
		})
	var own_hand := state.hand_of(observer)
	var opponent := GameState.PLAYER_AI if observer == GameState.PLAYER_HUMAN else GameState.PLAYER_HUMAN
	var hand: Array = []
	for monster_id in own_hand:
		hand.append(_definition(str(monster_id)))
	return {
		"schema_version": 1,
		"observer": observer,
		"board_size": state.board_size,
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


static func _definition(monster_id: String) -> Dictionary:
	var definition := MonsterLoader.get_monster(monster_id)
	return {
		"monster_id": monster_id,
		"affinity": MonsterLoader.monster_affinity(monster_id),
		"level": int(definition.get("level", 1)),
		"blades": definition.get("blades", {}).duplicate(),
		"long_blades": definition.get("long_blades", {}).duplicate(),
		"shields": definition.get("shields", {}).duplicate(),
		"random_blades": int(definition.get("random_blades", 0)),
		"effects": definition.get("effects", []).duplicate(),
		"coin_flip": str(definition.get("coin_flip", ""))
	}


static func _battle_monster(monster: BattleMonsterModel, monster_id: String) -> Dictionary:
	var data := _definition(monster_id)
	data.merge({
		"instance_id": monster.instance_id,
		"base_blades": monster.base_blades.duplicate(),
		"random_blade_sides": monster.random_blades.duplicate(),
		"long_blade_sides": monster.long_blades.duplicate(),
		"shield_sides": monster.shields.duplicate(),
		"swarm_blades": monster.swarm_blades.duplicate(),
		"miasma_weakness": monster.miasma_weakness,
		"temporary_weakness": monster.temporary_weakness,
		"temporary_weakness_owner": monster.temporary_weakness_owner,
		"coin_flipped": monster.coin_flipped
	}, true)
	return data
