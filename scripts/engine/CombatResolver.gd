## Arbitre commun aux coups réels et aux simulations.
## Coordonne la pose, les attaques puis les effets ; chaque règle vit dans son système.
class_name CombatResolver
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const Board := preload("res://scripts/engine/combat/CombatBoard.gd")
const PlacementEffects := preload("res://scripts/engine/effects/PlacementEffectResolver.gd")
const Attack := preload("res://scripts/engine/combat/AttackResolver.gd")
const PostAttackEffects := preload("res://scripts/engine/effects/PostAttackEffectResolver.gd")
const Swarm := preload("res://scripts/engine/effects/SwarmSystem.gd")

static func apply_move(state: GameState, row: int, col: int, stone_id: String, player: int) -> Dictionary:
	var placed := place_stone(state, row, col, stone_id, player)
	if not placed.get("success", false):
		return placed
	var result := finish_move(state, row, col, player)
	result["placement"] = placed
	return result

static func place_stone(state: GameState, row: int, col: int, stone_id: String, player: int) -> Dictionary:
	if not PlacementRules.is_valid(state, row, col, stone_id, player):
		return {"success": false, "reason": "invalid_placement"}
	var swarm_before := Swarm.snapshot(state)
	var definition := StoneLoader.get_stone(stone_id)
	var battle_stone: BattleStoneModel = BattleStoneModel.new()
	battle_stone.configure(stone_id, definition, state.take_instance_id())
	var placement_effects := PlacementEffects.resolve(state, battle_stone, definition)
	var index := GameState.cell_index(row, col)
	state.board[index]["stone_id"] = stone_id
	state.board[index]["owner"] = player
	state.board[index]["stone"] = battle_stone
	state.empty_playable_cells -= 1
	state.hand_of(player).erase(stone_id)
	Swarm.recalculate(state)
	var swarm_events := Swarm.transitions(
		swarm_before, Swarm.snapshot(state), row, col)
	return {
		"success": true,
		"row": row,
		"col": col,
		"stone_id": stone_id,
		"owner": player,
		"placement_effects": placement_effects,
		"swarm_events": swarm_events
	}

static func finish_move(state: GameState, row: int, col: int, player: int, attack_plan: Dictionary = {}) -> Dictionary:
	var source := Board.stone_at(state.get_cell(row, col))
	if source == null:
		return {"success": false, "reason": "missing_source", "captures": [], "effects": [], "swarm_events": []}
	var swarm_before := Swarm.snapshot(state)
	if attack_plan.is_empty():
		Swarm.recalculate(state)
		attack_plan = Attack.resolve(state, row, col, player, source)
	var captures: Array = attack_plan["captures"]
	for capture in captures:
		state.get_cell(capture["row"], capture["col"])["owner"] = player
	var effects := PostAttackEffects.resolve(state, source, row, col, player, captures)
	Swarm.recalculate(state)
	return {"success": true, "captures": captures, "attacks": attack_plan["attacks"],
		"effects": effects, "swarm_events": Swarm.transitions(swarm_before, Swarm.snapshot(state), row, col)}

## Façade stable pour les requêtes des IA et du coordinateur d'écran.
static func resolve_attacks(state: GameState, row: int, col: int, player: int, source: BattleStoneModel) -> Dictionary:
	return Attack.resolve(state, row, col, player, source)

static func find_captures(state: GameState, row: int, col: int, player: int, source: BattleStoneModel) -> Array:
	return Attack.resolve(state, row, col, player, source)["captures"]

static func recalculate_swarm(state: GameState) -> void:
	Swarm.recalculate(state)

static func swarm_links(state: GameState) -> Array:
	return Swarm.links(state)
