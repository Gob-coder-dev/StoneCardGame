## PvpResultController.gd
## Écran de fin de match PVP local : verdict, score des deux appareils, puis
## revanche négociée avec le même adversaire, ou sortie vers le salon.
##
## La session réseau reste ouverte pendant cet écran : c'est elle qui permet
## aux deux téléphones de relancer une partie sans repasser par la découverte.
## L'hôte reste seul à tirer la configuration de la revanche.
extends Control

const SessionLink := preload("res://scripts/network/LanSessionLink.gd")
const CoordinatorModel := preload("res://scripts/network/LanMatchCoordinator.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")

@onready var result_label: Label = $VBoxCenter/ResultLabel
@onready var detail_label: Label = $VBoxCenter/DetailLabel
@onready var score_label: Label = $VBoxCenter/ScoreLabel
@onready var status_label: Label = $VBoxCenter/StatusLabel
@onready var rematch_button: Button = $VBoxCenter/RematchButton
@onready var quit_button: Button = $VBoxCenter/QuitButton
@onready var background: MenuBackground = $Background

var _link: LanSessionLink = null
var _coordinator: LanMatchCoordinator = null
var _leaving := false
var _rematch_local := false
var _start_timeout: Timer = null


func _ready() -> void:
	rematch_button.pressed.connect(_press_rematch)
	quit_button.pressed.connect(_quit)
	_show_result()
	_start_rematch_link()
	_start_timeout = Timer.new()
	_start_timeout.name = "RematchAgreementTimeout"
	_start_timeout.one_shot = true
	_start_timeout.timeout.connect(_on_rematch_timeout)
	add_child(_start_timeout)


## Le score du joueur local reste toujours à gauche, comme sur le plateau, et
## le verdict parle au camp de cet appareil.
func _show_result() -> void:
	var result: Dictionary = PvpMatchContext.last_result
	var winner := int(result.get("winner", GameState.PLAYER_NONE))
	var score_one := int(result.get("score_one", 0))
	var score_two := int(result.get("score_two", 0))
	var local_one := PvpMatchContext.local_side == GameState.PLAYER_ONE
	var local_score := score_one if local_one else score_two
	var remote_score := score_two if local_one else score_one
	var verdict := "ÉGALITÉ"
	if winner == PvpMatchContext.local_side:
		verdict = "VICTOIRE !"
	elif winner != GameState.PLAYER_NONE:
		verdict = "DÉFAITE..."
	result_label.text = verdict
	detail_label.text = "PVP LOCAL • %s contre %s" % [_local_name(), _remote_name()]
	score_label.text = "%s %d  —  %d %s" % [
		_local_name(), local_score, remote_score, _remote_name()
	]
	var winning_god_id := ""
	if winner == GameState.PLAYER_ONE:
		winning_god_id = PvpMatchContext.local_god_id if local_one \
			else PvpMatchContext.remote_god_id
	elif winner == GameState.PLAYER_TWO:
		winning_god_id = PvpMatchContext.remote_god_id if local_one \
			else PvpMatchContext.local_god_id
	if winner == PvpMatchContext.local_side:
		background.set_result_victory(StoneLoader.get_god(winning_god_id))
	elif winner != GameState.PLAYER_NONE:
		background.set_result_defeat(StoneLoader.get_god(winning_god_id))
	else:
		background.set_result_draw(
			StoneLoader.get_god(PvpMatchContext.local_god_id),
			StoneLoader.get_god(PvpMatchContext.remote_god_id))


func _local_name() -> String:
	return PvpMatchContext.local_name if PvpMatchContext.local_name != "" else "Vous"


func _remote_name() -> String:
	return PvpMatchContext.remote_name if PvpMatchContext.remote_name != "" \
		else "L'adversaire"


## ─── Revanche ───────────────────────────────────────────────────────────────

