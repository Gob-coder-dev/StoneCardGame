## PvpLobbyController.gd
## Salon PVP local : un seul écran à la fois dans `PvpLobby.tscn`.
##   1. `ModeScreen`   — créer une partie ou en rejoindre une ;
##   2. `JoinScreen`   — salons trouvés sur le Wi-Fi et saisie d'adresse ;
##   3. `LobbyScreen`  — les deux joueurs, l'adresse à donner, puis PRÊT.
## Le cycle réseau appartient à PvpLobbyFlow ; ce contrôleur ne conserve que
## la présentation, les gestes et la transition vers l'avant-combat.
extends Control

const TouchButtonScript := preload("res://scripts/ui/input/TouchButton.gd")
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")
## Constantes d'état et type exposé à la vue ; le cycle reste dans le flow.
const LobbyCoordinator := preload("res://scripts/network/LanLobbyCoordinator.gd")
const FlowModel := preload("res://scripts/application/pvp/PvpLobbyFlow.gd")
const AddressResolver := preload("res://scripts/network/LanAddressResolver.gd")
const RulesModel := preload("res://scripts/domain/MatchRules.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")
const Presenter := preload("res://scripts/ui/pvp/PvpLobbyPresenter.gd")

const DECK_WARNING: String = "VEUILLEZ COMPLÉTER VOTRE DECK"

const MODE_NONE := FlowModel.MODE_NONE
const MODE_HOST := FlowModel.MODE_HOST
const MODE_JOIN := FlowModel.MODE_JOIN

@onready var back_button: Button = $Root/Header/BackButton
@onready var mode_screen: VBoxContainer = $Root/Scroll/Content/ModeScreen
@onready var create_card: PanelContainer = $Root/Scroll/Content/ModeScreen/CreateCard
@onready var join_card: PanelContainer = $Root/Scroll/Content/ModeScreen/JoinCard
@onready var create_button: Button = \
	$Root/Scroll/Content/ModeScreen/CreateCard/CreateBox/CreateButton
@onready var join_button: Button = \
	$Root/Scroll/Content/ModeScreen/JoinCard/JoinBox/JoinButton
@onready var join_screen: VBoxContainer = $Root/Scroll/Content/JoinScreen
@onready var join_title: Label = $Root/Scroll/Content/JoinScreen/JoinHeader/JoinTitle
@onready var join_refresh: Button = \
	$Root/Scroll/Content/JoinScreen/JoinHeader/RefreshButton
@onready var join_hint: Label = $Root/Scroll/Content/JoinScreen/JoinHint
@onready var games_panel: PanelContainer = $Root/Scroll/Content/JoinScreen/GamesPanel
@onready var games_list: VBoxContainer = \
	$Root/Scroll/Content/JoinScreen/GamesPanel/GamesBox/GamesList
@onready var empty_label: Label = \
	$Root/Scroll/Content/JoinScreen/GamesPanel/GamesBox/EmptyLabel
@onready var or_label: Label = $Root/Scroll/Content/JoinScreen/OrLabel
@onready var address_row: HBoxContainer = $Root/Scroll/Content/JoinScreen/AddressRow
@onready var address_input: LineEdit = \
	$Root/Scroll/Content/JoinScreen/AddressRow/AddressInput
@onready var connect_button: Button = \
	$Root/Scroll/Content/JoinScreen/AddressRow/ConnectButton
@onready var lobby_screen: VBoxContainer = $Root/Scroll/Content/LobbyScreen
@onready var lobby_title: Label = $Root/Scroll/Content/LobbyScreen/LobbyTitle
@onready var lobby_hint: Label = $Root/Scroll/Content/LobbyScreen/LobbyHint
@onready var rules_panel: PanelContainer = \
	$Root/Scroll/Content/LobbyScreen/RulesPanel
@onready var mode_option: OptionButton = \
	$Root/Scroll/Content/LobbyScreen/RulesPanel/RulesBox/ModeRow/ModeOption
