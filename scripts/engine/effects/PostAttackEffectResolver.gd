## Ordre unique des effets post-attaque, partagé par la partie et les IA.
## attack_plan est le plan d'AttackResolver : captures et attaques ratées.
extends RefCounted
const Weakness := preload("res://scripts/engine/effects/WeaknessSystem.gd")
const Theft := preload("res://scripts/engine/effects/ShieldTheftSystem.gd")
const Effects := preload("res://scripts/domain/StoneEffects.gd")

static func resolve(state: GameState, source: BattleStone, row: int, col: int, player: int, attack_plan: Dictionary) -> Array:
	var events: Array = []
	var captures: Array = attack_plan.get("captures", [])
	if StoneLoader.has_effect(source.stone_id, Effects.WEAKEN_ADJACENT):
		events.append_array(Weakness.apply_miasma(state, row, col))
	if StoneLoader.has_effect(source.stone_id, Effects.SHIELD_THEFT):
		events.append_array(Theft.resolve(state, source, row, col, captures))
	# Le coup profite encore de l'ancien malus avant son expiration.
	events.append_array(Weakness.expire_for_player(state, player))
	if StoneLoader.has_effect(source.stone_id, Effects.WEAKEN_ON_FAILED_ATTACK):
		events.append_array(Weakness.apply_failed_attack(state, row, col, player, attack_plan.get("attacks", [])))
	return events
