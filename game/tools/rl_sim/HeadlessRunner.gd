## HeadlessRunner.gd
## Serveur de commandes JSON via stdin/stdout pour le simulateur RL
extends Node

const TurnManagerModel := preload("res://scripts/engine/TurnManager.gd")
const GameStateModel := preload("res://scripts/engine/GameState.gd")
const RulesEngineModel := preload("res://scripts/engine/RulesEngine.gd")
const PlacementRulesModel := preload("res://scripts/engine/PlacementRules.gd")
const CombatResolverModel := preload("res://scripts/engine/CombatResolver.gd")
const BoardSetupGenerator := preload("res://scripts/engine/BoardSetupGenerator.gd")

const StateSerializer := preload("res://tools/rl_sim/StateSerializer.gd")
const RewardCalculator := preload("res://tools/rl_sim/RewardCalculator.gd")

var turn_manager: Node = null
var current_config: Dictionary = {}

func _ready() -> void:
	print("RL_SIM_READY")
	flush_stdout()
	set_process(true)

func flush_stdout():
	# Force flush in headless
	pass


func _process(_delta: float) -> void:
	if not OS.is_stdin_enabled():
		return
	
	# Read line from stdin
	var input = OS.read_string_from_stdin()
	if input == "":
		return
	
	# Process each line
	var lines = input.split("\n", false)
	for line in lines:
		if line.strip_edges() == "":
			continue
		_handle_command(line.strip_edges())

func _handle_command(line: String) -> void:
	var parsed = JSON.parse_string(line)
	if not parsed is Dictionary:
		_send_response({"ok": false, "error": "invalid_json"})
		return
	
	var cmd = parsed.get("cmd", "")
	var req_id = parsed.get("id", 0)
	
	match cmd:
		"ping":
			_send_response({"ok": true, "id": req_id, "result": {"pong": true}})
		"reset":
			var result = _handle_reset(parsed.get("config", {}))
			_send_response({"ok": true, "id": req_id, "result": result})
		"get_legal_moves":
			var result = _handle_legal_moves()
			_send_response({"ok": true, "id": req_id, "result": result})
		"step":
			var action = parsed.get("action", {})
			var result = _handle_step(action)
			_send_response({"ok": true, "id": req_id, "result": result})
		_:
			_send_response({"ok": false, "id": req_id, "error": "unknown_command"})

func _handle_reset(config: Dictionary) -> Dictionary:
	current_config = config
	var human_deck = config.get("human_deck", [])
	var ai_deck = config.get("ai_deck", [])
	var human_god = config.get("human_god", "")
	var ai_god = config.get("ai_god", "")
	var seed = config.get("seed", randi())
	var blocked = config.get("blocked", [])
	
	turn_manager = TurnManagerModel.new()
	add_child(turn_manager)
	
	# Generate blocked cells if empty
	if blocked.is_empty() and config.get("random_blocked", false):
		blocked = BoardSetupGenerator.generate_blocked_cells()
	
	var forced_first = config.get("forced_first_player", 0)
	turn_manager.start_game(human_deck, ai_deck, blocked, "", forced_first, human_god, ai_god)
	
	var state = turn_manager.get_state()
	# Force AI to be current player if requested
	if config.get("ai_to_move_first", false):
		state.current_player = GameStateModel.PLAYER_AI
	
	var obs = StateSerializer.serialize_state(state, true) # true = mask opponent hand
	return {"observation": obs, "legal_moves": _get_legal_moves_list()}

func _handle_legal_moves() -> Dictionary:
	return {"legal_moves": _get_legal_moves_list()}

func _get_legal_moves_list() -> Array:
	if turn_manager == null:
		return []
	var state = turn_manager.get_state()
	if state == null or state.is_game_over:
		return []
	
	var moves = RulesEngineModel.get_valid_moves(state, GameStateModel.PLAYER_AI)
	return moves

func _handle_step(action: Dictionary) -> Dictionary:
	if turn_manager == null:
		return {"observation": {}, "reward": 0.0, "done": true, "info": {}}
	
	var state = turn_manager.get_state()
	if state == null or state.is_game_over:
		return {"observation": StateSerializer.serialize_state(state, true), "reward": 0.0, "done": true, "info": {}}
	
	var row = int(action.get("row", -1))
	var col = int(action.get("col", -1))
	var stone_id = str(action.get("stone_id", ""))
	
	var before_score_ai = state.score_ai
	var before_score_human = state.score_human
	
	# Apply move
	var success = turn_manager.ai_play(row, col, stone_id)
	if not success:
		return {"observation": StateSerializer.serialize_state(state, true), "reward": -0.01, "done": false, "info": {"invalid_move": true}}
	
	# Wait for turn to advance (synchronously in headless)
	# In headless without UI, TurnManager processes immediately via awaits
	await get_tree().process_frame
	await get_tree().process_frame
	
	var after_state = turn_manager.get_state()
	var captures = max(0, after_state.score_ai - before_score_ai)
	
	var reward = RewardCalculator.calculate_reward(captures, after_state)
	var done = after_state.is_game_over
	var obs = StateSerializer.serialize_state(after_state, true)
	
	return {"observation": obs, "reward": reward, "done": done, "info": {"captures": captures}}

func _send_response(response: Dictionary) -> void:
	print(JSON.stringify(response))
