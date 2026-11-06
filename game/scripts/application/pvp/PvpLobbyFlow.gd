## Orchestration du salon PVP, indépendante de la scène.
##
## Service applicatif possédant le cycle découverte/session/coordinateur. Le contrôleur
## Godot ne fait plus que traduire ses signaux en affichage et lui transmettre
## les actions des boutons.
class_name PvpLobbyFlow
extends RefCounted

const LobbyCoordinatorModel := preload("res://scripts/network/LanLobbyCoordinator.gd")
const DiscoveryModel := preload("res://scripts/network/LanDiscovery.gd")
const SessionLinkModel := preload("res://scripts/network/LanSessionLink.gd")
const AddressResolver := preload("res://scripts/network/LanAddressResolver.gd")

const MODE_NONE := ""
const MODE_HOST := "hosting"
const MODE_JOIN := "joining"

signal changed
signal games_changed(games: Array)
signal notice_requested(message: String)
signal match_started(config: Dictionary)
signal series_ready(rules: Dictionary)
signal series_updated(state: Dictionary)

var mode := MODE_NONE
var discovery: LanDiscovery = null
var link: LanSessionLink = null
var lobby: LanLobbyCoordinator = null
var connection_attempt_pending := false
var attempted_address := ""
var attempted_host_name := ""
var connection_elapsed := 0.0
var displayed_connection_seconds := -1

var _games_signature := ""


func poll(delta: float) -> void:
	if discovery == null or not discovery.is_active():
		return
	discovery.poll(delta)
	if mode != MODE_JOIN or lobby != null:
		return
	var games := discovery.games()
	var signature := ""
	for game in games:
		signature += "%s|%s|%s;" % [game.get("key", ""), game.get("name", ""),
			str(game.get("compatible", false))]
	if signature == _games_signature:
		return
	_games_signature = signature
	games_changed.emit(games)


func start_hosting(player_name: String, god_id: String, deck: Array) -> bool:
	stop_discovery()
	close_lobby()
	PvpMatchContext.close_presence()
	LanSession.reset()
	mode = MODE_HOST
	if not LanSession.host_game():
		mode = MODE_NONE
		notice_requested.emit(LanSession.last_notice)
		changed.emit()
		return false
	link = SessionLinkModel.new()
	link.attach(LanSession)
	lobby = LobbyCoordinatorModel.new()
	lobby.attach(link, true)
	_connect_lobby()
	lobby.set_local_profile(player_name, god_id, deck)
	var discovery_problem := _start_broadcast(player_name)
	notice_requested.emit(discovery_problem)
	changed.emit()
	return true


func start_search() -> bool:
	if mode == MODE_JOIN and discovery != null and discovery.is_active():
		return true
	stop_discovery()
	close_lobby()
	PvpMatchContext.close_presence()
	LanSession.reset()
	mode = MODE_JOIN
	discovery = DiscoveryModel.new()
	if not discovery.start_listening():
		var reason := discovery.last_error
		discovery = null
		notice_requested.emit(reason)
		changed.emit()
		return false
	LanSession.enter_discovery()
	_games_signature = ""
	games_changed.emit([])
	notice_requested.emit("")
	changed.emit()
	return true


func restart_search(notice: String = "") -> bool:
	if mode != MODE_JOIN or lobby != null:
		return false
	stop_discovery()
	discovery = DiscoveryModel.new()
	if not discovery.start_listening():
		var reason := discovery.last_error
		discovery = null
		notice_requested.emit("%s %s" % [notice, reason] if notice != "" else reason)
		changed.emit()
		return false
	LanSession.enter_discovery()
	_games_signature = ""
	games_changed.emit([])
	notice_requested.emit(notice)
	changed.emit()
	return true


func join_address(address: String, host_name: String = "") -> bool:
	var host := AddressResolver.host_only(address)
	if host == "":
		notice_requested.emit("Entrez l'adresse affichée sur la salle d'attente de l'hôte.")
		return false
	stop_discovery()
	close_lobby()
	PvpMatchContext.close_presence()
	LanSession.reset()
	mode = MODE_JOIN
	attempted_address = address.strip_edges()
	attempted_host_name = host_name.strip_edges()
	connection_attempt_pending = true
	connection_elapsed = 0.0
	displayed_connection_seconds = -1
	LanSession.last_notice = ""
	var started := LanSession.join_game(host)
	changed.emit()
	return started