@onready var series_option: OptionButton = \
	$Root/Scroll/Content/LobbyScreen/RulesPanel/RulesBox/SeriesRow/SeriesOption
@onready var tier_option: OptionButton = \
	$Root/Scroll/Content/LobbyScreen/RulesPanel/RulesBox/TierRow/TierOption
@onready var tier_row: HBoxContainer = \
	$Root/Scroll/Content/LobbyScreen/RulesPanel/RulesBox/TierRow
@onready var rules_hint: Label = \
	$Root/Scroll/Content/LobbyScreen/RulesPanel/RulesBox/RulesHint
@onready var address_panel: PanelContainer = \
	$Root/Scroll/Content/LobbyScreen/AddressPanel
@onready var address_button: Button = \
	$Root/Scroll/Content/LobbyScreen/AddressPanel/AddressBox/AddressButton
@onready var address_hint: Label = \
	$Root/Scroll/Content/LobbyScreen/AddressPanel/AddressBox/AddressHint
@onready var local_role: Label = \
	$Root/Scroll/Content/LobbyScreen/PlayersPanel/PlayersBox/LocalRow/LocalInfo/LocalRole
@onready var local_name: Label = \
	$Root/Scroll/Content/LobbyScreen/PlayersPanel/PlayersBox/LocalRow/LocalInfo/LocalName
@onready var local_god: Label = \
	$Root/Scroll/Content/LobbyScreen/PlayersPanel/PlayersBox/LocalRow/LocalInfo/LocalGod
@onready var local_status: Label = \
	$Root/Scroll/Content/LobbyScreen/PlayersPanel/PlayersBox/LocalRow/LocalStatus
@onready var remote_role: Label = \
	$Root/Scroll/Content/LobbyScreen/PlayersPanel/PlayersBox/RemoteRow/RemoteInfo/RemoteRole
@onready var remote_name: Label = \
	$Root/Scroll/Content/LobbyScreen/PlayersPanel/PlayersBox/RemoteRow/RemoteInfo/RemoteName
@onready var remote_god: Label = \
	$Root/Scroll/Content/LobbyScreen/PlayersPanel/PlayersBox/RemoteRow/RemoteInfo/RemoteGod
@onready var remote_status: Label = \
	$Root/Scroll/Content/LobbyScreen/PlayersPanel/PlayersBox/RemoteRow/RemoteStatus
@onready var ready_button: Button = $Root/Scroll/Content/LobbyScreen/ReadyButton
@onready var notice_label: Label = $Root/Scroll/Content/NoticeLabel
@onready var connection_overlay: ColorRect = $ConnectionOverlay
@onready var connection_target: Label = \
	$ConnectionOverlay/ConnectionCenter/ConnectionPanel/ConnectionContent/ConnectionTarget
@onready var connection_progress: Label = \
	$ConnectionOverlay/ConnectionCenter/ConnectionPanel/ConnectionContent/ConnectionProgress
@onready var connection_error: Label = \
	$ConnectionOverlay/ConnectionCenter/ConnectionPanel/ConnectionContent/ConnectionError
@onready var cancel_connection_button: Button = \
	$ConnectionOverlay/ConnectionCenter/ConnectionPanel/ConnectionContent/ConnectionActions/CancelButton
@onready var retry_connection_button: Button = \
	$ConnectionOverlay/ConnectionCenter/ConnectionPanel/ConnectionContent/ConnectionActions/RetryButton
@onready var close_connection_button: Button = \
	$ConnectionOverlay/ConnectionCenter/ConnectionPanel/ConnectionContent/ConnectionActions/CloseButton
@onready var background: MenuBackground = $Background

## Point d'injection réservé aux tests : le jeu réel utilise toujours GameRoutes.
var scene_changer: Callable = Callable()
var _flow: PvpLobbyFlow = FlowModel.new()
var _notice := ""
var _leaving := false
var _resumed := false


