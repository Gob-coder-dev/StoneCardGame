## Boss exporte et certifie. Les profils actuels restent disponibles en parallele.
extends AIPlayer

const Policy := preload("res://scripts/ai/neural/NeuralPolicy.gd")
const Evaluator := preload("res://scripts/ai/neural/NeuralMoveEvaluator.gd")
const Search := preload("res://scripts/ai/MoveSearch.gd")
const ProfileAIModel := preload("res://scripts/ai/ProfileAI.gd")
const Profile := preload("res://scripts/ai/AIProfile.gd")
var _policy := Policy.new()
var _loaded := false
var _fallback := ProfileAIModel.new(Profile.new({"precision": 1.0, "anticipation": true}))


func _init(path: String) -> void:
	var error := _policy.load_file(path)
	_loaded = error == OK
	if not _loaded:
		push_error("NeuralAI: politique absente ou incompatible (%s): %s" % [error_string(error), path])


func start_search(state: GameState) -> MoveSearch:
	if not _loaded or state.board_size != 4 or state.ai_god_id != str(_policy.metadata.get("god", "")):
		return _fallback.start_search(state)
	var expected: Array = _policy.metadata.get("deck", []).duplicate()
	var actual: Array = state.ai_hand.duplicate()
	for cell in state.board:
		if int(cell["placed_by"]) == GameState.PLAYER_AI:
			actual.append(str(cell["monster_id"]))
	expected.sort()
	actual.sort()
	if actual != expected:
		push_error("NeuralAI: le deck ne correspond pas a la politique certifiee.")
		return _fallback.start_search(state)
	var moves := RulesEngine.get_valid_moves(state, GameState.PLAYER_AI)
	moves.sort_custom(func(a: Dictionary, b: Dictionary):
		return state.ai_hand.find(str(a["monster_id"])) * 16 + int(a["row"]) * 4 + int(a["col"]) < state.ai_hand.find(str(b["monster_id"])) * 16 + int(b["row"]) * 4 + int(b["col"]))
	return Search.new(moves, Evaluator.new(state, _policy), _choose)


func _choose(scored: Array) -> Dictionary:
	var best := -INF
	var chosen := {}
	# Canonical action order resolves equal logits identically to torch.argmax.
	for entry in scored:
		var move: Dictionary = entry["move"]
		var value := float(entry["value"])
		if value > best:
			best = value
			chosen = move
	return chosen
