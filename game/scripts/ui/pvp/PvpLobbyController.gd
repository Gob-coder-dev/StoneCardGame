## PvpLobbyController.gd
## Salon PVP local : un seul écran à la fois dans `PvpLobby.tscn`.
##   1. `ModeScreen`   — créer une partie ou en rejoindre une ;
##   2. `JoinScreen`   — salons trouvés sur le Wi-Fi et saisie d'adresse ;
##   3. `LobbyScreen`  — les deux joueurs, l'adresse à donner, puis PRÊT.
## Ce contrôleur ne contient ni transport ni règle : il affiche l'état du
## coordinateur de salon et lui transmet les actions du joueur.
extends Control

const LobbyCoordinator := preload("res://scripts/network/LanLobbyCoordinator.gd")
const Discovery := preload("res://scripts/network/LanDiscovery.gd")
const SessionLink := preload("res://scripts/network/LanSessionLink.gd")
const TouchButtonScript := preload("res://scripts/ui/input/TouchButton.gd")

const MENU_SCENE: String = "res://scenes/menus/MainMenu.tscn"
## Le pile ou face du salon s'affiche avant le plateau, comme en campagne.
const PREBATTLE_SCENE: String = "res://scenes/menus/PreBattle.tscn"
const DECK_WARNING: String = "VEUILLEZ COMPLÉTER VOTRE DECK"

const MODE_NONE := ""
const MODE_HOST := "hosting"
const MODE_JOIN := "joining"

@onready var back_button: Button = $Root/Header/BackButton
@onready var mode_screen: VBoxContainer = $Root/Scroll/Content/ModeScreen
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

var _mode := MODE_NONE
var _discovery: LanDiscovery = null
var _link: LanSessionLink = null
var _lobby: LanLobbyCoordinator = null
var _games_signature := ""
var _notice := ""
var _leaving := false
var _connection_attempt_pending := false
var _attempted_address := ""
var _attempted_host_name := ""
var _connection_elapsed := 0.0
var _displayed_connection_seconds := -1


func _ready() -> void:
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
	LanSession.connected_to_host.connect(_on_connected_to_host)
	LanSession.state_changed.connect(_on_session_state)
	LanSession.notice.connect(_show_notice)
	# Le salon repart toujours d'un état réseau propre, puis explique pourquoi
	# le joueur y revient (fin de match, déconnexion, désynchronisation).
	PvpMatchContext.clear()
	LanSession.reset()
	var notice := LanSession.last_notice
	LanSession.last_notice = ""
	_refresh_status()
	if notice != "":
		_show_notice(notice)


func _exit_tree() -> void:
	_stop_discovery()
	_close_lobby()
	if LanSession.connected_to_host.is_connected(_on_connected_to_host):
		LanSession.connected_to_host.disconnect(_on_connected_to_host)
	if LanSession.state_changed.is_connected(_on_session_state):
		LanSession.state_changed.disconnect(_on_session_state)
	if LanSession.notice.is_connected(_show_notice):
		LanSession.notice.disconnect(_show_notice)


## La découverte doit tourner dans **tous** les modes : c'est `poll` qui émet
## le beacon de l'hôte. Seule la reconstruction de la liste appartient à
## l'écran de recherche.
func _process(delta: float) -> void:
	_update_connection_progress(delta)
	if _discovery == null or not _discovery.is_active():
		return
	_discovery.poll(delta)
	if _mode != MODE_JOIN or _lobby != null:
		return
	var games := _discovery.games()
	var signature := ""
	for game in games:
		signature += "%s|%s|%s;" % [game.get("key", ""), game.get("name", ""),
			str(game.get("compatible", false))]
	if signature == _games_signature:
		return
	_games_signature = signature
	_rebuild_games(games)
	_refresh_status()


## ─── Choix du mode ───────────────────────────────────────────────────────────

