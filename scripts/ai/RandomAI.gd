## RandomAI.gd
## IA facile : un coup valide au hasard. Ne réfléchit pas.
class_name RandomAI
extends AIPlayer


func _init() -> void:
	think_delay = 0.6


func choose_move(state: GameState) -> Dictionary:
	var moves := RulesEngine.get_valid_moves(state, GameState.PLAYER_AI)
	if moves.is_empty():
		return {}
	return moves[randi() % moves.size()]