func _ready() -> void:
	_style_mode_cards()
	Audio.set_button_sfx(ready_button, AudioCatalog.SFX_BUTTON_2)
	_flow.changed.connect(_refresh_status)
	_flow.games_changed.connect(_on_games_changed)
	_flow.notice_requested.connect(_show_notice)
	_flow.match_started.connect(_on_match_started)
	_flow.series_ready.connect(_on_series_ready)
	back_button.pressed.connect(_go_back)
	create_button.pressed.connect(_start_hosting)
	join_button.pressed.connect(_start_search)
	join_refresh.pressed.connect(_restart_search)
	connect_button.pressed.connect(_connect_manual)
	address_button.pressed.connect(_copy_address)
	ready_button.pressed.connect(_press_ready)
	cancel_connection_button.pressed.connect(_dismiss_connection)
	retry_connection_button.pressed.connect(_retry_connection)
	close_connection_button.pressed.connect(_dismiss_connection)
	address_input.text_submitted.connect(_on_address_submitted)
	_build_rule_options()
	LanSession.connected_to_host.connect(_on_connected_to_host)
	LanSession.state_changed.connect(_on_session_state)
	LanSession.notice.connect(_show_notice)
	# Un retour connecté reprend le lien et les deux profils existants. Toute
	# autre entrée repart d'un état réseau propre et explique pourquoi le joueur
	# revient (fin de match, déconnexion, désynchronisation).
	var resume := PvpMatchContext.take_lobby_resume()
	if not resume.is_empty() and _flow.resume_session(resume):
		_resumed = true
		PvpMatchContext.clear()
		PvpMatchContext.stage = PvpMatchContext.Stage.LOBBY_RETURN
		LanSession.enter_lobby()
		_notice = "Retour au salon : la connexion et vos profils sont conservés."
	else:
		PvpMatchContext.close_presence()
		PvpMatchContext.clear()
		LanSession.reset()
	var notice := LanSession.last_notice
	LanSession.last_notice = ""
	_refresh_status()
	if notice != "":
		_show_notice(notice)


func _exit_tree() -> void:
	# Aucun rafraîchissement de contrôles pendant leur destruction : `reset()`
	# émet volontairement un dernier changement pour ses autres consommateurs.
	_disconnect_flow()
	if _leaving:
		_flow.close()
	else:
		_flow.reset()
	if LanSession.connected_to_host.is_connected(_on_connected_to_host):
		LanSession.connected_to_host.disconnect(_on_connected_to_host)
	if LanSession.state_changed.is_connected(_on_session_state):
		LanSession.state_changed.disconnect(_on_session_state)
	if LanSession.notice.is_connected(_show_notice):
		LanSession.notice.disconnect(_show_notice)


func _disconnect_flow() -> void:
	if _flow.changed.is_connected(_refresh_status):
		_flow.changed.disconnect(_refresh_status)
	if _flow.games_changed.is_connected(_on_games_changed):
		_flow.games_changed.disconnect(_on_games_changed)
	if _flow.notice_requested.is_connected(_show_notice):
		_flow.notice_requested.disconnect(_show_notice)
	if _flow.match_started.is_connected(_on_match_started):
		_flow.match_started.disconnect(_on_match_started)
	if _flow.series_ready.is_connected(_on_series_ready):
		_flow.series_ready.disconnect(_on_series_ready)


## La découverte doit tourner dans **tous** les modes : c'est `poll` qui émet
## le beacon de l'hôte. Seule la reconstruction de la liste appartient à
## l'écran de recherche.
func _process(delta: float) -> void:
	_update_connection_progress(delta)
	_flow.poll(delta)


func _on_games_changed(games: Array) -> void:
	_rebuild_games(games)
	_refresh_status()


## ─── Choix du mode ───────────────────────────────────────────────────────────

