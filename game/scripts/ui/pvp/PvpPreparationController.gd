extends Control

const RulesModel := preload("res://scripts/domain/MatchRules.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")
const LayoutModel := preload("res://scripts/ui/pvp/PvpPreparationLayout.gd")

@onready var back_button: Button = $Root/Header/BackButton
@onready var title_label: Label = $Root/Header/Titles/Title
@onready var round_label: Label = $Root/Header/Titles/RoundLabel
@onready var series_label: Label = $Root/Header/SeriesLabel
@onready var scroll: ScrollContainer = $Root/Scroll
@onready var draft_panel: VBoxContainer = $Root/Scroll/Content/DraftPanel
@onready var opponent_info: Label = \
	$Root/Scroll/Content/DraftPanel/OpponentPanel/OpponentBox/OpponentInfo
@onready var opponent_grid: LoadoutCardGrid = \
	$Root/Scroll/Content/DraftPanel/OpponentPanel/OpponentBox/OpponentGrid
@onready var local_grid: LoadoutCardGrid = \
	$Root/Scroll/Content/DraftPanel/LocalPanel/LocalBox/LocalGrid
@onready var draft_deck_grid: LoadoutCardGrid = \
	$Root/Scroll/Content/DraftPanel/DraftDeckPanel/DraftDeckBox/DraftDeckGrid
@onready var draft_deck_title: Label = \
	$Root/Scroll/Content/DraftPanel/DraftDeckPanel/DraftDeckBox/DraftDeckTitle
@onready var draft_status: Label = \
	$Root/Scroll/Content/DraftPanel/LocalPanel/LocalBox/DraftStatus
@onready var draft_info: Label = \
	$Root/Scroll/Content/DraftPanel/LocalPanel/LocalBox/DraftInfo
@onready var draft_timer: Label = \
	$Root/Scroll/Content/DraftPanel/LocalPanel/LocalBox/DraftTimer
@onready var reveal_panel: VBoxContainer = $Root/Scroll/Content/RevealPanel
@onready var god_portrait: GodPortrait = \
	$Root/Scroll/Content/RevealPanel/GodPanel/GodBox/GodPortrait
@onready var god_name: Label = \
	$Root/Scroll/Content/RevealPanel/GodPanel/GodBox/GodInfo/GodName
@onready var god_family: Label = \
	$Root/Scroll/Content/RevealPanel/GodPanel/GodBox/GodInfo/GodFamily
@onready var loadout_info: Label = \
	$Root/Scroll/Content/RevealPanel/GodPanel/GodBox/GodInfo/LoadoutInfo
@onready var deck_grid: LoadoutCardGrid = $Root/Scroll/Content/RevealPanel/DeckGrid
@onready var wait_label: Label = $Root/Scroll/Content/WaitLabel
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
var _draft_deck_columns := 4
var _opponent_card_size := UITheme.PVP_OPPONENT_CARD_MAX
var _local_card_size := UITheme.PVP_LOCAL_CARD_MAX
var _draft_card_size := UITheme.PVP_DRAFT_CARD_MAX
var _final_card_size := UITheme.PVP_FINAL_CARD_MAX
var _layout_fit_pending := false


