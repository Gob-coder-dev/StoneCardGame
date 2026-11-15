## Adaptateur incremental du reseau au contrat MoveSearch de l'interface.
extends RefCounted

const Encoder := preload("res://scripts/ai/neural/RLObservationEncoder.gd")
const Tactics := preload("res://scripts/ai/neural/RLTacticalFeatures.gd")
var _state: GameState
var _policy
var _observation: PackedFloat32Array
var _context: Dictionary


func _init(state: GameState, policy) -> void:
	_state = state
	_policy = policy
	_observation = Encoder.encode(state, GameState.PLAYER_AI)
	_context = policy.start_state(_observation)


func prepare_step(budget_usec: int = 0) -> bool:
	return _policy.advance_state(_context, budget_usec)


func random_samples() -> int:
	return 1


func evaluate(move: Dictionary, _sample: int) -> Dictionary:
	var slot := _state.ai_hand.find(str(move["stone_id"]))
	var action := slot * 16 + int(move["row"]) * 4 + int(move["col"])
	var features := PackedFloat32Array()
	if str(_policy.metadata["policy_spec"]["architecture"]) == "tactical_actor_critic":
		var scores := Tactics.scores(_state, GameState.PLAYER_AI, [move])
		features = Encoder.action_features(_observation, action, scores[str(action)])
	return {"value": _policy.score_action(_context, action, features), "random": false}
