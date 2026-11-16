## Point d'entrée des pouvoirs propres à la nouvelle monstre, avant sa pose.
## Ajouter un pouvoir de pose ici sans allonger CombatResolver.place_monster().
extends RefCounted
const RandomBlades := preload("res://scripts/engine/effects/RandomBladeEffect.gd")
const CoinFlip := preload("res://scripts/engine/effects/CoinFlipEffect.gd")

static func resolve(state: GameState, monster: BattleMonster, definition: Dictionary) -> Array:
	var events: Array = []
	events.append_array(RandomBlades.resolve(state, monster, definition))
	events.append_array(CoinFlip.resolve(state, monster, definition))
	return events
