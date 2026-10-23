## Gère le joueur actif et l'ordre des phases. Les règles vivent dans CombatResolver.
## Les durées et les animations appartiennent exclusivement à la présentation.
class_name TurnManager
extends Node
const CombatResolverModel := preload("res://scripts/engine/CombatResolver.gd")

signal coin_flip_result(starting_player: int)
signal turn_started(player: int)
signal stone_placed(row: int, col: int, stone_id: String, owner: int)
signal stone_preparing(row: int, col: int, events: Array)
signal attacks_started(row: int, col: int, attacks: Array, owner: int)
signal stone_captured(row: int, col: int, new_owner: int)
signal effects_resolved(events: Array)
signal swarm_changed(events: Array)
signal presentation_requested(step: CombatPresentation)
signal turn_ended(score_human: int, score_ai: int)
signal game_over(winner: int, score_human: int, score_ai: int)
signal invalid_move(reason: String)

enum Phase { WAITING_INPUT, PLACING, PREPARING, SWARM, ATTACKING, EFFECTS, GAME_OVER }
var phase: Phase = Phase.WAITING_INPUT
var _pending_step: CombatPresentation
var _state: GameState

func start_game(human_hand: Array, ai_hand: Array, blocked_cells: Array, npc_id: String = "", forced_first_player: int = 0, human_god_id: String = "", ai_god_id: String = "") -> void:
	phase = Phase.WAITING_INPUT
	_state = GameState.new()
	if _pending_step != null:
		_pending_step.cancel()
		_pending_step = null
	_state.npc_id = npc_id
	_state.human_god_id = human_god_id
	_state.ai_god_id = ai_god_id
	_state.set_random_seed(randi())
	_state.apply_blocked_cells(blocked_cells)
	_state.setup_hands(human_hand, ai_hand)
	_coin_flip(forced_first_player)

func _coin_flip(forced_first_player: int = 0) -> void:
	if forced_first_player == GameState.PLAYER_HUMAN or forced_first_player == GameState.PLAYER_AI:
		_state.current_player = forced_first_player
	else:
		_state.current_player = GameState.PLAYER_HUMAN if randi() % 2 == 0 else GameState.PLAYER_AI
	emit_signal("coin_flip_result", _state.current_player)
	emit_signal("turn_started", _state.current_player)


## ─── Jouer un coup ────────────────────────────────────────────────────────────

func human_play(row: int, col: int, stone_id: String) -> bool:
	if _state == null or _state.is_game_over or phase != Phase.WAITING_INPUT:
		return false
	if _state.current_player != GameState.PLAYER_HUMAN:
		emit_signal("invalid_move", "Ce n'est pas ton tour.")
		return false
	return _apply_move(row, col, stone_id, GameState.PLAYER_HUMAN)

func ai_play(row: int, col: int, stone_id: String) -> bool:
	if _state == null or _state.is_game_over or phase != Phase.WAITING_INPUT:
		return false
	if _state.current_player != GameState.PLAYER_AI:
		return false
	return _apply_move(row, col, stone_id, GameState.PLAYER_AI)


## ─── Application d'un coup (orchestration courte) ────────────────────────────

func _apply_move(row: int, col: int, stone_id: String, player: int) -> bool:
	if not PlacementRules.is_valid(_state, row, col, stone_id, player):
		invalid_move.emit("Placement invalide.")
		return false
	phase = Phase.PLACING
	var placement := CombatResolverModel.place_stone(_state, row, col, stone_id, player)
	stone_placed.emit(row, col, stone_id, player)
	_resolve_placed_move(row, col, player, placement, _state)
	return true

func _resolve_placed_move(row: int, col: int, player: int, placement: Dictionary, move_state: GameState) -> void:
	var pose := CombatPresentation.new(CombatPresentation.Kind.PLACEMENT, row, col, player)
	pose.placement_swarm = placement["swarm_events"]
	await _present(pose)
	if _state != move_state:
		return
	var preparations: Array = placement["placement_effects"]
	if not preparations.is_empty():
		phase = Phase.PREPARING
		stone_preparing.emit(row, col, preparations)
		await _present(CombatPresentation.new(CombatPresentation.Kind.PREPARATION, row, col, player, preparations))
		if _state != move_state:
			return
	await _reveal_swarm(placement["swarm_events"], row, col, player)
	if _state != move_state:
		return
	var plan := CombatResolverModel.resolve_attacks(move_state, row, col, player, move_state.get_cell(row, col)["stone"])
	if not plan["attacks"].is_empty():
		phase = Phase.ATTACKING
		attacks_started.emit(row, col, plan["attacks"], player)
		await _present(CombatPresentation.new(CombatPresentation.Kind.ATTACK, row, col, player, plan["attacks"]))
		if _state != move_state:
			return
	var result := CombatResolverModel.finish_move(move_state, row, col, player, plan)
	for capture in result["captures"]:
		stone_captured.emit(capture["row"], capture["col"], player)
	phase = Phase.EFFECTS
	effects_resolved.emit(result["effects"])
	await _present(CombatPresentation.new(CombatPresentation.Kind.EFFECTS, row, col, player, result["effects"]))
	if _state != move_state:
		return
	await _reveal_swarm(result["swarm_events"], row, col, player)
	if _state == move_state:
		_advance_turn(player)

func _reveal_swarm(events: Array, row: int, col: int, player: int) -> void:
	if events.is_empty():
		return
	phase = Phase.SWARM
	swarm_changed.emit(events)
	await _present(CombatPresentation.new(CombatPresentation.Kind.SWARM, row, col, player, events))

func _present(step: CombatPresentation) -> void:
	if presentation_requested.get_connections().is_empty():
		# Un match sans interface n'a aucune animation à attendre.
		await get_tree().process_frame
		step.complete()
		return
	_pending_step = step
	presentation_requested.emit(step)
	if not step.completed:
		await step.finished
	if _pending_step == step:
		_pending_step = null

func _advance_turn(player: int) -> void:
	phase = Phase.WAITING_INPUT
	var score := RulesEngine.calculate_score(_state)
	_state.score_human = score["human"]
	_state.score_ai = score["ai"]
	emit_signal("turn_ended", _state.score_human, _state.score_ai)

	if RulesEngine.is_game_over(_state):
		phase = Phase.GAME_OVER
		_state.is_game_over = true
		_state.winner = RulesEngine.determine_winner(_state)
		emit_signal("game_over", _state.winner, _state.score_human, _state.score_ai)
		return

	_state.current_player = GameState.PLAYER_AI if player == GameState.PLAYER_HUMAN else GameState.PLAYER_HUMAN
	emit_signal("turn_started", _state.current_player)


## ─── Accès à l'état ───────────────────────────────────────────────────────────

func get_state() -> GameState:
	return _state

## Copie pour l'IA : la main du joueur humain y est masquée (voir GameState).

func get_state_for_ai() -> GameState:
	return _state.clone_for_ai()

func _exit_tree() -> void:
	_state = null
	if _pending_step != null:
		_pending_step.cancel()
		_pending_step = null
