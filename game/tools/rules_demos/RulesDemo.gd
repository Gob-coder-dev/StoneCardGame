## Joue et vérifie des scénarios avec le moteur et les animations de combat.
extends Control

const BoardModel := preload("res://scripts/engine/combat/CombatBoard.gd")
const WEAKNESS := preload("res://scripts/engine/effects/WeaknessSystem.gd")

@onready var _board_area: Control = $BoardArea
@onready var _turns: TurnManager = $Turns

var _board: BoardView
var _hits: Array = []
var _events: Array = []
var _card_art: Array[Texture2D] = []


func _ready() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_turns.monster_placed.connect(_on_placed)
	_turns.attacks_started.connect(_on_attacks)
	_turns.presentation_requested.connect(_present)
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var id := "horizon" if args.is_empty() else args[0]
	var shots = JSON.parse_string(FileAccess.get_file_as_string("res://tools/rules_demos/scenarios/%s.json" % id))
	if not shots is Array:
		_fail("Scénario illisible – %s" % id)
		return
	_preload_card_art(shots)
	for index in range(shots.size()):
		var poster := args[1] if index == 0 and args.size() > 1 else ""
		if not await _play_shot(shots[index], poster):
			_fail("Résultat inattendu – %s, plan %d." % [id, index + 1])
			return
	print("RULES_DEMO_OK ", id)
	Audio.quit_game(0)


func _preload_card_art(shots: Array) -> void:
	var ids := {}
	for shot in shots:
		for entry in shot.get("initial", []) + shot["moves"]:
			ids[entry[2]] = true
	for id in ids:
		var path := str(MonsterLoader.get_monster(id).get("asset", ""))
		if not path.is_empty():
			_card_art.append(load(path) as Texture2D)


func _play_shot(shot: Dictionary, poster: String) -> bool:
	var moves: Array = shot["moves"]
	var first_player := int(shot.get("first", GameState.PLAYER_ONE))
	var hands := [[], []]
	var player := first_player
	for move in moves:
		hands[player - 1].append(move[2])
		player = 3 - player
	var initial: Array[Dictionary] = []
	for entry in shot.get("initial", []):
		initial.append({"row": entry[0], "col": entry[1], "monster_id": entry[2], "owner": entry[3]})
	var gods: Array = shot.get("gods", ["", ""])
	_turns.start_game(hands[0], hands[1], shot.get("blocked", []), "", first_player,
		gods[0], gods[1], int(shot.get("seed", 7)), int(shot.get("size", 4)), initial)
	var state := _turns.get_state()
	CombatResolver.recalculate_swarm(state)
	WEAKNESS.update_miasma(state, -1, -1)
	_build_board(state.board_size, float(shot.get("focus", moves[0][0])), float(shot.get("zoom", 1.0)))
	_board.refresh(state)
	_board.animations.set_swarm_links(CombatResolver.swarm_links(state))
	for index in range(moves.size()):
		if not await _play_move(state, moves[index], poster if index == 0 else "",
				float(shot.get("lead_in", 1.4)) if index == 0 else 0.65):
			return false
	await get_tree().create_timer(1.85).timeout
	return true


func _play_move(state: GameState, move: Array, poster: String, lead_in: float) -> bool:
	var cell := Vector2i(int(move[0]), int(move[1]))
	_board.set_drop_target(cell)
	if not poster.is_empty():
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(poster) != OK:
			return false
	await get_tree().create_timer(lead_in).timeout
	_hits.clear()
	_events.clear()
	if not _turns.play(state.current_player, cell.x, cell.y, move[2]):
		return false
	await _turns.turn_ended
	# L’arbitre change de camp et termine la manche après l’émission du signal.
	await get_tree().process_frame
	var expected: Dictionary = move[3]
	if expected.has("hits") and not _matches_hits(expected["hits"]):
		print("Impacts obtenus ", _hits)
		return false
	for event in expected.get("events", []):
		if not _events.has(event):
			print("Effets obtenus ", _events)
			return false
	for entry in expected.get("owners", []):
		if state.get_cell(int(entry[0]), int(entry[1]))["owner"] != entry[2]:
			return false
	for entry in expected.get("miasma", []):
		var monster := BoardModel.monster_at(state.get_cell(int(entry[0]), int(entry[1])))
		if monster == null or monster.miasma_weakness != int(entry[2]):
			return false
	for entry in expected.get("shields", []):
		var monster := BoardModel.monster_at(state.get_cell(int(entry[0]), int(entry[1])))
		if monster == null or monster.shields.values().reduce(func(sum, value): return sum + value, 0) != int(entry[2]):
			return false
	return true


func _matches_hits(expected: Array) -> bool:
	if _hits.size() != expected.size():
		return false
	for index in range(expected.size()):
		var hit: Array = expected[index]
		if _hits[index] != [int(hit[0]), int(hit[1]), int(hit[2]), int(hit[3]), bool(hit[4])]:
			return false
	return true


func _build_board(board_size: int, focus: float, zoom: float) -> void:
	if _board != null:
		_board_area.remove_child(_board)
		_board.queue_free()
	_board = BoardView.new()
	_board.configure_board_size(board_size)
	var area := _board_area.size
	var side := minf(area.x, area.y) if focus < 0 else area.x * zoom
	_board.size = Vector2.ONE * side
	_board.position.x = (area.x - side) * 0.5
	_board_area.add_child(_board)
	_board.build()
	var slot := _board.slot_at(0, 0)
	var focus_y := (slot.size.y + BoardView.GAP) * focus + slot.size.y * 0.5
	_board.position.y = (area.y - side) * 0.5 if focus < 0 else area.y * 0.5 - focus_y
	_board.set_input_enabled(false)
	_board.get_node("SwarmLinks").z_index = _board.z_index


func _on_placed(_row: int, _col: int, _monster_id: String, _owner: int) -> void:
	_board.set_drop_target(Vector2i(-1, -1))
	_board.refresh(_turns.get_state())


func _on_attacks(_row: int, _col: int, attacks: Array, _owner: int) -> void:
	for attack in attacks:
		for hit in attack["hits"]:
			_hits.append([hit["row"], hit["col"], hit["attack"], hit["defense"], hit["success"]])


func _present(step: CombatPresentation) -> void:
	for event in step.events:
		if event.has("type"):
			var kind := str(event["type"])
			if kind == CombatEvents.COIN_FLIP:
				kind = "coin_swapped" if event["flipped"] else "coin_same"
			_events.append(kind)
	if step.kind == CombatPresentation.Kind.EFFECTS:
		_board.refresh(_turns.get_state())
	_board.animations.present(step)
	# Les effets couvrent le plateau et se dessinent après les cases dans la prise cadrée.
	for layer in _board.animations.get_children():
		if layer is Control:
			layer.size = _board.size
			layer.z_index = _board.z_index


func _fail(message: String) -> void:
	push_error(message)
	Audio.quit_game(1)
