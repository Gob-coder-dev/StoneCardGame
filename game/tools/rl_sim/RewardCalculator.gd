## RewardCalculator.gd
## Calcule la récompense selon le système défini
extends RefCounted

const GameStateModel := preload("res://scripts/engine/GameState.gd")

static func calculate_reward(captures_count: int, state: GameState) -> float:
	var reward: float = 0.0
	
	# Récompense par capture + bonus multi-captures
	if captures_count > 0:
		reward += float(captures_count) * 1.0
		if captures_count >= 2:
			reward += 0.25 * float(captures_count - 1)
	
	# Récompense terminale
	if state.is_game_over:
		if state.winner == GameStateModel.PLAYER_AI:
			reward += 2.0
		elif state.winner == GameStateModel.PLAYER_HUMAN:
			reward += -2.0
		# Égalité = 0
	
	return reward
