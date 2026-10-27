## Point d'entrée des pouvoirs propres à la nouvelle pierre, avant sa pose.
## Ajouter un pouvoir de pose ici sans allonger CombatResolver.place_stone().
extends RefCounted
const RandomBlades := preload("res://scripts/engine/effects/RandomBladeEffect.gd")
const CoinFlip := preload("res://scripts/engine/effects/CoinFlipEffect.gd")

static func resolve(state: GameState, stone: BattleStone, definition: Dictionary) -> Array:
	var events: Array = []
	events.append_array(RandomBlades.resolve(state, stone, definition))
	events.append_array(CoinFlip.resolve(state, stone, definition))
	return events
