## Serveur JSON-lines local. Le TCP separe le protocole des logs Godot.
extends Node

const SimulatorModel := preload("res://tools/rl_sim/MatchSimulator.gd")
const Serializer := preload("res://tools/rl_sim/StateSerializer.gd")
const DeckApi := preload("res://tools/rl_sim/DeckApi.gd")

var _server := TCPServer.new()
var _peer: StreamPeerTCP = null
var _buffer := ""
var _simulator := SimulatorModel.new()
var _simulators: Dictionary = {}


func _ready() -> void:
	var port := _argument_value("--rl-port")
	if port <= 0:
		push_error("HeadlessRunner: --rl-port PORT est obligatoire")
		get_tree().quit(2)
		return
	var error := _server.listen(port, "127.0.0.1")
	if error != OK:
		push_error("HeadlessRunner: impossible d'ecouter le port %d" % port)
		get_tree().quit(3)


func _process(_delta: float) -> void:
	if _peer == null and _server.is_connection_available():
		_peer = _server.take_connection()
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_peer = null
		_buffer = ""
		return
	var available := _peer.get_available_bytes()
	if available <= 0:
		return
	_buffer += _peer.get_utf8_string(available)
	while _buffer.contains("\n"):
		var boundary := _buffer.find("\n")
		var line := _buffer.substr(0, boundary).strip_edges()
		_buffer = _buffer.substr(boundary + 1)
		if line != "":
			_handle(line)


func _handle(line: String) -> void:
	var request = JSON.parse_string(line)
	if not request is Dictionary:
		_send({"ok": false, "id": 0, "error": "invalid_json"})
		return
	var request_id := int(request.get("id", 0))
	var command := str(request.get("cmd", ""))
	match command:
		"ping":
			_send_ok(request_id, {"pong": true})
		"reset":
			var reset_result := _simulator.reset(request.get("config", {}))
			if not bool(reset_result.get("success", false)):
				_send_error(request_id, str(reset_result.get("error", "reset impossible")))
			else:
				_send_ok(request_id, _snapshot(int(request.get("observer", GameState.PLAYER_HUMAN)), reset_result))
		"legal_actions":
			_send_ok(request_id, {"legal_actions": _simulator.legal_actions()})
		"get_state":
			_send_ok(request_id, _snapshot(int(request.get("observer", GameState.PLAYER_HUMAN))))
		"step":
			var step_result := _simulator.step(request.get("action", {}))
			if not bool(step_result.get("success", false)):
				_send_error(request_id, str(step_result.get("error", "action refusee")))
			else:
				_send_ok(request_id, _snapshot(int(request.get("observer", GameState.PLAYER_HUMAN)), step_result))
		"choose_profile_action":
			var choice := _simulator.choose_profile_action(request.get("profile", {}))
			if bool(choice.get("success", false)):
				_send_ok(request_id, {"action": choice["action"]})
			else:
				_send_error(request_id, str(choice.get("error", "choix impossible")))
		"tactical_action_scores":
			_send_ok(request_id, {"scores": _simulator.tactical_action_scores(
				int(request.get("observer", GameState.PLAYER_HUMAN)))})
		"get_deck_catalog":
			_send_ok(request_id, DeckApi.catalog())
		"validate_deck":
			_send_ok(request_id, DeckApi.validate_deck(
				request.get("stone_ids", []), str(request.get("god_id", ""))))
		"validate_decks":
			_send_ok(request_id, {"results": DeckApi.validate_decks(request.get("decks", []))})
		"get_engine_manifest":
			_send_ok(request_id, DeckApi.engine_manifest())
		"batch_reset":
			_send_ok(request_id, {"results": _batch_reset(request.get("matches", []))})
		"batch_step":
			_send_ok(request_id, {"results": _batch_step(request.get("matches", []))})
		"batch_get_state":
			_send_ok(request_id, {"results": _batch_get_state(request.get("matches", []))})
		"batch_choose_profile_action":
			_send_ok(request_id, {"results": _batch_choose_profile(request.get("matches", []))})
		"release_matches":
			for match_id in request.get("match_ids", []):
				_simulators.erase(str(match_id))
			_send_ok(request_id, {"remaining": _simulators.size()})
		"shutdown":
			_send_ok(request_id, {"shutdown": true})
			get_tree().quit()
		_:
			_send_error(request_id, "unknown_command")