## Les deux cartes d'action portent la couleur de leur bouton. Sans cadre
## visible, la phrase d'aide flottait et seul le liseré du bouton « rejoindre »
## délimitait un bloc.
func _style_mode_cards() -> void:
	_style_mode_card(create_card, UITheme.COL_ACCENT)
	_style_mode_card(join_card, UITheme.COL_NEON)


func _style_mode_card(card: PanelContainer, accent: Color) -> void:
	var style := UITheme.panel_style(Color(0.145, 0.133, 0.160, 0.88), accent, 3, 24)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", style)


func _start_hosting() -> void:
	var deck := PlayerData.get_active_deck()
	if not DeckRules.is_deck_valid(deck, PlayerData.player_god_id):
		_show_notice(DECK_WARNING)
		return
	_flow.start_hosting(PlayerData.player_name, PlayerData.player_god_id, deck)


func _start_search() -> void:
	_flow.start_search()


## Relance l'écoute après une coupure Wi-Fi ou un socket mort : la liste est
## automatique, mais un socket ne se relève pas tout seul.
func _restart_search(notice: String = "") -> void:
	_flow.restart_search(notice)


## ─── Rejoindre ───────────────────────────────────────────────────────────────

func _connect_manual() -> void:
	var address := address_input.text.strip_edges()
	if address == "":
		_show_notice("Entrez l'adresse affichée sur la salle d'attente de l'hôte.")
		return
	_join_address(address)


func _on_address_submitted(_text: String) -> void:
	_connect_manual()


## L'adresse affichée et copiée contient le port (`ip:45555`) : on ne garde que
## l'hôte, le port de jeu étant fixe. Une adresse collée telle quelle marche
## donc du premier coup.
static func host_only(address: String) -> String:
	return AddressResolver.host_only(address)


func _join_address(address: String) -> void:
	_join_address_with_name(address)


func _join_address_with_name(address: String, host_name: String = "") -> void:
	if _flow.join_address(address, host_name):
		address_input.text = _flow.attempted_address
		_notice = ""


## Le client crée sa passerelle seulement une fois connecté : son identifiant
## réseau n'existe qu'à ce moment-là.
func _on_connected_to_host() -> void:
	if _leaving:
		return
	_flow.connected_to_host(PlayerData.player_name, PlayerData.player_god_id,
		PlayerData.get_active_deck())


func _press_ready() -> void:
	_flow.press_ready()


## ─── Navigation ──────────────────────────────────────────────────────────────

## Depuis le choix du mode on quitte le PVP ; depuis une recherche ou une salle
## on revient au choix du mode, sans perdre le chemin.
func _go_back() -> void:
	if _leaving:
		return
	if _flow.connection_attempt_pending:
		_dismiss_connection()
		return
	if _flow.mode == MODE_NONE and _flow.lobby == null:
		_leaving = true
		_reset_session()
		Routes.go_with_override(get_tree(), scene_changer, Routes.MAIN_MENU)
		return
	_reset_session()
	_refresh_status()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _on_session_state(session_state: int) -> void:
	_flow.handle_session_state(session_state)


func _reset_session() -> void:
	_flow.reset()
	_notice = ""


func _on_lobby_state(_state: Dictionary) -> void:
	_refresh_status()


