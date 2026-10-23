## Ordre unique des effets post-attaque, partagé par la partie et les IA.
extends RefCounted
const Weakness := preload("res://scripts/engine/effects/WeaknessSystem.gd")
const Theft := preload("res://scripts/engine/effects/ShieldTheftSystem.gd")

static func resolve(state: GameState, source: BattleStone, row: int, col: int, player: int, captures: Array) -> Array:
	var flags: Array = StoneLoader.get_stone(source.stone_id).get("effects", [])
	var events: Array = Weakness.apply_miasma(state, row, col, flags)
	if flags.has(CombatEvents.SHIELD_THEFT):
		events.append_array(Theft.resolve(state, source, row, col, captures))
	# Le coup profite encore de l'ancien malus avant son expiration.
	events.append_array(Weakness.expire_for_player(state, player))
	events.append_array(Weakness.apply_failed_attack(state, row, col, player, captures, flags))
	return events