func _ready() -> void:
	if not PvpMatchContext.series_flow is LanSeriesCoordinator:
		_show_waiting("Préparation indisponible. Revenez au salon.")
		confirm_button.visible = false
		return
	_flow = PvpMatchContext.series_flow as LanSeriesCoordinator
	PvpMatchContext.set_presence(LanPvpPresence.PREPARATION)
	back_button.pressed.connect(_leave_session)
	confirm_button.pressed.connect(_on_confirm)
	local_grid.card_chosen.connect(_on_card_chosen)
	scroll.resized.connect(_on_scroll_resized)
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
	draft_panel.visible = drafting
	reveal_panel.visible = not drafting and not loadout.is_empty()
	wait_label.visible = not drafting and loadout.is_empty()
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
	var own_side := int(draft.get("own_side", PvpMatchContext.local_side))
	var opponent_offers: Array = draft.get("offers_two", []) if own_side == GameState.PLAYER_ONE \
		else draft.get("offers_one", [])
	var own_offers: Array = draft.get("own_offers", [])
	var step := int(draft.get("own_step", draft.get("step", 0)))
	var total := int(draft.get("total_steps", DeckRules.DECK_SIZE))
	var opponent_step := clampi(int(draft.get("opponent_step", 0)), 0, total)
	var chosen := str(draft.get("own_chosen", ""))
	if _pending_choice_step == step and _pending_choice_id != "":
		chosen = _pending_choice_id
	var own_deck: Array = (draft.get("own_deck", []) as Array).duplicate(true)
	opponent_info.text = "Adversaire : %d / %d cartes choisies" % [opponent_step, total]
	opponent_grid.show_cards(opponent_offers, _opponent_card_size, 2, false, "",
		_opponent_card_size)
	local_grid.show_cards(own_offers, _local_card_size, 2,
		chosen == "" and not own_offers.is_empty(), chosen, _local_card_size)
	draft_deck_grid.show_cards(own_deck, _draft_card_size, _draft_deck_columns,
		false, "", _draft_card_size)
	draft_deck_title.text = "VOTRE DECK — %d / %d" % [own_deck.size(), DeckRules.DECK_SIZE]
	if chosen != "":
		draft_status.text = "Choix enregistré."
	elif own_offers.is_empty():
		draft_status.text = "Votre deck est terminé."
	else:
		draft_status.text = "Choisissez une carte."
	draft_info.text = "Étape %d / %d • %d cartes choisies" % [
		mini(step + 1, total), total, own_deck.size()
	]
	if bool(_state.get("opponent_ready", false)):
		opponent_ready_label.text = "L'adversaire est prêt."
	elif bool(draft.get("opponent_complete", false)):
		opponent_ready_label.text = "L'adversaire a terminé son deck."
	else:
		opponent_ready_label.text = "L'adversaire n'est pas encore prêt."
	status_label.text = "En attente de l'adversaire…" if chosen != "" else "Choisissez une carte."
	confirm_button.visible = false
	_update_timer()
	_schedule_layout_fit()


func _render_loadout(loadout: Dictionary, series: Dictionary, format: String) -> void:
	draft_panel.visible = false
	reveal_panel.visible = true
	wait_label.visible = false
	confirm_button.visible = true
	var god := StoneLoader.get_god(str(loadout.get("god_id", "")))
	god_portrait.setup(god)
	god_name.text = str(god.get("name", loadout.get("god_id", "")))
	var family := str(god.get("family_name", ""))
	god_family.text = family if family != "" else "Dieu"
	god_family.add_theme_color_override("font_color",
		Color(str(god.get("color", UITheme.COL_TEXT.to_html()))))
	background.set_god(god)
	var total := float(int(loadout.get("total_quarters", 0))) / float(StoneCostRules.COST_SCALE)
	var tier := int(series.get("power_tier", _flow.rules().get("power_tier", RulesModel.DEFAULT_POWER_TIER)))
	loadout_info.text = "%d cartes • %.2f points • palier %d • %s" % [
		(loadout.get("deck", []) as Array).size(), total, tier, format.to_upper()
	]
	var deck: Array = loadout.get("deck", [])
	# Le dernier choix doit aussi actualiser la zone de deck en construction,
	# même si elle est déjà masquée par la présentation finale.
	draft_deck_grid.show_cards(deck, _draft_card_size, _draft_deck_columns,
		false, "", _draft_card_size)
	draft_deck_title.text = "VOTRE DECK — %d / %d" % [deck.size(), DeckRules.DECK_SIZE]
	# Deck final en portrait : deux colonnes et quatre lignes, taille calculée
	# par LoadoutCardGrid depuis la largeur disponible.
	deck_grid.show_cards(deck, _final_card_size, 2, false, "", _final_card_size)
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
	_schedule_layout_fit()


