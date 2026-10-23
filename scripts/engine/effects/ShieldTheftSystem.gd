## Pillage : transferts vers des emplacements libres, sans changement du RNG visuel.
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const SIDES = StoneSide.ALL

static func resolve(state: GameState, source: BattleStoneModel, row: int, col: int, captures: Array) -> Array:
	var effects: Array = []
	var shields_before := source.shields.duplicate()
	var placements: Array[String] = []
	var stolen_sources: Array = []
	for capture in captures:
		for marker_index in capture.get("stolen_markers", []):
			stolen_sources.append({
				"row": capture["row"], "col": capture["col"],
				"direction": capture["direction"],
				"defense_side": capture["defense_side"],
				"marker_index": marker_index
			})
	var gained := 0
	var transfers: Array = []
	for stolen_source in stolen_sources:
		var candidates: Array[String] = []
		for candidate in SIDES:
			if source.free_marker_slots(candidate) > 0:
				candidates.append(candidate)
		if candidates.is_empty():
			break
		var side := candidates[state.draw_random_index(candidates.size())]
		source.shields[side] = int(source.shields.get(side, 0)) + 1
		placements.append(side)
		var transfer: Dictionary = stolen_source.duplicate()
		transfer["destination_side"] = side
		transfers.append(transfer)
		gained += 1
	if gained > 0:
		effects.append(CombatEvents.shield_theft(row, col, placements, shields_before, captures, transfers))
	return effects
