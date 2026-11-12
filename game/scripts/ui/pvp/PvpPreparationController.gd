## Contrôleur de l'écran de préparation PVP : il projette l'état autoritaire
## de la série dans les vues et relaie uniquement les intentions du joueur.
extends Control

const RulesModel := preload("res://scripts/domain/MatchRules.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")

@onready var back_button: Button = $Root/Header/BackButton
@onready var title_label: Label = $Root/Header/Titles/Title
@onready var round_label: Label = $Root/Header/Titles/RoundLabel
@onready var series_label: Label = $Root/Header/SeriesLabel
@onready var scroll: ScrollContainer = $Root/Scroll
@onready var preparation_view = $Root/Scroll/PreparationView
@onready var opponent_ready_label: Label = $Root/Footer/OpponentReadyLabel
@onready var status_label: Label = $Root/Footer/StatusLabel
@onready var confirm_button: Button = $Root/Footer/ConfirmButton
@onready var background: MenuBackground = $Background

## Point d'injection réservé aux tests : le jeu réel utilise toujours GameRoutes.
var scene_changer: Callable = Callable()
var _flow: LanSeriesCoordinator = null
var _leaving := false
var _state: Dictionary = {}
var _observed_phase := ""
var _pending_choice_step := -1
var _pending_choice_id := ""


func _ready() -> void:
	Audio.set_button_sfx(confirm_button, AudioCatalog.SFX_BUTTON_2)
	if not PvpMatchContext.series_flow is LanSeriesCoordinator:
		_show_waiting("Préparation indisponible. Revenez au salon.")
		confirm_button.visible = false
		return
	_flow = PvpMatchContext.series_flow as LanSeriesCoordinator
	PvpMatchContext.set_presence(LanPvpPresence.PREPARATION)
	back_button.pressed.connect(_leave_session)
	confirm_button.pressed.connect(_on_confirm)
	preparation_view.card_chosen.connect(_on_card_chosen)
	preparation_view.bind_scroll(scroll)
	_flow.state_changed.connect(_on_state)
	_flow.preparation_started.connect(_on_state)
	_flow.draft_updated.connect(_on_state)
	_flow.loadout_revealed.connect(_on_state)
	_flow.round_ready.connect(_on_round_ready)
	_flow.series_finished.connect(_on_series_finished)
	_flow.failed.connect(_on_failed)
	LanSession.state_changed.connect(_on_session_state)
	_refresh(_flow.public_state())


func _process(delta: float) -> void:
	if _flow == null or _leaving:
		return
	if _flow.is_host():
		_flow.poll(delta)
	_update_timer()


func _on_state(state: Dictionary) -> void:
	if _leaving:
		return
	var draft: Dictionary = state.get("draft", {})
	if int(draft.get("own_step", -1)) != _pending_choice_step:
		_pending_choice_step = -1
		_pending_choice_id = ""
	PvpMatchContext.set_series(state)
	_refresh(state)


func _refresh(state: Dictionary) -> void:
	if _flow == null:
		return
	_state = state
	var series: Dictionary = state.get("series", {})
	var mode := str(series.get("mode", _flow.rules().get("mode", RulesModel.MODE_CLASSIC)))
	var format := str(series.get("series", _flow.rules().get("series", RulesModel.SERIES_FT1)))
	title_label.text = "PRÉPARATION • %s" % RulesModel.mode_label(mode).to_upper()
	if format == RulesModel.SERIES_FT1:
		round_label.text = "Partie simple"
		series_label.text = ""
		series_label.visible = false
	else:
		round_label.text = "MANCHE %d" % int(state.get("round_index", 1))
		series_label.text = "%s • %d — %d" % [
			format.to_upper(), int(series.get("wins_one", 0)), int(series.get("wins_two", 0))
		]
		series_label.visible = true
	var draft: Dictionary = state.get("draft", {})
	var loadout: Dictionary = state.get("own_loadout", {})
	var own_complete := bool(state.get("own_draft_complete", false)) \
		or bool(draft.get("own_complete", false))
	var drafting := not draft.is_empty() and not own_complete
	confirm_button.visible = not drafting and not loadout.is_empty()
	if drafting:
		_render_draft(draft)
	elif not loadout.is_empty():
		_render_loadout(loadout, series, format)
	elif own_complete:
		_show_waiting("Votre deck est terminé. En attente de l'adversaire…")
	else:
		_show_waiting("En attente de la préparation de l'hôte…")


func _render_draft(draft: Dictionary) -> void:
	var step := int(draft.get("own_step", draft.get("step", 0)))
	var chosen := str(draft.get("own_chosen", ""))
	if _pending_choice_step == step and _pending_choice_id != "":
		chosen = _pending_choice_id
	preparation_view.show_draft(draft, chosen)
	if bool(_state.get("opponent_ready", false)):
		opponent_ready_label.text = "L'adversaire est prêt."
	elif bool(draft.get("opponent_complete", false)):
		opponent_ready_label.text = "L'adversaire a terminé son deck."
	else:
		opponent_ready_label.text = "L'adversaire n'est pas encore prêt."
	status_label.text = "En attente de l'adversaire…" if chosen != "" else "Choisissez une carte."
	confirm_button.visible = false
	_update_timer()


