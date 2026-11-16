## Place uniquement les lames aléatoires, avec le RNG de la partie.
extends RefCounted
const BattleMonsterModel := preload("res://scripts/engine/BattleMonster.gd")
const SIDES = MonsterSide.ALL

static func resolve(state: GameState, battle_monster: BattleMonsterModel, definition: Dictionary) -> Array:
	var events: Array = []
	var random_count := int(definition.get("random_blades", 0))
	for i in range(random_count):
		var candidates: Array[String] = []
		for side in SIDES:
			if battle_monster.free_marker_slots(side) > 0:
				candidates.append(side)
		if candidates.is_empty():
			break
		var chosen := candidates[state.draw_random_index(candidates.size())]
		battle_monster.random_blades[chosen] = int(battle_monster.random_blades[chosen]) + 1
		events.append(CombatEvents.random_blade(chosen))

	return events
