## Évalue le résultat immédiat de chaque coup simulé sur le plateau public.
## La main humaine et le prochain tirage réel restent cachés.
class_name ScoreAI
extends AIPlayer
const Resolver := preload("res://scripts/engine/CombatResolver.gd")

func _init() -> void:
	think_delay = 1.2

func choose_move(state: GameState) -> Dictionary:
	var moves := RulesEngine.get_valid_moves_sorted(state, GameState.PLAYER_AI)
	var best_score := -9999
	var best_move: Dictionary = {}
	for move in moves:
		var simulation := state.clone()
		Resolver.apply_move(simulation, move["row"], move["col"], move["stone_id"], GameState.PLAYER_AI)
		var score := RulesEngine.calculate_score(simulation)
		var value: int = score["ai"] - score["human"]
		if value > best_score:
			best_score = value
			best_move = move.duplicate()
	best_move.erase("_captures")
	return best_move
