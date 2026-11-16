## Ordre unique des effets post-attaque, partagé par la partie et les IA.
## attack_plan est le plan d'AttackResolver : captures et attaques ratées.
extends RefCounted
const Weakness := preload("res://scripts/engine/effects/WeaknessSystem.gd")
const Theft := preload("res://scripts/engine/effects/ShieldTheftSystem.gd")
const Effects := preload("res://scripts/domain/MonsterEffects.gd")

static func resolve(state: GameState, source: BattleMonster, row: int, col: int, player: int, attack_plan: Dictionary) -> Array:
	var events: Array = []
	var captures: Array = attack_plan.get("captures", [])
	# L'aura du Miasme est continue : chaque coup peut l'étendre (pose à côté
	# d'un monstre Miasme) ou la réduire (capture), quelle que soit la carte posée.
	events.append_array(Weakness.update_miasma(state, row, col))
	if MonsterLoader.has_effect(source.monster_id, Effects.SHIELD_THEFT):
		events.append_array(Theft.resolve(state, source, row, col, captures))
	# Le coup profite encore de l'ancien malus avant son expiration.
	events.append_array(Weakness.expire_for_player(state, player))
	if MonsterLoader.has_effect(source.monster_id, Effects.WEAKEN_ON_FAILED_ATTACK):
		events.append_array(Weakness.apply_failed_attack(state, row, col, player, attack_plan.get("attacks", [])))
	return events
