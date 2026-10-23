## Plan d'attaque pur. Les impacts sont calculés avant toute capture ou effet.
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const SIDES = StoneSide.ALL
const Board := preload("res://scripts/engine/combat/CombatBoard.gd")
const DIRECTIONS = StoneSide.GRID
const OPPOSITE = StoneSide.OPPOSITE

static func resolve(state: GameState, row: int, col: int, player: int, source: BattleStoneModel) -> Dictionary:
	var captures: Array = []
	var attacks: Array = []
	for direction in SIDES:
		var normal_count := source.normal_blades(direction)
		var long_count := int(source.long_blades.get(direction, 0))
		if normal_count + long_count == 0:
			continue
		var delta: Vector2i = DIRECTIONS[direction]
		var hits: Array = []
		var adjacent_enemy := false
		var endpoint := {}
		for distance in range(1, GameState.BOARD_SIZE + 1):
			var target_row := row + delta.x * distance
			var target_col := col + delta.y * distance
			endpoint = {"row": target_row, "col": target_col, "distance": distance, "type": "exit"}
			if target_row < 0 or target_row >= GameState.BOARD_SIZE or target_col < 0 or target_col >= GameState.BOARD_SIZE:
				break
			if distance > 1 and long_count == 0:
				break
			var target_cell := state.get_cell(target_row, target_col)
			if target_cell["cell_type"] == GameState.CELL_BLOCKED:
				endpoint["type"] = "blocked"
				break
			if not Board.is_enemy(target_cell, player):
				continue
			adjacent_enemy = adjacent_enemy or distance == 1
			var target := Board.stone_at(target_cell)
			var defense_side: String = OPPOSITE[direction]
			var strength := source.attack(direction) if distance == 1 else source.ranged_attack(direction)
			var defense := target.defense(defense_side)
			var success := strength > defense
			hits.append({
				"row": target_row, "col": target_col, "distance": distance,
				"attack": strength, "defense": defense, "success": success
			})
			if success:
				captures.append(_capture_result(target_row, target_col, direction, distance, target, defense_side))
			if not success or long_count == 0:
				endpoint["type"] = "enemy"
				break
			# Une capture laisse continuer les seules lames bleues, à leur force
			# distante initiale. Une résistance ou une case bloquée arrêtera le tir.
		if not hits.is_empty():
			attacks.append({
				"direction": direction, "adjacent_enemy": adjacent_enemy,
				"normal_count": normal_count if adjacent_enemy else 0,
				"long_count": long_count, "hits": hits, "endpoint": endpoint
			})
	return {"captures": captures, "attacks": attacks}


static func _capture_result(row: int, col: int, direction: String, distance: int, target: BattleStoneModel, defense_side: String) -> Dictionary:
	return {
		"row": row,
		"col": col,
		"direction": direction,
		"distance": distance,
		"defense_side": defense_side,
		"stolen_strength": target.attack(defense_side) + int(target.shields.get(defense_side, 0)),
		"stolen_markers": target.defending_marker_indices(defense_side)
	}