## Reprend un salon déjà connecté après un retour coordonné. Le lien ENet est
## conservé ; aucun hello, aucune découverte et aucun reset de session.
func resume_session(data: Dictionary) -> bool:
	stop_discovery()
	close_lobby()
	var kept_link = data.get("link", null)
	if kept_link == null or not kept_link is LanSessionLink or not kept_link.is_attached():
		return false
	var is_host := bool(data.get("is_host", false))
	mode = MODE_HOST if is_host else MODE_JOIN
	link = kept_link
	var client_peer := int(data.get("client_peer", 0))
	lobby = LobbyCoordinatorModel.new()
	var presence: LanPvpPresence = PvpMatchContext.presence as LanPvpPresence
	lobby.attach(link, is_host, client_peer, presence)
	_connect_lobby()
	lobby.resume(data.get("local", {}), data.get("remote", {}),
		data.get("rules", {}), client_peer)
	changed.emit()
	return true


func connected_to_host(player_name: String, god_id: String, deck: Array) -> void:
	if mode != MODE_JOIN or lobby != null:
		return
	connection_attempt_pending = false
	link = SessionLinkModel.new()
	link.attach(LanSession)
	lobby = LobbyCoordinatorModel.new()
	lobby.attach(link, false)
	_connect_lobby()
	lobby.set_local_profile(player_name, god_id, deck)
	lobby.client_connected()
	changed.emit()


func press_ready() -> bool:
	if lobby == null:
		return false
	var accepted := lobby.press_ready()
	changed.emit()
	return accepted


func handle_session_state(session_state: int) -> bool:
	if session_state != LanSession.State.DISCONNECTED or mode != MODE_JOIN or lobby == null:
		changed.emit()
		return false
	var message := LanSession.last_notice
	if message == "":
		message = "L'hôte a quitté le salon."
	close_lobby()
	connection_attempt_pending = false
	LanSession.last_notice = ""
	restart_search(message)
	return true


func dismiss_connection() -> void:
	if not connection_attempt_pending:
		return
	connection_attempt_pending = false
	connection_elapsed = 0.0
	stop_discovery()
	LanSession.reset()
	LanSession.last_notice = ""
	notice_requested.emit("")
	restart_search()


func reset() -> void:
	stop_discovery()
	close_lobby()
	LanSession.reset()
	PvpMatchContext.close_presence()
	PvpMatchContext.clear()
	mode = MODE_NONE
	connection_attempt_pending = false
	attempted_address = ""
	attempted_host_name = ""
	_games_signature = ""
	games_changed.emit([])
	changed.emit()


func stop_discovery() -> void:
	if discovery != null:
		discovery.stop()
		discovery = null
	_games_signature = ""


func close_lobby() -> void:
	if lobby != null:
		lobby.close()
		lobby = null
	if link != null:
		link.detach()
		link = null


func close() -> void:
	stop_discovery()
	close_lobby()


func _start_broadcast(player_name: String) -> String:
	discovery = DiscoveryModel.new()
	var beacon := LanProtocol.make_beacon(player_name, LanProtocol.GAME_PORT, 1)
	if not discovery.start_broadcast(beacon):
		var reason := discovery.last_error
		discovery = null
		return "%s Votre adversaire peut entrer votre adresse à la main." % reason
	return ""


func _connect_lobby() -> void:
	lobby.state_changed.connect(_on_lobby_state)
	lobby.match_started.connect(_on_match_started)
	lobby.series_ready.connect(_on_series_ready)
	lobby.series_updated.connect(_on_series_updated)
	lobby.failed.connect(_on_lobby_failed)


## Le salon est démonté, mais le lien et le coordinateur de série restent
## vivants pour la manche et l'écran de résultat. Le contexte les conserve.
func release_for_series() -> LanSessionLink:
	if lobby != null:
		lobby.detach_network()
		lobby = null
	var kept := link
	link = null
	return kept


func _on_lobby_state(_state: Dictionary) -> void:
	changed.emit()


func _on_match_started(config: Dictionary) -> void:
	match_started.emit(config)


func _on_series_ready(rules: Dictionary) -> void:
	series_ready.emit(rules)


func _on_series_updated(state: Dictionary) -> void:
	series_updated.emit(state)


func _on_lobby_failed(message: String) -> void:
	notice_requested.emit(message)
