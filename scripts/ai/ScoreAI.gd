## Évalue le résultat immédiat de chaque coup simulé sur le plateau public.
## La main humaine et le prochain tirage réel restent cachés.
class_name ScoreAI
extends AIPlayer
const Resolver := preload("res://scripts/engine/CombatResolver.gd")

func _init() -> void:
	think_delay = 1.2

## Chaque coup n'est simulé qu'une fois : la même simulation donne le score
## obtenu et le nombre de captures qui départage les égalités.
func choose_move(state: GameState) -> Dictionary:
	var candidates: Array = []
	for move in RulesEngine.get_valid_moves(state, GameState.PLAYER_AI):
		var simulation := state.clone()
		var result := Resolver.apply_move(simulation, move["row"], move["col"], move["stone_id"], GameState.PLAYER_AI)
		var score := RulesEngine.calculate_score(simulation)
		candidates.append({
			"move": move,
			"captures": result.get("captures", []).size(),
			"value": score["ai"] - score["human"]
		})
	# À score égal, le coup qui capture le plus est examiné en premier.
	candidates.sort_custom(func(a, b): return a["captures"] > b["captures"])
	var best_value := -9999
	var best_move: Dictionary = {}
	for candidate in candidates:
		if candidate["value"] > best_value:
			best_value = candidate["value"]
			best_move = candidate["move"].duplicate()
	return best_move