func _render_loadout(loadout: Dictionary, series: Dictionary, format: String) -> void:
	confirm_button.visible = true
	var god := GodIdentityModel.player(str(loadout.get("god_id", "")))
	background.set_god(god)
	var tier := int(series.get("power_tier", _flow.rules().get("power_tier", RulesModel.DEFAULT_POWER_TIER)))
	preparation_view.show_loadout(loadout, tier, format)
	var own_ready := bool(_state.get("own_ready", false))
	var opponent_ready := bool(_state.get("opponent_ready", false))
	confirm_button.disabled = own_ready
	confirm_button.text = "PRÊT ✓" if own_ready else "PRÊT"
	if own_ready and opponent_ready:
		opponent_ready_label.text = "L'adversaire est prêt."
		status_label.text = "Les deux joueurs sont prêts."
	elif own_ready:
		opponent_ready_label.text = "L'adversaire n'est pas encore prêt."
		status_label.text = "En attente de l'adversaire…"
	elif opponent_ready:
		opponent_ready_label.text = "L'adversaire est prêt."
		status_label.text = "Votre deck est terminé."
	else:
		opponent_ready_label.text = "L'adversaire n'est pas encore prêt."
		status_label.text = "Votre deck est terminé."


func _show_waiting(message: String) -> void:
	preparation_view.show_waiting(message)
	confirm_button.visible = false
	opponent_ready_label.text = ""
	status_label.text = ""
	title_label.text = "PRÉPARATION"
	round_label.text = ""
	series_label.visible = false


func _update_timer() -> void:
	preparation_view.set_remaining_seconds(_flow.remaining_seconds() if _flow != null else 0.0)


func _on_card_chosen(stone_id: String) -> void:
	if _flow == null or _leaving:
		return
	var step := int(_state.get("draft", {}).get("own_step", -1))
	if not _flow.choose_local(stone_id):
		status_label.text = "Cette carte n'est plus disponible."
		return
	_pending_choice_step = step
	_pending_choice_id = stone_id
	_refresh(_flow.public_state())
	# L'hôte peut recevoir sa paire suivante dans le même appel ; ce texte reste
	# néanmoins le retour immédiat du toucher, sans explication supplémentaire.
	preparation_view.draft_status.text = "Choix enregistré."


func _on_confirm() -> void:
	if _flow == null or _leaving:
		return
	if not _flow.confirm_local():
		status_label.text = "La confirmation n'est pas disponible."
	_refresh(_flow.public_state())


func _on_round_ready(config: Dictionary) -> void:
	if _leaving:
		return
	_leaving = true
	PvpMatchContext.set_presence(LanPvpPresence.PRE_BATTLE)
	PvpMatchContext.begin(config, PvpMatchContext.local_side, LanSession.local_peer_id(),
		PvpMatchContext.lobby_local_profile(), PvpMatchContext.lobby_remote_profile(), true,
		_flow.rules())
	_disconnect_flow()
	Routes.go_with_override(get_tree(), scene_changer, Routes.PRE_BATTLE)


func _on_series_finished(state: Dictionary) -> void:
	if _leaving:
		return
	PvpMatchContext.set_series(state)
	status_label.text = "La série est terminée."


func _on_failed(message: String) -> void:
	if _leaving:
		return
	status_label.text = message
	confirm_button.disabled = true


func _on_session_state(session_state: int) -> void:
	if _leaving or session_state != LanSession.State.DISCONNECTED:
		return
	status_label.text = "La connexion avec l'adversaire est perdue."
	confirm_button.disabled = true


## RETOUR AU SALON est un départ individuel : le lien ENet reste ouvert et le
## pair ne reçoit qu'une présence LOBBY, jamais un ordre de navigation.
func _leave_session() -> void:
	if _leaving:
		return
	_leaving = true
	_disconnect_flow()
	var is_host := _flow != null and _flow.is_host()
	var local_profile := _flow.local_profile() if _flow != null \
		else PvpMatchContext.lobby_local_profile()
	var remote_profile := _flow.remote_profile() if _flow != null \
		else PvpMatchContext.lobby_remote_profile()
	var rules := _flow.rules() if _flow != null else PvpMatchContext.match_rules
	var client_peer := PvpMatchContext.peer_of_side(GameState.PLAYER_TWO) if is_host else 0
	PvpMatchContext.set_presence(LanPvpPresence.LOBBY)
	if _flow != null:
		_flow.close()
		_flow = null
	var released := PvpMatchContext.release_series()
	var kept_link := released.get("link") as LanSessionLink
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


func _remote_peer() -> int:
	if PvpMatchContext.local_side == GameState.PLAYER_ONE:
		var peers := LanSession.peer_ids()
		return int(peers[0]) if not peers.is_empty() else 0
	return LanProtocol.SERVER_ID


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_leave_session()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_leave_session()


func _exit_tree() -> void:
	_disconnect_flow()
	if not _leaving:
		if _flow != null:
			_flow.close()
			_flow = null
		var released := PvpMatchContext.release_series()
		if released.get("link") is LanSessionLink:
			(released["link"] as LanSessionLink).detach()
		PvpMatchContext.clear()
		LanSession.reset()


func _disconnect_flow() -> void:
	if _flow == null:
		return
	if _flow.state_changed.is_connected(_on_state):
		_flow.state_changed.disconnect(_on_state)
	if _flow.preparation_started.is_connected(_on_state):
		_flow.preparation_started.disconnect(_on_state)
	if _flow.draft_updated.is_connected(_on_state):
		_flow.draft_updated.disconnect(_on_state)
	if _flow.loadout_revealed.is_connected(_on_state):
		_flow.loadout_revealed.disconnect(_on_state)
	if _flow.round_ready.is_connected(_on_round_ready):
		_flow.round_ready.disconnect(_on_round_ready)
	if _flow.series_finished.is_connected(_on_series_finished):
		_flow.series_finished.disconnect(_on_series_finished)
	if _flow.failed.is_connected(_on_failed):
		_flow.failed.disconnect(_on_failed)
	if LanSession.state_changed.is_connected(_on_session_state):
		LanSession.state_changed.disconnect(_on_session_state)