func _show_waiting(message: String) -> void:
	draft_panel.visible = false
	reveal_panel.visible = false
	wait_label.visible = true
	wait_label.text = message
	confirm_button.visible = false
	opponent_ready_label.text = ""
	status_label.text = ""
	title_label.text = "PRÉPARATION"
	round_label.text = ""
	series_label.visible = false


## La largeur du bas de page décide du nombre de colonnes du deck en
## construction : deux colonnes lisibles sur téléphone étroit, quatre sur les
## écrans plus larges. Aucun redimensionnement horizontal n'est nécessaire.
func _on_scroll_resized() -> void:
	var columns := _draft_deck_columns_for(scroll.size.x)
	if columns != _draft_deck_columns:
		_draft_deck_columns = columns
		if _flow != null and not _leaving and draft_panel.visible:
			_refresh(_flow.public_state())
	_schedule_layout_fit()


func _draft_deck_columns_for(width: float) -> int:
	return LayoutModel.draft_columns(width)


## Ajuste les cartes à la hauteur réellement disponible. La largeur donne une
## borne par colonne, mais elle ne peut plus agrandir une tablette au point de
## masquer la dernière ligne. Le ScrollContainer reste uniquement un filet de
## sécurité pour les fenêtres plus petites que les appareils pris en charge.
func _schedule_layout_fit() -> void:
	if _layout_fit_pending or not is_inside_tree():
		return
	_layout_fit_pending = true
	_fit_current_layout.call_deferred()


func _fit_current_layout() -> void:
	_layout_fit_pending = false
	if _leaving or scroll.size.x <= 0.0 or scroll.size.y <= 0.0:
		return
	var changed := false
	if draft_panel.visible:
		changed = _fit_draft_layout()
	elif reveal_panel.visible:
		changed = _fit_reveal_layout()
	if changed and _flow != null:
		_refresh(_state if not _state.is_empty() else _flow.public_state())
		return
	# Aux formats officiellement supportés, le contenu tient entièrement. Une
	# ancienne position de scroll ne doit pas laisser l'en-tête hors champ.
	var bar := scroll.get_v_scroll_bar()
	if bar.max_value <= bar.page + 1.0:
		scroll.scroll_vertical = 0


func _fit_draft_layout() -> bool:
	var next := LayoutModel.draft_sizes(size, scroll.size,
		draft_panel.get_combined_minimum_size().y,
		[opponent_grid.size.x, local_grid.size.x, draft_deck_grid.size.x],
		[opponent_grid.get_child_count(), local_grid.get_child_count(),
			draft_deck_grid.get_child_count()], _draft_deck_columns,
		[_opponent_card_size, _local_card_size, _draft_card_size])
	var next_opponent := int(next["opponent"])
	var next_local := int(next["local"])
	var next_deck := int(next["deck"])
	var changed := next_opponent != _opponent_card_size \
		or next_local != _local_card_size or next_deck != _draft_card_size
	_opponent_card_size = next_opponent
	_local_card_size = next_local
	_draft_card_size = next_deck
	return changed


func _fit_reveal_layout() -> bool:
	var next_size := LayoutModel.reveal_size(scroll.size,
		reveal_panel.get_combined_minimum_size().y, deck_grid.size.x, _final_card_size)
	if next_size == _final_card_size:
		return false
	_final_card_size = next_size
	return true


func _update_timer() -> void:
	var remaining := float(_state.get("remaining_seconds", 0.0))
	var drafting := draft_panel.visible
	draft_timer.visible = drafting and remaining > 0.0
	if draft_timer.visible:
		draft_timer.text = "Temps de draft : %d s" % int(ceilf(remaining))


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
	draft_status.text = "Choix enregistré."


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
	_go_route(Routes.PRE_BATTLE)


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
	_go_route(Routes.PVP_LOBBY)


func _go_route(path: String) -> void:
	if scene_changer.is_valid():
		scene_changer.call(path)
		return
	Routes.go(get_tree(), path)


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
