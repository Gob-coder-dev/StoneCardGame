## PvpResultController.gd
## Résultat d'une partie ou d'une manche PVP. La préparation n'est jamais
## affichée ici : une manche suivante ouvre `PvpPreparation.tscn`.
##
## Trois sorties distinctes :
##   - action principale : revanche, partie suivante ou nouvelle série ;
##   - retour au salon : conserve la connexion ENet et reconstruit le salon ;
##   - quitter : ferme réellement la session et revient au choix PVP.
extends Control

const SessionLink := preload("res://scripts/network/LanSessionLink.gd")
const CoordinatorModel := preload("res://scripts/network/LanMatchCoordinator.gd")
const PresenceModel := preload("res://scripts/network/LanPvpPresence.gd")
const RulesModel := preload("res://scripts/domain/MatchRules.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")
const Presenter := preload("res://scripts/ui/pvp/PvpResultPresenter.gd")

@onready var result_label: Label = $VBoxCenter/ResultLabel
@onready var detail_label: Label = $VBoxCenter/DetailLabel
@onready var score_label: Label = $VBoxCenter/ScoreLabel
@onready var series_card = $VBoxCenter/SeriesResultCard
@onready var status_label: Label = $VBoxCenter/StatusLabel
@onready var primary_button: Button = $VBoxCenter/PrimaryActionButton
@onready var return_button: Button = $VBoxCenter/ReturnLobbyButton
@onready var quit_button: Button = $VBoxCenter/QuitButton
@onready var background: MenuBackground = $Background

## Point d'injection réservé aux tests : le jeu réel utilise toujours GameRoutes.
var scene_changer: Callable = Callable()
var _link: LanSessionLink = null
var _coordinator: LanMatchCoordinator = null
var _series_flow: LanSeriesCoordinator = null
var _presence: LanPvpPresence = null
var _return_available := false
var _remote_in_lobby := false
var _series_recorded := false
var _leaving := false
var _pending_action := false
var _primary_mode := "classic_rematch"
var _action_timeout: Timer = null
## `_apply_presentation` est appelé plusieurs fois pour le même verdict.
var _result_sound_key := ""


func _ready() -> void:
	primary_button.pressed.connect(_press_primary)
	return_button.pressed.connect(_press_return_lobby)
	quit_button.pressed.connect(_quit)
	LanSession.state_changed.connect(_on_session_state)
	_show_result()
	if not _start_series_result():
		_start_classic_rematch()
	_setup_presence()
	_action_timeout = _make_timer("SeriesActionTimeout", 30.0, _on_action_timeout)


