## GreedyAI.gd
## IA moyenne : choisit le coup qui capture le plus immédiatement.
## Égalités départagées au hasard. Myope (un seul coup d'avance).
class_name GreedyAI
extends AIPlayer


func _init() -> void:
	think_delay = 1.0


func choose_move(state: GameState) -> Dictionary:
	var moves := RulesEngine.get_valid_moves(state, GameState.PLAYER_AI)
	if moves.is_empty():
		return {}

	var best_score: int = -1
	var best_moves: Array = []

	for move in moves:
		var capture_count := RulesEngine.count_captures(
			state, move["row"], move["col"], move["stone_id"], GameState.PLAYER_AI
		)
		if capture_count > best_score:
			best_score = capture_count
			best_moves = [move]
		elif capture_count == best_score:
			best_moves.append(move)

	return best_moves[randi() % best_moves.size()]