func _on_match_started(config: Dictionary) -> void:
	if _leaving or _flow.lobby == null:
		return
	var is_host := bool(_flow.lobby.state()["is_host"])
	var side := GameState.PLAYER_ONE if is_host else GameState.PLAYER_TWO
	var local_profile := {}
	var remote_profile := {}
	for entry in config.get("participants", []):
		var participant: Dictionary = entry
		if int(participant.get("side", 0)) == side:
			local_profile = _profile_of(participant)
		else:
			remote_profile = _profile_of(participant)
	if local_profile.is_empty() or remote_profile.is_empty():
		_show_notice("Configuration de partie invalide.")
		return
	var series_flow := _flow.lobby.series_coordinator()
	var kept_link: LanSessionLink = null
	var rules := _flow.lobby.rules()
	if series_flow != null:
		PvpMatchContext.set_series(series_flow.public_state())
		kept_link = _flow.release_for_series()
	else:
		_flow.close_lobby()
	_leaving = true
	_flow.stop_discovery()
	PvpMatchContext.set_presence(LanPvpPresence.PRE_BATTLE)
	PvpMatchContext.begin(config, side, LanSession.local_peer_id(),
		local_profile, remote_profile, series_flow != null, rules)
	if series_flow != null:
		PvpMatchContext.set_series(series_flow.public_state())
		PvpMatchContext.keep_series(series_flow, kept_link)
	LanSession.enter_match()
	Routes.go_with_override(get_tree(), scene_changer, Routes.PRE_BATTLE)


## ─── Préparation de série ───────────────────────────────────────────────────

## Le salon se démonte sans fermer la connexion : le lien et le coordinateur de
## série sont confiés au contexte, puis la scène de préparation prend le relais.
func _on_series_ready(_rules: Dictionary) -> void:
	if _leaving or _flow.lobby == null or _flow.lobby.series_coordinator() == null:
		return
	var series_flow := _flow.lobby.series_coordinator()
	# Classique FT2/FT3 ne passe pas par une préparation vide : son client doit
	# toutefois recevoir `prepare_start` avant `round_start`. Le salon reste donc
	# affiché jusqu'à ce que le coordinateur émette `match_started` sur la
	# configuration de manche, via son branchement `round_ready`.
	if str(series_flow.rules().get("mode", "")) == RulesModel.MODE_CLASSIC:
		return
	var side := int(_flow.lobby.state()["local_side"])
	var local_profile := series_flow.local_profile()
	var remote_profile := series_flow.remote_profile()
	var flow_rules := series_flow.rules()
	var local_peer := LanSession.local_peer_id()
	var remote_peer := LanProtocol.SERVER_ID if side == GameState.PLAYER_TWO else _first_peer()
	var kept_link := _flow.release_for_series()
	PvpMatchContext.set_presence(LanPvpPresence.PREPARATION)
	PvpMatchContext.begin_preparation(series_flow, kept_link, side, local_peer, remote_peer,
		local_profile, remote_profile, flow_rules, series_flow.public_state())
	_leaving = true
	_flow.stop_discovery()
	LanSession.enter_match()
	Routes.go_with_override(get_tree(), scene_changer, Routes.PVP_PREPARATION)


func _first_peer() -> int:
	var peers := LanSession.peer_ids()
	return int(peers[0]) if not peers.is_empty() else 0


static func _profile_of(participant: Dictionary) -> Dictionary:
	return {
		"name": str(participant.get("name", "Joueur")),
		"god_id": str(participant.get("god_id", "")),
		"deck": (participant.get("deck", []) as Array).duplicate(),
	}


## ─── Affichage ───────────────────────────────────────────────────────────────

func _refresh_status() -> void:
	if _flow.lobby != null:
		background.room = MenuBackground.Room.PVP
		_fill_lobby()
		_show_screen(lobby_screen)
	elif _flow.mode == MODE_JOIN:
		_reset_ready_button()
		background.room = MenuBackground.Room.PVP
		background.set_god(GodIdentityModel.player(PlayerData.player_god_id))
		_fill_join()
		_show_screen(join_screen)
	else:
		_reset_ready_button()
		background.room = MenuBackground.Room.PVP
		background.set_god(GodIdentityModel.player(PlayerData.player_god_id))
		_show_screen(mode_screen)
	background.queue_redraw()
	_fill_connection_overlay()
	notice_label.text = _notice
	notice_label.visible = _notice != ""


func _show_screen(screen: Control) -> void:
	for candidate in [mode_screen, join_screen, lobby_screen]:
		(candidate as Control).visible = candidate == screen


