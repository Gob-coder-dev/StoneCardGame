## LanSession.gd — AutoLoad
## Cycle de vie réseau du mode PVP local : un hôte, un client, aucun serveur
## Internet. Il ne contient aucune règle de jeu, aucune scène et aucun bouton.
##
## Les RPC sont déclarés sur ce nœud dont le chemin est stable sur les deux
## appareils (`/root/LanSession`). Tous les messages passent par
## `LanProtocol.validate()` et l'expéditeur est toujours vérifié.
extends Node

## État explicite du cycle réseau, lisible par l'interface du salon.
enum State { IDLE, DISCOVERING, HOSTING, CONNECTING, LOBBY, IN_MATCH, DISCONNECTED }

signal state_changed(state: int)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## Le client vient d'être accepté par le serveur ENet (la poignée de main reste
## à faire par le salon).
signal connected_to_host()
## Message lisible à afficher, jamais un détail réseau brut.
signal notice(message: String)
## Message déjà validé, transmis au coordinateur concerné.
signal message_received(from_peer: int, kind: String, payload: Dictionary)

const CONNECT_TIMEOUT: float = 12.0
const LOBBY_TIMEOUT: float = 120.0

var state: State = State.IDLE
## Dernier message destiné au joueur. Conservé à la fermeture pour que l'écran
## suivant puisse expliquer pourquoi la session s'est arrêtée.
var last_notice: String = ""

var _peer: ENetMultiplayerPeer = null
var _timer: Timer = null
var _closing := false


func _ready() -> void:
	_timer = Timer.new()
	_timer.name = "Timeout"
	_timer.one_shot = true
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	reset()


## ─── Cycle de vie ────────────────────────────────────────────────────────────

func host_game() -> bool:
	reset()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(LanProtocol.GAME_PORT, LanProtocol.MAX_PARTICIPANTS - 1)
	if error != OK:
		_notice("Impossible d'ouvrir le salon sur le réseau local.")
		_set_state(State.DISCONNECTED)
		return false
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_set_state(State.HOSTING)
	_timer.start(LOBBY_TIMEOUT)
	return true


func join_game(address: String) -> bool:
	reset()
	var clean := address.strip_edges()
	if clean == "":
		_notice("Adresse IP manquante.")
		return false
	if clean == "localhost":
		clean = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(clean, LanProtocol.GAME_PORT)
	if error != OK:
		_notice("Connexion impossible à %s." % clean)
		_set_state(State.DISCONNECTED)
		return false
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_set_state(State.CONNECTING)
	_timer.start(CONNECT_TIMEOUT)
	return true


func enter_discovery() -> void:
	_set_state(State.DISCOVERING)


func enter_lobby() -> void:
	_set_state(State.LOBBY)


## La partie commence : les délais de salon ne doivent plus fermer la session.
func enter_match() -> void:
	_timer.stop()
	_set_state(State.IN_MATCH)


## Fermeture idempotente : sockets, minuteur et MultiplayerPeer reviennent à
## l'état hors ligne. Peut être appelée plusieurs fois sans effet de bord.
func reset() -> void:
	if _closing:
		return
	_close_peer()
	_set_state(State.IDLE)


## Ferme uniquement les ressources réseau, sans changer l'état affiché : les
## échecs de connexion gardent DISCONNECTED pour que l'interface l'explique.
func _close_peer() -> void:
	if _closing:
		return
	_closing = true
	if _timer != null:
		_timer.stop()
	if _peer != null:
		_peer.close()
	_peer = null
	var offline := OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = offline
	_closing = false


func is_online() -> bool:
	return state == State.HOSTING or state == State.LOBBY or state == State.IN_MATCH \
		or state == State.CONNECTING


func is_host() -> bool:
	return multiplayer.is_server() and _peer != null


func local_peer_id() -> int:
	return multiplayer.get_unique_id() if _peer != null else 0


func peer_ids() -> Array:
	return Array(multiplayer.get_peers()) if _peer != null else []


func leave_with_notice(message: String) -> void:
	last_notice = message
	reset()


## ─── Envoi ───────────────────────────────────────────────────────────────────

func send_to(peer_id: int, kind: String, payload: Dictionary) -> bool:
	if _peer == null or peer_id <= 0:
		return false
	if not LanProtocol.validate(kind, payload)["ok"]:
		push_error("LanSession: message refusé avant envoi (%s)." % kind)
		return false
	_receive.rpc_id(peer_id, kind, payload)
	return true


func broadcast(kind: String, payload: Dictionary) -> bool:
	if _peer == null:
		return false
	if not LanProtocol.validate(kind, payload)["ok"]:
		push_error("LanSession: message refusé avant envoi (%s)." % kind)
		return false
	_receive.rpc(kind, payload)
	return true


## ─── Réception ───────────────────────────────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable", 1)
func _receive(kind: String, payload: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _is_known_peer(sender):
		# Un pair inconnu ne peut rien déclencher, même avec un message valide.
		return
	var check := LanProtocol.validate(kind, payload)
	if not check["ok"]:
		notice.emit("Message réseau refusé : %s" % str(check["reason"]))
		return
	message_received.emit(sender, kind, payload)


## Seul le serveur est joignable côté client ; côté hôte, seuls les pairs
## réellement connectés par ENet sont acceptés.
func _is_known_peer(sender: int) -> bool:
	if sender <= 0:
		return false
	if multiplayer.is_server():
		return multiplayer.get_peers().has(sender)
	return sender == LanProtocol.SERVER_ID


## ─── Rappels MultiplayerAPI ──────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	if _peer == null:
		return
	last_notice = ""
	_set_state(State.LOBBY)
	_timer.start(LOBBY_TIMEOUT)
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if _peer == null:
		return
	if state == State.IN_MATCH:
		last_notice = "L'adversaire a quitté la partie."
		_set_state(State.DISCONNECTED)
	else:
		if multiplayer.is_server():
			last_notice = "L'adversaire a quitté le salon."
			# Le serveur reste ouvert pour accueillir un autre adversaire.
			_set_state(State.HOSTING)
		else:
			last_notice = "L'hôte a quitté le salon."
			_set_state(State.DISCONNECTED)
	peer_left.emit(peer_id)


func _on_connected_to_server() -> void:
	if _peer == null:
		return
	_timer.stop()
	last_notice = ""
	_set_state(State.LOBBY)
	connected_to_host.emit()


func _on_connection_failed() -> void:
	if _peer == null or state != State.CONNECTING:
		return
	last_notice = "Connexion impossible : adresse ou hôte indisponible."
	_close_peer()
	_set_state(State.DISCONNECTED)


func _on_server_disconnected() -> void:
	if _peer == null:
		return
	last_notice = "L'hôte a quitté la partie." if state == State.IN_MATCH \
		else "L'hôte a quitté le salon."
	_close_peer()
	_set_state(State.DISCONNECTED)


func _on_timeout() -> void:
	match state:
		State.CONNECTING:
			last_notice = "Délai de connexion dépassé."
			_close_peer()
			_set_state(State.DISCONNECTED)
		State.HOSTING, State.LOBBY:
			last_notice = "Salon expiré : aucun adversaire."
			_close_peer()
			_set_state(State.DISCONNECTED)
		_:
			pass


func _set_state(value: State) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(state)


func _notice(message: String) -> void:
	last_notice = message
	notice.emit(message)


func _exit_tree() -> void:
	reset()