func _start_hosting() -> void:
	var deck := PlayerData.get_active_deck()
	if not DeckRules.is_deck_valid(deck, PlayerData.player_god_id):
		_show_notice(DECK_WARNING)
		return
	_stop_discovery()
	_close_lobby()
	LanSession.reset()
	_mode = MODE_HOST
	if not LanSession.host_game():
		_mode = MODE_NONE
		_show_notice(LanSession.last_notice)
		_refresh_status()
		return
	_link = SessionLink.new()
	_link.attach(LanSession)
	_lobby = LobbyCoordinator.new()
	_lobby.attach(_link, true)
	_lobby.state_changed.connect(_on_lobby_state)
	_lobby.match_started.connect(_on_match_started)
	_lobby.failed.connect(_show_notice)
	_lobby.set_local_profile(PlayerData.player_name, PlayerData.player_god_id, deck)
	_start_broadcast()
	_show_notice("")
	_refresh_status()


func _start_search() -> void:
	if _mode == MODE_JOIN and _discovery != null and _discovery.is_active():
		return
	_stop_discovery()
	_close_lobby()
	LanSession.reset()
	_mode = MODE_JOIN
	_discovery = Discovery.new()
	if not _discovery.start_listening():
		_show_notice(_discovery.last_error)
		_discovery = null
		_refresh_status()
		return
	LanSession.enter_discovery()
	_games_signature = ""
	_rebuild_games([])
	_show_notice("")
	_refresh_status()


## Relance l'écoute après une coupure Wi-Fi ou un socket mort : la liste est
## automatique, mais un socket ne se relève pas tout seul.
func _restart_search(notice: String = "") -> void:
	if _mode != MODE_JOIN or _lobby != null:
		return
	_stop_discovery()
	_discovery = Discovery.new()
	if not _discovery.start_listening():
		var error := _discovery.last_error
		_discovery = null
		_show_notice("%s %s" % [notice, error] if notice != "" else error)
		_refresh_status()
		return
	LanSession.enter_discovery()
	_games_signature = ""
	_rebuild_games([])
	_show_notice(notice)
	_refresh_status()


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
	var clean := address.strip_edges()
	if clean.contains("://"):
		clean = clean.split("://", true, 1)[1]
	if clean.contains(":"):
		clean = clean.split(":", true, 1)[0]
	return clean.strip_edges()


func _join_address(address: String) -> void:
	_join_address_with_name(address)


func _join_address_with_name(address: String, host_name: String = "") -> void:
	var host := host_only(address)
	if host == "":
		_show_notice("Entrez l'adresse affichée sur la salle d'attente de l'hôte.")
		return
	_stop_discovery()
	_close_lobby()
	LanSession.reset()
	_mode = MODE_JOIN
	_attempted_address = address.strip_edges()
	_attempted_host_name = host_name.strip_edges()
	address_input.text = _attempted_address
	_connection_attempt_pending = true
	_connection_elapsed = 0.0
	_displayed_connection_seconds = -1
	_notice = ""
	LanSession.last_notice = ""
	if not LanSession.join_game(host):
		_refresh_status()
		return
	_refresh_status()


## Le client crée sa passerelle seulement une fois connecté : son identifiant
## réseau n'existe qu'à ce moment-là.
func _on_connected_to_host() -> void:
	if _mode != MODE_JOIN or _leaving or _lobby != null:
		return
	_connection_attempt_pending = false
	_link = SessionLink.new()
	_link.attach(LanSession)
	_lobby = LobbyCoordinator.new()
	_lobby.attach(_link, false)
	_lobby.state_changed.connect(_on_lobby_state)
	_lobby.match_started.connect(_on_match_started)
	_lobby.failed.connect(_show_notice)
	_lobby.set_local_profile(PlayerData.player_name, PlayerData.player_god_id,
		PlayerData.get_active_deck())
	_lobby.client_connected()
	_refresh_status()


func _press_ready() -> void:
	if _lobby == null:
		return
	_lobby.press_ready()
	_refresh_status()


## ─── Navigation ──────────────────────────────────────────────────────────────

## Depuis le choix du mode on quitte le PVP ; depuis une recherche ou une salle
## on revient au choix du mode, sans perdre le chemin.
func _go_back() -> void:
	if _leaving:
		return
	if _connection_attempt_pending:
		_dismiss_connection()
		return
	if _mode == MODE_NONE and _lobby == null:
		_leaving = true
		_reset_session()
		get_tree().change_scene_to_file(MENU_SCENE)
		return
	_reset_session()
	_refresh_status()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _on_session_state(session_state: int) -> void:
	if session_state == LanSession.State.DISCONNECTED \
			and _mode == MODE_JOIN and _lobby != null:
		var message := LanSession.last_notice
		if message == "":
			message = "L'hôte a quitté le salon."
		_close_lobby()
		_connection_attempt_pending = false
		LanSession.last_notice = ""
		_restart_search(message)
		return
	_refresh_status()


