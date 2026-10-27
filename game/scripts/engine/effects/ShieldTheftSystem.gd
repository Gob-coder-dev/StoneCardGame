## Pillage : chaque symbole volé devient un bouclier sur une autre face que
## celle qui a capturé, tirée au hasard parmi celles qui ont encore une place.
## Le tirage utilise le hasard de la partie ; la vue ne relance aucun tirage.
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const SIDES = StoneSide.ALL

static func resolve(state: GameState, source: BattleStoneModel, row: int, col: int, captures: Array) -> Array:
	var effects: Array = []
	var shields_before := source.shields.duplicate()
	var placements: Array[String] = []
	var transfers: Array = []
	for capture in captures:
		var attacking_side := str(capture["direction"])
		for marker_index in capture.get("stolen_markers", []):
			var candidates: Array[String] = []
			for side in SIDES:
				if side != attacking_side and source.free_marker_slots(side) > 0:
					candidates.append(side)
			# Sans place sur les trois autres faces, ce symbole est perdu.
			if candidates.is_empty():
				continue
			var destination := candidates[state.draw_random_index(candidates.size())]
			source.shields[destination] = int(source.shields.get(destination, 0)) + 1
			placements.append(destination)
			transfers.append({
				"row": capture["row"], "col": capture["col"],
				"direction": attacking_side,
				"defense_side": capture["defense_side"],
				"marker_index": marker_index,
				# Faces possibles au moment du tirage : l'animation les fait clignoter.
				"candidate_sides": candidates,
				"destination_side": destination
			})
	if not transfers.is_empty():
		effects.append(CombatEvents.shield_theft(row, col, placements, shields_before, captures, transfers))
	return effects