func _reset_ready_button() -> void:
	ready_button.disabled = true
	ready_button.text = "PRÊT"


func _fill_join() -> void:
	join_title.text = "PARTIES TROUVÉES"
	join_hint.text = "Elles apparaissent dès qu'un hôte ouvre un salon, sur le même Wi-Fi."
	join_refresh.visible = true
	games_panel.visible = true
	or_label.visible = true
	address_row.visible = true
	empty_label.visible = games_list.get_child_count() == 0
	empty_label.text = "Recherche en cours… Aucun salon pour l'instant."


func _fill_connection_overlay() -> void:
	var connecting := LanSession.state == LanSession.State.CONNECTING
	var failed := LanSession.state == LanSession.State.DISCONNECTED
	connection_overlay.visible = _flow.mode == MODE_JOIN \
		and _flow.connection_attempt_pending and (connecting or failed)
	if not connection_overlay.visible:
		return

	var host := host_only(_flow.attempted_address)
	var target := "%s:%d" % [host, LanProtocol.GAME_PORT]
	connection_target.text = "Hôte : %s\n%s" % [_flow.attempted_host_name, target] \
		if _flow.attempted_host_name != "" else "Cible : %s" % target
	connection_progress.visible = connecting
	connection_error.visible = failed
	cancel_connection_button.visible = connecting
	retry_connection_button.visible = failed
	close_connection_button.visible = failed
	if connecting:
		connection_progress.text = "Connexion en cours… %d s" \
			% int(_flow.connection_elapsed)
	else:
		var reason := LanSession.last_notice
		connection_error.text = reason if reason != "" \
			else "Connexion impossible. Vérifiez l'adresse et le réseau local."


func _update_connection_progress(delta: float) -> void:
	if not _flow.connection_attempt_pending or LanSession.state != LanSession.State.CONNECTING:
		return
	_flow.connection_elapsed += delta
	var seconds := int(_flow.connection_elapsed)
	if seconds == _flow.displayed_connection_seconds:
		return
	_flow.displayed_connection_seconds = seconds
	connection_progress.text = "Connexion en cours… %d s" % seconds


func _retry_connection() -> void:
	if not _flow.connection_attempt_pending or _flow.attempted_address == "":
		return
	_join_address_with_name(_flow.attempted_address, _flow.attempted_host_name)


func _dismiss_connection() -> void:
	if not _flow.connection_attempt_pending:
		return
	address_input.text = _flow.attempted_address
	_flow.dismiss_connection()


func _fill_lobby() -> void:
	var lobby := _flow.lobby.state()
	var is_host := bool(lobby["is_host"])
	var local: Dictionary = lobby["host"] if is_host else lobby["client"]
	var remote: Dictionary = lobby["client"] if is_host else lobby["host"]
	var local_god_data := StoneLoader.get_god(str(local.get("god_id", "")))
	var remote_god_id := str(remote.get("god_id", ""))
	var remote_god_data := local_god_data if remote_god_id == "" \
		else StoneLoader.get_god(remote_god_id)
	background.set_gods(local_god_data, remote_god_data)
	var remote_in_game := bool(lobby.get("remote_in_game", false))
	var header := Presenter.header(lobby)
	lobby_title.text = str(header["title"])
	lobby_hint.text = str(header["hint"])
	address_panel.visible = is_host
	address_button.text = _address_text()
	_sync_rules(lobby)
	_fill_player(local_role, local_name, local_god, local_status, "VOUS", local)
	_fill_player(remote_role, remote_name, remote_god, remote_status, "ADVERSAIRE",
		remote, "En attente d'un adversaire…", remote_in_game)
	_update_ready_button(lobby)
	if _resumed:
		_resumed = false
		lobby_title.text = "SALON REPRIS"
		lobby_hint.text = "La connexion est conservée. Les règles sont de nouveau modifiables."