## ─── Cycle réseau ────────────────────────────────────────────────────────────

func _start_broadcast() -> void:
	_discovery = Discovery.new()
	var beacon := LanProtocol.make_beacon(PlayerData.player_name, LanProtocol.GAME_PORT, 1)
	if not _discovery.start_broadcast(beacon):
		var reason := _discovery.last_error
		_discovery = null
		_show_notice("%s Votre adversaire peut entrer votre adresse à la main." % reason)


func _stop_discovery() -> void:
	if _discovery != null:
		_discovery.stop()
		_discovery = null
	_games_signature = ""


func _close_lobby() -> void:
	if _lobby != null:
		_lobby.close()
		_lobby = null
	if is_node_ready():
		ready_button.disabled = true
		ready_button.text = "PRÊT"
	if _link != null:
		_link.detach()
		_link = null


func _reset_session() -> void:
	_stop_discovery()
	_close_lobby()
	LanSession.reset()
	PvpMatchContext.clear()
	_mode = MODE_NONE
	_notice = ""
	_games_signature = ""
	_rebuild_games([])


func _on_lobby_state(_state: Dictionary) -> void:
	_refresh_status()


func _on_match_started(config: Dictionary) -> void:
	if _leaving or _lobby == null:
		return
	var is_host := bool(_lobby.state()["is_host"])
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
	_leaving = true
	_stop_discovery()
	_close_lobby()
	PvpMatchContext.begin(config, side, LanSession.local_peer_id(), local_profile, remote_profile)
	LanSession.enter_match()
	get_tree().change_scene_to_file(PREBATTLE_SCENE)


static func _profile_of(participant: Dictionary) -> Dictionary:
	return {
		"name": str(participant.get("name", "Joueur")),
		"god_id": str(participant.get("god_id", "")),
		"deck": (participant.get("deck", []) as Array).duplicate(),
	}


## ─── Affichage ───────────────────────────────────────────────────────────────

func _refresh_status() -> void:
	if _lobby != null:
		background.room = MenuBackground.Room.PVP
		_fill_lobby()
		_show_screen(lobby_screen)
	elif _mode == MODE_JOIN:
		background.room = MenuBackground.Room.PVP
		background.set_god(StoneLoader.get_god(PlayerData.player_god_id))
		_fill_join()
		_show_screen(join_screen)
	else:
		background.room = MenuBackground.Room.PVP
		background.set_god(StoneLoader.get_god(PlayerData.player_god_id))
		_show_screen(mode_screen)
	background.queue_redraw()
	_fill_connection_overlay()
	notice_label.text = _notice
	notice_label.visible = _notice != ""


func _show_screen(screen: Control) -> void:
	for candidate in [mode_screen, join_screen, lobby_screen]:
		(candidate as Control).visible = candidate == screen


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
	connection_overlay.visible = _mode == MODE_JOIN \
		and _connection_attempt_pending and (connecting or failed)
	if not connection_overlay.visible:
		return

	var host := host_only(_attempted_address)
	var target := "%s:%d" % [host, LanProtocol.GAME_PORT]
	connection_target.text = "Hôte : %s\n%s" % [_attempted_host_name, target] \
		if _attempted_host_name != "" else "Cible : %s" % target
	connection_progress.visible = connecting
	connection_error.visible = failed
	cancel_connection_button.visible = connecting
	retry_connection_button.visible = failed
	close_connection_button.visible = failed
	if connecting:
		connection_progress.text = "Connexion en cours… %d s" \
			% int(_connection_elapsed)
	else:
		var reason := LanSession.last_notice
		connection_error.text = reason if reason != "" \
			else "Connexion impossible. Vérifiez l'adresse et le réseau local."


func _update_connection_progress(delta: float) -> void:
	if not _connection_attempt_pending or LanSession.state != LanSession.State.CONNECTING:
		return
	_connection_elapsed += delta
	var seconds := int(_connection_elapsed)
	if seconds == _displayed_connection_seconds:
		return
	_displayed_connection_seconds = seconds
	connection_progress.text = "Connexion en cours… %d s" % seconds


