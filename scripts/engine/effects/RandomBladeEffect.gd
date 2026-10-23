## Place uniquement les lames aléatoires, avec le RNG de la partie.
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const SIDES = StoneSide.ALL

static func resolve(state: GameState, battle_stone: BattleStoneModel, definition: Dictionary) -> Array:
	var events: Array = []
	var random_count := int(definition.get("random_blades", 0))
	for i in range(random_count):
		var candidates: Array[String] = []
		for side in SIDES:
			if battle_stone.free_marker_slots(side) > 0:
				candidates.append(side)
		if candidates.is_empty():
			break
		var chosen := candidates[state.draw_random_index(candidates.size())]
		battle_stone.random_blades[chosen] = int(battle_stone.random_blades[chosen]) + 1
		events.append(CombatEvents.random_blade(chosen))

	return events