func _snapshot(observer: int, extra: Dictionary = {}) -> Dictionary:
	return _snapshot_for(_simulator, observer, extra)


func _snapshot_for(simulator, observer: int, extra: Dictionary = {}) -> Dictionary:
	var result := extra.duplicate(true)
	result["observation"] = Serializer.serialize_for_player(simulator.state, observer)
	result["legal_actions"] = simulator.legal_actions()
	return result


func _batch_reset(matches: Array) -> Array:
	var results: Array = []
	for request in matches:
		if not request is Dictionary:
			results.append({"ok": false, "match_id": "", "error": "requete invalide"})
			continue
		var match_id := str(request.get("match_id", ""))
		if match_id == "":
			results.append({"ok": false, "match_id": "", "error": "match_id obligatoire"})
			continue
		var simulator := SimulatorModel.new()
		var reset_result := simulator.reset(request.get("config", {}))
		if not bool(reset_result.get("success", false)):
			results.append({"ok": false, "match_id": match_id,
				"error": str(reset_result.get("error", "reset impossible"))})
			continue
		_simulators[match_id] = simulator
		results.append({"ok": true, "match_id": match_id,
			"result": _snapshot_for(simulator, int(request.get("observer", GameState.PLAYER_HUMAN)), reset_result)})
	return results


func _batch_step(matches: Array) -> Array:
	var results: Array = []
	for request in matches:
		var match_id := str(request.get("match_id", "")) if request is Dictionary else ""
		var simulator = _simulators.get(match_id)
		if simulator == null:
			results.append({"ok": false, "match_id": match_id, "error": "match inconnu"})
			continue
		var step_result: Dictionary = simulator.step(request.get("action", {}))
		if not bool(step_result.get("success", false)):
			results.append({"ok": false, "match_id": match_id,
				"error": str(step_result.get("error", "action refusee"))})
			continue
		results.append({"ok": true, "match_id": match_id,
			"result": _snapshot_for(simulator, int(request.get("observer", GameState.PLAYER_HUMAN)), step_result)})
	return results


func _batch_get_state(matches: Array) -> Array:
	var results: Array = []
	for request in matches:
		var match_id := str(request.get("match_id", "")) if request is Dictionary else ""
		var simulator = _simulators.get(match_id)
		if simulator == null:
			results.append({"ok": false, "match_id": match_id, "error": "match inconnu"})
			continue
		results.append({"ok": true, "match_id": match_id,
			"result": _snapshot_for(simulator, int(request.get("observer", GameState.PLAYER_HUMAN)))})
	return results


func _batch_choose_profile(matches: Array) -> Array:
	var results: Array = []
	for request in matches:
		var match_id := str(request.get("match_id", "")) if request is Dictionary else ""
		var simulator = _simulators.get(match_id)
		if simulator == null:
			results.append({"ok": false, "match_id": match_id, "error": "match inconnu"})
			continue
		var choice: Dictionary = simulator.choose_profile_action(request.get("profile", {}))
		if bool(choice.get("success", false)):
			results.append({"ok": true, "match_id": match_id, "result": {"action": choice["action"]}})
		else:
			results.append({"ok": false, "match_id": match_id,
				"error": str(choice.get("error", "choix impossible"))})
	return results


func _send_ok(request_id: int, result: Dictionary) -> void:
	_send({"ok": true, "id": request_id, "result": result})


func _send_error(request_id: int, message: String) -> void:
	_send({"ok": false, "id": request_id, "error": message})


func _send(response: Dictionary) -> void:
	if _peer != null:
		_peer.put_data((JSON.stringify(response) + "\n").to_utf8_buffer())


func _argument_value(name: String) -> int:
	var args := OS.get_cmdline_user_args()
	var index := args.find(name)
	return int(args[index + 1]) if index >= 0 and index + 1 < args.size() else -1