func _retry_connection() -> void:
	if not _connection_attempt_pending or _attempted_address == "":
		return
	_join_address_with_name(_attempted_address, _attempted_host_name)


func _dismiss_connection() -> void:
	if not _connection_attempt_pending:
		return
	address_input.text = _attempted_address
	_connection_attempt_pending = false
	_connection_elapsed = 0.0
	_stop_discovery()
	LanSession.reset()
	LanSession.last_notice = ""
	_show_notice("")
	_restart_search()


func _fill_lobby() -> void:
	var lobby := _lobby.state()
	var is_host := bool(lobby["is_host"])
	var local: Dictionary = lobby["host"] if is_host else lobby["client"]
	var remote: Dictionary = lobby["client"] if is_host else lobby["host"]
	var local_god_data := StoneLoader.get_god(str(local.get("god_id", "")))
	var remote_god_id := str(remote.get("god_id", ""))
	var remote_god_data := local_god_data if remote_god_id == "" \
		else StoneLoader.get_god(remote_god_id)
	background.set_gods(local_god_data, remote_god_data)
	var status := str(lobby["status"])
	lobby_title.text = "SALLE OUVERTE"
	lobby_hint.text = "En attente d'un adversaire sur le même Wi-Fi…"
	if status == LobbyCoordinator.STATUS_CONNECTED:
		lobby_title.text = "ADVERSAIRE CONNECTÉ"
		lobby_hint.text = "Vérifiez votre dieu, puis touchez PRÊT."
	elif status == LobbyCoordinator.STATUS_BOTH_READY:
		lobby_title.text = "LES DEUX JOUEURS SONT PRÊTS"
		lobby_hint.text = "La partie démarre…"
	elif status == LobbyCoordinator.STATUS_ERROR:
		lobby_title.text = "ERREUR"
		lobby_hint.text = str(lobby["error"])
	address_panel.visible = is_host
	address_button.text = _address_text()
	_fill_player(local_role, local_name, local_god, local_status, "VOUS", local)
	_fill_player(remote_role, remote_name, remote_god, remote_status, "ADVERSAIRE",
		remote, "En attente d'un adversaire…")
	_update_ready_button(lobby)


## Une carte joueur ne montre que ce qui se lit : nom, dieu dans sa couleur et
## badge d'état. Le deck n'apparaît pas : il est forcément valide pour arriver
## ici, et son état n'intéresse pas l'adversaire.
func _fill_player(role_label: Label, name_label: Label, god_label: Label,
		status_label: Label, role: String, profile: Dictionary,
		waiting_text: String = "") -> void:
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
	var ready := bool(profile.get("ready", false))
	status_label.text = "PRÊT" if ready else "PAS PRÊT"
	status_label.add_theme_color_override("font_color",
		UITheme.COL_SUCCESS if ready else UITheme.COL_ERROR)


func _update_ready_button(lobby: Dictionary) -> void:
	var ready_local := _lobby.is_ready_local()
	var both_ready := bool(lobby["both_ready"])
	ready_button.disabled = not bool(lobby["can_ready"]) or ready_local or both_ready
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
	if address.begins_with("192.168."):
		return 0
	var parts := address.split(".")
	if parts.size() == 4 and parts[0] == "172":
		var second := int(parts[1])
		if second >= 16 and second <= 31:
			return 1
	if address.begins_with("10."):
		return 2
	return 3


static func rank_addresses(addresses: Array) -> Array:
	var result: Array = []
	for entry in addresses:
		var address := str(entry)
		if address.contains(":") or address.begins_with("127.") \
				or address.begins_with("169.254."):
			continue
		result.append(address)
	## Tri par insertion : le classement d'abord, puis l'ordre lexicographique
	## pour rester déterministe. Aucune allocation de fermeture.
	for index in range(1, result.size()):
		var current: String = result[index]
		var cursor := index - 1
		while cursor >= 0 and _sorts_before(current, str(result[cursor])):
			result[cursor + 1] = result[cursor]
			cursor -= 1
		result[cursor + 1] = current
	return result


static func _sorts_before(first: String, second: String) -> bool:
	var rank_first := address_rank(first)
	var rank_second := address_rank(second)
	if rank_first != rank_second:
		return rank_first < rank_second
	return first < second


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
