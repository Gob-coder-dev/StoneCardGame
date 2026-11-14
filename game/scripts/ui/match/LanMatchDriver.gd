## LanMatchDriver.gd
## Driver PVP local : relie le coordinateur réseau au TurnManager et applique
## les commandes validées par l'hôte avec le même moteur que la campagne.
##
## Aucune règle de combat n'est dupliquée : la validation passe par
## PlacementRules et par la phase réelle du TurnManager.
class_name LanMatchDriver
extends MatchDriver

const StateFingerprintModel := preload("res://scripts/engine/StateFingerprint.gd")
const CoordinatorModel := preload("res://scripts/network/LanMatchCoordinator.gd")
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")

var _coordinator: LanMatchCoordinator = null
var _link: LanSessionLink = null
var _last_sequence := 0
var _leaving := false
var _confirmation_timer: Timer = null


func start() -> bool:
	if not PvpMatchContext.is_active():
		return false
	local_side = PvpMatchContext.local_side
	records_campaign_stats = false
	local_name = PvpMatchContext.local_name
	opponent_name = PvpMatchContext.remote_name
	local_god = GodIdentityModel.player(PvpMatchContext.local_god_id)
	opponent_god = GodIdentityModel.player(PvpMatchContext.remote_god_id)

	var one := PvpMatchContext.participant_for_side(GameState.PLAYER_ONE)
	var two := PvpMatchContext.participant_for_side(GameState.PLAYER_TWO)
	if one.is_empty() or two.is_empty():
		return false
	if not DeckRules.is_deck_valid(one.get("deck", []), str(one.get("god_id", ""))) \
			or not DeckRules.is_deck_valid(two.get("deck", []), str(two.get("god_id", ""))):
		return false

	_link = LanSessionLink.new()
	_link.attach(LanSession)
	var client_peer := 0
	if local_side == GameState.PLAYER_ONE:
		client_peer = PvpMatchContext.peer_of_side(GameState.PLAYER_TWO)
	_coordinator = CoordinatorModel.new()
	_coordinator.attach(_link, PvpMatchContext.match_id,
		local_side == GameState.PLAYER_ONE, local_side, client_peer)
	_coordinator.set_move_validator(_validate_move)
	_coordinator.command_accepted.connect(_on_command_accepted)
	_coordinator.desync.connect(_on_desync)
	_coordinator.aborted.connect(_on_aborted)
	_coordinator.match_finished.connect(_on_match_finished)
	_coordinator.ready_changed.connect(_on_ready_changed)
	_confirmation_timer = Timer.new()
	_confirmation_timer.name = "TurnConfirmationTimeout"
	_confirmation_timer.one_shot = true
	_confirmation_timer.timeout.connect(_on_confirmation_timeout)
	add_child(_confirmation_timer)

	LanSession.enter_match()
	turn_manager.start_game(
		StoneLoader.build_hand(one.get("deck", [])),
		StoneLoader.build_hand(two.get("deck", [])),
		PvpMatchContext.blocked_cells,
		"",
		PvpMatchContext.starting_player,
		str(one.get("god_id", "")),
		str(two.get("god_id", "")),
		PvpMatchContext.seed
	)
	_coordinator.begin(PvpMatchContext.starting_player)
	return true


## Validation autoritaire, exécutée sur le moteur local : joueur actif, phase,
## coordonnées, présence de la carte et PlacementRules.
func _validate_move(player: int, row: int, col: int, stone_id: String) -> bool:
	var state := turn_manager.get_state()
	if state == null or state.is_game_over:
		return false
	if turn_manager.phase != TurnManager.Phase.WAITING_INPUT:
		return false
	if state.current_player != player:
		return false
	return PlacementRules.is_valid(state, row, col, stone_id, player)


func can_submit() -> bool:
	if _coordinator == null or not _coordinator.can_submit():
		return false
	var state := turn_manager.get_state()
	return state != null and not state.is_game_over \
		and state.current_player == local_side \
		and turn_manager.phase == TurnManager.Phase.WAITING_INPUT


func request_move(row: int, col: int, stone_id: String) -> bool:
	if _coordinator == null or not can_submit() \
			or not _validate_move(local_side, row, col, stone_id):
		return false
	return _coordinator.request_move(row, col, stone_id)


func on_turn_started(_player: int) -> void:
	pass


func on_turn_ended() -> void:
	if _coordinator == null:
		return
	var state := turn_manager.get_state()
	if state == null:
		return
	_coordinator.report_local_state(StateFingerprintModel.of(state), _last_sequence)


func on_game_over(winner: int, score_one: int, score_two: int) -> void:
	# Seul l'hôte diffuse le résultat ; le client attend MATCH_END.
	if _coordinator != null:
		_coordinator.finish_match(winner, score_one, score_two)


func shutdown() -> void:
	if _confirmation_timer != null:
		_confirmation_timer.stop()
	if _coordinator != null:
		_coordinator.close()
	if _link != null:
		_link.detach()


## ─── Réactions au coordinateur ──────────────────────────────────────────────

## L'hôte confirme le tour après avoir comparé les deux états : c'est le seul
## moment où le joueur suivant peut toucher le plateau.
func _on_ready_changed(_can_submit: bool) -> void:
	if _confirmation_timer != null:
		if _can_submit:
			_confirmation_timer.stop()
		elif not _leaving:
			# Couvre aussi l'intention envoyée avant toute acceptation de l'hôte.
			_confirmation_timer.start(LanProtocol.TURN_CONFIRM_TIMEOUT_SECONDS)
	interaction_changed.emit()

func _on_command_accepted(command: Dictionary) -> void:
	if _leaving:
		return
	var sequence := int(command.get("sequence", 0))
	if sequence <= _last_sequence:
		return
	if _confirmation_timer != null:
		_confirmation_timer.start(LanProtocol.TURN_CONFIRM_TIMEOUT_SECONDS)
	if not turn_manager.play(int(command["player"]), int(command["row"]),
			int(command["col"]), str(command["stone_id"])):
		_leaving = true
		aborted.emit("Désynchronisation : le moteur local a refusé un coup validé.")
		return
	_last_sequence = sequence


func _on_confirmation_timeout() -> void:
	if _leaving or _coordinator == null:
		return
	_coordinator.abort("L'adversaire ne confirme plus les tours. La partie est arrêtée.")


func _on_desync(message: String) -> void:
	if _leaving:
		return
	_leaving = true
	aborted.emit(message)


func _on_aborted(message: String) -> void:
	if _leaving:
		return
	_leaving = true
	aborted.emit(message)


func _on_match_finished(winner: int, score_one: int, score_two: int) -> void:
	if _leaving:
		return
	_leaving = true
	finished.emit(winner, score_one, score_two)
