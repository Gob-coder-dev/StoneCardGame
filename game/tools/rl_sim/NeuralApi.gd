## Verification numerique de l'export PyTorch, dans le vrai runtime Godot.
extends RefCounted
const Policy := preload("res://scripts/ai/neural/NeuralPolicy.gd")
const Encoder := preload("res://scripts/ai/neural/RLObservationEncoder.gd")
const Tactics := preload("res://scripts/ai/neural/RLTacticalFeatures.gd")
const TurnRunner := preload("res://scripts/ai/AITurnRunner.gd")


## Exerce aussi le parcours utilise par l'interface : main adverse masquee
## et calcul reparti entre plusieurs appels MoveSearch.step().
static func choose(state: GameState, path: String) -> Dictionary:
	if state == null or state.current_player != GameState.PLAYER_AI:
		return {"error": "tour de l'IA requis"}
	var ai := TurnRunner.create_neural_ai(path)
	var search := ai.start_search(state.clone_for_ai())
	var slices := 0
	while not search.is_finished() and slices < 10000:
		search.step(1000)
		slices += 1
	return {"action": search.chosen_move(), "slices": slices,
		"finished": search.is_finished()}


static func evaluate(state: GameState, observer: int, path: String) -> Dictionary:
	var policy := Policy.new()
	var error := policy.load_file(path, false)
	if error != OK:
		return {"error": error_string(error)}
	var observation := Encoder.encode(state, observer)
	var context := policy.start_state(observation)
	var slices := 1
	while not policy.advance_state(context, 1):
		slices += 1
	var logits := PackedFloat32Array()
	logits.resize(128)
	logits.fill(-1e9)
	var features := {}
	var scores := Tactics.scores(state, observer)
	for raw_action in scores:
		var action := int(raw_action)
		var encoded := Encoder.action_features(observation, action, scores[raw_action])
		features[str(action)] = encoded
		logits[action] = policy.score_action(context, action, encoded)
	return {"observation": observation, "features": features, "logits": logits,
		"value": context["value"][0], "preparation_slices": slices}