func _make_timer(timer_name: String, seconds: float, callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.name = timer_name
	timer.one_shot = true
	timer.wait_time = seconds
	timer.timeout.connect(callback)
	add_child(timer)
	return timer


## ─── Verdict et score ───────────────────────────────────────────────────────

func _show_result() -> void:
	if PvpMatchContext.is_simple_result():
		_show_simple_result()
	else:
		_show_series_result()


## FT1 et partie Classique directe gardent l'apparence historique : verdict,
## score réel du plateau, aucun vocabulaire de série ni numéro de manche.
func _show_simple_result() -> void:
	_apply_presentation(Presenter.simple(PvpMatchContext.last_result,
		PvpMatchContext.local_side, _local_name(), _remote_name(), _series_flow != null))


func _show_series_result() -> void:
	_apply_presentation(Presenter.series(PvpMatchContext.series_public,
		PvpMatchContext.last_result, PvpMatchContext.local_side,
		_local_name(), _remote_name()))


func _apply_presentation(view: Dictionary) -> void:
	result_label.text = str(view["title"])
	detail_label.text = str(view["detail"])
	score_label.text = str(view["score"])
	status_label.text = str(view["status"])
	if view.has("series_view"):
		series_card.show_view(view["series_view"])
	else:
		series_card.hide_view()
	_primary_mode = str(view["primary_mode"])
	primary_button.text = str(view["primary_text"])
	return_button.text = "RETOUR AU SALON"
	quit_button.text = "QUITTER"
	_apply_result_background(int(view["winner"]), bool(view["local_one"]))
	_play_result_sound(view)
	_set_actions_enabled(true)


## Le présentateur renvoie le vainqueur de la série quand elle est finie, sinon
## celui de la manche. Le son suit exactement cette distinction.
func _play_result_sound(view: Dictionary) -> void:
	var winner := int(view.get("winner", GameState.PLAYER_NONE))
	var finished := PvpMatchContext.is_simple_result() or PvpMatchContext.series_finished()
	var key := "%d:%s" % [winner, "final" if finished else "round"]
	if key == _result_sound_key:
		return
	_result_sound_key = key
	if winner == PvpMatchContext.local_side:
		Audio.play_jingle(AudioCatalog.SFX_VICTORY if finished
			else AudioCatalog.SFX_ROUND_WON)
	elif winner != GameState.PLAYER_NONE:
		Audio.play_jingle(AudioCatalog.SFX_DEFEAT if finished
			else AudioCatalog.SFX_ROUND_DEFEAT)
	else:
		Audio.play_jingle(AudioCatalog.SFX_DRAW)


func _apply_result_background(winner: int, local_one: bool) -> void:
	var winning_god_id := ""
	if winner == GameState.PLAYER_ONE:
		winning_god_id = PvpMatchContext.local_god_id if local_one else PvpMatchContext.remote_god_id
	elif winner == GameState.PLAYER_TWO:
		winning_god_id = PvpMatchContext.remote_god_id if local_one else PvpMatchContext.local_god_id
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


## ─── Série ──────────────────────────────────────────────────────────────────

func _start_series_result() -> bool:
	if not PvpMatchContext.has_series():
		return false
	_series_flow = PvpMatchContext.series_flow as LanSeriesCoordinator
	if _series_flow == null:
		return false
	_connect_series()
	_show_result()
	if PvpMatchContext.series_finished():
		if not PvpMatchContext.is_simple_result():
			status_label.text = "La série est terminée. Choisissez une nouvelle série ou revenez au salon."
		return true
	if _series_flow.is_host():
		call_deferred("_host_record_series_round")
	else:
		status_label.text = "Résultat de la manche en attente de l'hôte…"
	return true


func _host_record_series_round() -> void:
	if _series_recorded or _leaving or _series_flow == null or not _series_flow.is_host():
		return
	_series_recorded = true
	var result: Dictionary = PvpMatchContext.last_result
	if not _series_flow.host_record_round(
			int(result.get("winner", GameState.PLAYER_NONE)),
			int(result.get("score_one", 0)), int(result.get("score_two", 0))):
		status_label.text = "Le résultat de la manche n'a pas pu être enregistré."


func _connect_series() -> void:
	_series_flow.state_changed.connect(_on_series_state)
	_series_flow.preparation_started.connect(_on_series_preparation)
	_series_flow.draft_updated.connect(_on_series_preparation)
	_series_flow.loadout_revealed.connect(_on_series_preparation)
	_series_flow.round_ready.connect(_on_series_round_ready)
	_series_flow.series_finished.connect(_on_series_finished)
	_series_flow.failed.connect(_on_aborted)


func _on_series_state(state: Dictionary) -> void:
	if _leaving:
		return
	PvpMatchContext.set_series(state)
	_show_result()
	if _pending_action and str(state.get("phase", "")) == RulesModel.PHASE_ROUND_RESULT:
		status_label.text = "Résultat enregistré. En attente de la manche suivante…"


func _on_series_preparation(state: Dictionary) -> void:
	if _leaving:
		return
	PvpMatchContext.set_series(state)
	_open_preparation()


func _on_series_round_ready(config: Dictionary) -> void:
	if _leaving:
		return
	_leaving = true
	_stop_timers()
	PvpMatchContext.set_presence(LanPvpPresence.PRE_BATTLE)
	PvpMatchContext.begin(config, PvpMatchContext.local_side, LanSession.local_peer_id(),
		PvpMatchContext.lobby_local_profile(), PvpMatchContext.lobby_remote_profile(), true,
		_series_flow.rules() if _series_flow != null else PvpMatchContext.match_rules)
	_close_return()
	_detach_match()
	Routes.go_with_override(get_tree(), scene_changer, Routes.PRE_BATTLE)


func _on_series_finished(state: Dictionary) -> void:
	if _leaving:
		return
	PvpMatchContext.set_series(state)
	_show_result()


func _open_preparation() -> void:
	if _leaving:
		return
	_leaving = true
	_stop_timers()
	PvpMatchContext.set_presence(LanPvpPresence.PREPARATION)
	_close_return()
	_detach_match()
	Routes.go_with_override(get_tree(), scene_changer, Routes.PVP_PREPARATION)


## ─── Action principale ──────────────────────────────────────────────────────

func _press_primary() -> void:
	if _leaving or _pending_action:
		return
	match _primary_mode:
		"next":
			if _series_flow == null or not _series_flow.request_next_round():
				status_label.text = "La manche suivante n'est pas disponible."
				return
			if _leaving:
				return
			_begin_pending("En attente de l'adversaire pour la partie suivante…")
		"series_rematch":
			if _series_flow == null or not _series_flow.request_rematch():
				status_label.text = "La nouvelle série n'est pas disponible."
				return
			if _leaving:
				return
			_begin_pending("En attente de l'adversaire pour une nouvelle série…")
		_:
			if _coordinator == null or not _coordinator.request_start():
				status_label.text = "La revanche n'est pas disponible."
				return
			if _leaving:
				return
			_begin_pending("En attente de l'adversaire pour la revanche…")


func _begin_pending(message: String) -> void:
	_pending_action = true
	primary_button.disabled = true
	status_label.text = message
	if _action_timeout != null:
		_action_timeout.start()


func _on_action_timeout() -> void:
	if _leaving or not _pending_action:
		return
	_pending_action = false
	primary_button.disabled = false
	status_label.text = "L'adversaire n'a pas confirmé. Vous pouvez réessayer ou revenir au salon."


## ─── Revanche Classique directe ─────────────────────────────────────────────

func _start_classic_rematch() -> void:
	if not PvpMatchContext.is_active() or not LanSession.is_online():
		primary_button.disabled = true
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


func _on_start_pending() -> void:
	if _leaving or _pending_action:
		return
	status_label.text = "L'adversaire veut une revanche. Touchez REVANCHE."
	primary_button.disabled = false
	primary_button.grab_focus()


func _on_match_ready(config: Dictionary) -> void:
	if _leaving:
		return
	_leaving = true
	_stop_timers()
	PvpMatchContext.set_presence(LanPvpPresence.PRE_BATTLE)
	PvpMatchContext.begin(config, PvpMatchContext.local_side, LanSession.local_peer_id(),
		PvpMatchContext.lobby_local_profile(), PvpMatchContext.lobby_remote_profile(), false,
		PvpMatchContext.match_rules)
	_detach_match()
	Routes.go_with_override(get_tree(), scene_changer, Routes.PRE_BATTLE)


## ─── Retour individuel au salon ─────────────────────────────────────────────

## Le retour n'est plus une poignée de main : chaque camp annonce seulement sa
## présence. Personne ne reçoit d'ordre de navigation.
func _setup_presence() -> void:
	var link: LanSessionLink = null
	if _series_flow != null:
		link = PvpMatchContext.series_link as LanSessionLink
	else:
		link = _link
	if link == null or not link.is_attached():
		_presence = PvpMatchContext.presence as LanPvpPresence
		if _presence == null or not _presence.is_attached():
			return_button.disabled = true
			return
	else:
		_presence = PvpMatchContext.ensure_presence(link, _return_remote_peer()) as LanPvpPresence
	if _presence == null:
		return_button.disabled = true
		return
	if not _presence.remote_changed.is_connected(_on_remote_presence):
		_presence.remote_changed.connect(_on_remote_presence)
	_presence.set_local(PresenceModel.RESULT)
	_remote_in_lobby = _presence.remote_presence() == PresenceModel.LOBBY
	_return_available = true
	return_button.disabled = false
	if _remote_in_lobby:
		_on_remote_presence(PresenceModel.LOBBY)


func _return_remote_peer() -> int:
	return PvpMatchContext.peer_of_side(PvpMatchContext.remote_side())


func _on_remote_presence(presence: String) -> void:
	if _leaving:
		return
	_remote_in_lobby = presence == PresenceModel.LOBBY
	if _remote_in_lobby:
		_pending_action = false
		primary_button.disabled = true
		status_label.text = "L'adversaire est retourné au salon. Revenez au salon pour rejouer."
	else:
		_set_actions_enabled(true)


func _press_return_lobby() -> void:
	if _leaving:
		return
	if not _return_available:
		status_label.text = "Le retour au salon n'est pas disponible."
		return
	_finish_return_to_lobby()


func _finish_return_to_lobby() -> void:
	if _leaving:
		return
	_leaving = true
	_stop_timers()
	var kept_link: LanSessionLink = null
	if _series_flow != null:
		kept_link = PvpMatchContext.series_link as LanSessionLink
	else:
		kept_link = _link
	var is_host := PvpMatchContext.local_side == GameState.PLAYER_ONE
	var client_peer := PvpMatchContext.peer_of_side(GameState.PLAYER_TWO) if is_host else 0
	# Le dieu et le deck de la manche peuvent être générés. La reprise du salon
	# doit réutiliser exclusivement les profils capturés avant la série.
	var local_profile := PvpMatchContext.lobby_local_profile()
	var remote_profile := PvpMatchContext.lobby_remote_profile()
	var rules := _series_flow.rules() if _series_flow != null \
		else (PvpMatchContext.match_rules.duplicate(true) if not PvpMatchContext.match_rules.is_empty() \
			else RulesModel.default_config())
	if _presence != null:
		_presence.set_local(PresenceModel.LOBBY)
	_close_return()
	_detach_match()
	if _series_flow != null:
		_series_flow.close()
		_series_flow = null
		PvpMatchContext.release_series()
	elif _link != null:
		# Le lien est déjà conservé dans kept_link : ne pas le détacher.
		_link = null
	PvpMatchContext.clear()
	PvpMatchContext.set_lobby_resume({
		"link": kept_link,
		"is_host": is_host,
		"client_peer": client_peer,
		"local": local_profile,
		"remote": remote_profile,
		"rules": rules,
	})
	LanSession.enter_lobby()
	Routes.go_with_override(get_tree(), scene_changer, Routes.PVP_LOBBY)


func _on_session_state(session_state: int) -> void:
	if _leaving or session_state != LanSession.State.DISCONNECTED:
		return
	_pending_action = false
	_stop_timers()
	primary_button.disabled = true
	return_button.disabled = true
	status_label.text = "La connexion avec l'adversaire est perdue."


## ─── Quitter ────────────────────────────────────────────────────────────────

func _quit() -> void:
	if _leaving:
		return
	_leaving = true
	_stop_timers()
	_close_return()
	_detach_match()
	_close_series()
	PvpMatchContext.close_presence()
	if _link != null:
		_link.detach()
		_link = null
	PvpMatchContext.clear()
	LanSession.leave_with_notice("Partie PVP quittée. Créez ou rejoignez un salon.")
	Routes.go_with_override(get_tree(), scene_changer, Routes.PVP_LOBBY)


func _close_series() -> void:
	if _series_flow != null:
		_series_flow.close()
		_series_flow = null
	var released := PvpMatchContext.release_series()
	if released.get("link") is LanSessionLink:
		(released["link"] as LanSessionLink).detach()


## ─── Nettoyage ──────────────────────────────────────────────────────────────

func _on_aborted(message: String) -> void:
	if _leaving:
		return
	status_label.text = message
	_pending_action = false
	primary_button.disabled = true


func _set_actions_enabled(enabled: bool) -> void:
	primary_button.disabled = not enabled or _remote_in_lobby
	return_button.disabled = not enabled or not _return_available
	quit_button.disabled = false


func _stop_timers() -> void:
	if _action_timeout != null:
		_action_timeout.stop()


## Les signaux de la présence sont retirés à la sortie, mais la présence elle-
## même survit : elle doit continuer à annoncer LOBBY après la navigation.
func _close_return() -> void:
	if _presence != null and _presence.remote_changed.is_connected(_on_remote_presence):
		_presence.remote_changed.disconnect(_on_remote_presence)
	_presence = null
	_return_available = false


func _detach_match() -> void:
	if _coordinator != null:
		_coordinator.close()
		_coordinator = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_quit()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_quit()


func _exit_tree() -> void:
	_stop_timers()
	_close_return()
	_detach_match()
	if LanSession.state_changed.is_connected(_on_session_state):
		LanSession.state_changed.disconnect(_on_session_state)
	if not _leaving:
		if _series_flow != null:
			_series_flow.close()
			_series_flow = null
			PvpMatchContext.release_series()
		if _link != null:
			_link.detach()
			_link = null
		PvpMatchContext.close_presence()
		if PvpMatchContext.is_active() or not PvpMatchContext.series_public.is_empty():
			PvpMatchContext.clear()
			LanSession.reset()