func _start_rematch_link() -> void:
	if not PvpMatchContext.is_active() or not LanSession.is_online():
		rematch_button.disabled = true
		status_label.text = "Session fermée : revenez au salon pour rejouer."
		return
	var is_host := PvpMatchContext.local_side == GameState.PLAYER_ONE
	var client_peer := PvpMatchContext.peer_of_side(GameState.PLAYER_TWO) if is_host else 0
	_link = SessionLink.new()
	_link.attach(LanSession)
	_coordinator = CoordinatorModel.new()
	_coordinator.attach(_link, PvpMatchContext.match_id, is_host,
		PvpMatchContext.local_side, client_peer)
	_coordinator.set_start_builder(_build_rematch_config)
	_coordinator.enable_start()
	_coordinator.start_pending.connect(_on_start_pending)
	_coordinator.match_ready.connect(_on_match_ready)
	_coordinator.aborted.connect(_on_aborted)


## Nouvelle graine, nouveau terrain, nouveau premier joueur : la revanche n'est
## pas un rejeu du même match. Les deux camps gardent leur pseudo et leur deck.
func _build_rematch_config() -> Dictionary:
	return {
		"match_id": "%d-%d" % [Time.get_ticks_usec(), LanProtocol.SERVER_ID],
		"seed": randi(),
		"blocked_cells": BoardSetupGenerator.generate(),
		"starting_player": BoardSetupGenerator.draw_first_player(),
		"participants": [
			PvpMatchContext.participant_for_side(GameState.PLAYER_ONE),
			PvpMatchContext.participant_for_side(GameState.PLAYER_TWO),
		],
	}


func _press_rematch() -> void:
	if _coordinator == null or _leaving:
		return
	if not _coordinator.request_start():
		status_label.text = "La revanche n'est pas disponible."
		rematch_button.disabled = true
		return
	_rematch_local = true
	rematch_button.disabled = true
	status_label.text = "En attente de l'adversaire…"
	if _start_timeout != null:
		_start_timeout.start(LanProtocol.START_AGREEMENT_TIMEOUT_SECONDS)


## L'adversaire a demandé la revanche : il suffit de la demander à son tour.
func _on_start_pending() -> void:
	if _leaving:
		return
	if not _rematch_local:
		status_label.text = "L'adversaire veut une revanche. Touchez REVANCHE."
		rematch_button.disabled = false
		rematch_button.grab_focus()


func _on_match_ready(config: Dictionary) -> void:
	if _leaving:
		return
	_leaving = true
	if _start_timeout != null:
		_start_timeout.stop()
	## Les profils sont lus avant `begin`, qui remet le contexte à zéro.
	var local_profile := PvpMatchContext.local_profile()
	var remote_profile := PvpMatchContext.remote_profile()
	PvpMatchContext.begin(config, PvpMatchContext.local_side, LanSession.local_peer_id(),
		local_profile, remote_profile)
	_detach()
	Routes.go(get_tree(), Routes.PRE_BATTLE)


func _on_aborted(message: String) -> void:
	if _leaving:
		return
	status_label.text = message
	rematch_button.disabled = true
	if _start_timeout != null:
		_start_timeout.stop()


func _on_rematch_timeout() -> void:
	if _leaving or _coordinator == null:
		return
	_coordinator.abort("L'adversaire n'a pas confirmé la revanche.")


## ─── Sortie ─────────────────────────────────────────────────────────────────

func _quit() -> void:
	if _leaving:
		return
	_leaving = true
	_detach()
	PvpMatchContext.clear()
	LanSession.leave_with_notice("Partie PVP quittée. Créez ou rejoignez un salon.")
	Routes.go(get_tree(), Routes.PVP_LOBBY)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_quit()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_quit()


func _exit_tree() -> void:
	_detach()
	if not _leaving and PvpMatchContext.is_active():
		## Scène libérée sans passer par un bouton : la session doit fermer.
		PvpMatchContext.clear()
		LanSession.reset()


func _detach() -> void:
	if _start_timeout != null:
		_start_timeout.stop()
	if _coordinator != null:
		_coordinator.close()
		_coordinator = null
	if _link != null:
		_link.detach()
		_link = null