## ─── Règles de la série ─────────────────────────────────────────────────────

## Les listes viennent du domaine : aucun libellé n'est recopié dans la scène.
func _build_rule_options() -> void:
	for mode in RulesModel.MODES:
		mode_option.add_item(RulesModel.mode_label(mode))
		mode_option.set_item_metadata(mode_option.item_count - 1, mode)
	for series in RulesModel.SERIES_FORMATS:
		series_option.add_item(RulesModel.series_label(series))
		series_option.set_item_metadata(series_option.item_count - 1, series)
	for tier in range(RulesModel.MIN_POWER_TIER, RulesModel.MAX_POWER_TIER + 1):
		tier_option.add_item("Palier %d" % tier)
		tier_option.set_item_metadata(tier_option.item_count - 1, tier)
	mode_option.item_selected.connect(_on_mode_selected)
	series_option.item_selected.connect(_on_series_selected)
	tier_option.item_selected.connect(_on_tier_selected)


## Seul l'hôte peut modifier ; le verrouillage intervient après le double PRÊT.
## Le client voit les mêmes valeurs, sans pouvoir les changer.
func _sync_rules(lobby: Dictionary) -> void:
	var view := Presenter.rules(lobby)
	var rules: Dictionary = view["config"]
	var editable := bool(view["editable"])
	_select_rule(mode_option, str(rules.get("mode", RulesModel.MODE_CLASSIC)))
	_select_rule(series_option, str(rules.get("series", RulesModel.SERIES_FT1)))
	_select_rule(tier_option, int(rules.get("power_tier", RulesModel.DEFAULT_POWER_TIER)))
	var uses_power_tier := bool(view["uses_power_tier"])
	var minimum_tier := int(view["minimum_tier"])
	for index in range(tier_option.item_count):
		tier_option.set_item_disabled(index,
			int(tier_option.get_item_metadata(index)) < minimum_tier)
	tier_row.visible = uses_power_tier
	mode_option.disabled = not editable
	series_option.disabled = not editable
	tier_option.disabled = not editable or not uses_power_tier
	rules_panel.visible = not rules.is_empty()
	rules_hint.text = str(view["hint"])
	rules_hint.visible = rules_hint.text != ""


func _select_rule(option: OptionButton, value: Variant) -> void:
	for index in range(option.item_count):
		if option.get_item_metadata(index) == value or str(option.get_item_metadata(index)) == str(value):
			option.select(index)
			return


func _apply_rule(key: String, value: Variant) -> void:
	if _flow.lobby == null:
		return
	var result := _flow.lobby.set_rule(key, value)
	if not bool(result.get("ok", false)):
		_show_notice(str(result.get("reason", "Option indisponible.")))
	_fill_lobby()


func _on_mode_selected(index: int) -> void:
	_apply_rule("mode", mode_option.get_item_metadata(index))


func _on_series_selected(index: int) -> void:
	_apply_rule("series", series_option.get_item_metadata(index))


func _on_tier_selected(index: int) -> void:
	_apply_rule("power_tier", tier_option.get_item_metadata(index))


## Une carte joueur ne montre que ce qui se lit : nom, dieu dans sa couleur et
## badge d'état. Le deck n'apparaît pas : il est forcément valide pour arriver
## ici, et son état n'intéresse pas l'adversaire.
func _fill_player(role_label: Label, name_label: Label, god_label: Label,
		status_label: Label, role: String, profile: Dictionary,
		waiting_text: String = "", remote_in_game: bool = false) -> void:
	role_label.text = role
	var player_name := str(profile.get("name", ""))
	var present := player_name != "" and player_name != LobbyCoordinator.UNKNOWN_NAME
	name_label.text = player_name if present else (waiting_text if waiting_text != "" else "—")
	var god := StoneLoader.get_god(str(profile.get("god_id", "")))
	if present and not god.is_empty():
		god_label.text = str(god.get("name", ""))
		god_label.add_theme_color_override("font_color",
			Color(str(god.get("color", UITheme.COL_TEXT.to_html()))))
	elif present:
		god_label.text = "Dieu non choisi"
		god_label.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	else:
		god_label.text = ""
	status_label.visible = present
	if not present:
		return
	if remote_in_game:
		status_label.text = "EN PARTIE"
		status_label.add_theme_color_override("font_color", UITheme.COL_WARNING)
		return
	var ready := bool(profile.get("ready", false))
	status_label.text = "PRÊT" if ready else "PAS PRÊT"
	status_label.add_theme_color_override("font_color",
		UITheme.COL_SUCCESS if ready else UITheme.COL_ERROR)


