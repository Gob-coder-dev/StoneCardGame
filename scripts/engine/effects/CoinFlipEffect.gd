## Tire l'issue du pile ou face et échange les faces demandées.
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const SIDES = StoneSide.ALL

static func resolve(state: GameState, battle_stone: BattleStoneModel, definition: Dictionary) -> Array:
	var events: Array = []
	var coin_axis := str(definition.get("coin_flip", ""))
	if coin_axis != "":
		var flipped := state.draw_random_index(2) == 1
		battle_stone.coin_flipped = flipped
		if flipped:
			if coin_axis == "horizontal":
				battle_stone.swap_faces("left", "right")
			else:
				battle_stone.swap_faces("top", "bottom")
		events.append(CombatEvents.coin_flip(coin_axis, flipped))

	return events