func _update_ready_button(lobby: Dictionary) -> void:
	var ready_local := _flow.lobby.is_ready_local()
	var both_ready := bool(lobby["both_ready"])
	var remote_in_game := bool(lobby.get("remote_in_game", false))
	ready_button.disabled = not bool(lobby["can_ready"]) or ready_local or both_ready \
		or remote_in_game
	if both_ready:
		ready_button.text = "DÉMARRAGE…"
	elif ready_local:
		ready_button.text = "PRÊT ✓"
		lobby_hint.text = "En attente de l'adversaire…"
	else:
		ready_button.text = "PRÊT"


## ─── Adresse locale ──────────────────────────────────────────────────────────

## Godot ne donne pas le nom des interfaces : on classe les adresses pour
## proposer d'abord le Wi-Fi domestique, seul joignable par l'autre téléphone,
## avant les réseaux VPN ou opérateur (10.x) qui, eux, ne le sont pas.
static func address_rank(address: String) -> int:
	return AddressResolver.address_rank(address)


static func rank_addresses(addresses: Array) -> Array:
	return AddressResolver.rank_addresses(addresses)


static func _sorts_before(first: String, second: String) -> bool:
	return AddressResolver._sorts_before(first, second)


func _address_text() -> String:
	var addresses := rank_addresses(IP.get_local_addresses())
	if addresses.is_empty():
		return "Aucune adresse Wi-Fi détectée"
	return "%s:%d" % [str(addresses[0]), LanProtocol.GAME_PORT]


func _copy_address() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return
	DisplayServer.clipboard_set(address_button.text)
	address_hint.text = "Adresse copiée. Donnez-la à votre adversaire."


## ─── Liste des salons ────────────────────────────────────────────────────────

func _rebuild_games(games: Array) -> void:
	for child in games_list.get_children():
		games_list.remove_child(child)
		child.queue_free()
	for game in games:
		games_list.add_child(_game_row(game))


func _game_row(game: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_SMALL)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	var name_label := Label.new()
	name_label.text = str(game.get("name", "Hôte"))
	name_label.add_theme_font_size_override("font_size", 32)
	text.add_child(name_label)
	var compatible := bool(game.get("compatible", false))
	var address_label_row := Label.new()
	address_label_row.text = "%s:%d%s" % [str(game.get("address", "")),
		int(game.get("port", 0)), "" if compatible else " • version différente"]
	address_label_row.add_theme_font_size_override("font_size", 24)
	address_label_row.add_theme_color_override("font_color",
		UITheme.COL_TEXT_DIM if compatible else UITheme.COL_WARNING)
	address_label_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(address_label_row)
	row.add_child(text)
	var join := TouchButtonScript.new() as Button
	join.text = "REJOINDRE"
	join.custom_minimum_size = Vector2(260, 96)
	join.add_theme_font_size_override("font_size", 30)
	join.disabled = not compatible
	join.pressed.connect(_join_address_with_name.bind(
		str(game.get("address", "")), str(game.get("name", ""))))
	row.add_child(join)
	return row


func _show_notice(message: String) -> void:
	_notice = message
	notice_label.text = message
	notice_label.visible = message != ""
