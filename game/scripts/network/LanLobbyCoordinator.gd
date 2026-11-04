## LanLobbyCoordinator.gd
## Poignée de main et préparation du salon PVP local.
##
## L'hôte valide la version, le catalogue, le pseudo, le dieu et le deck du
## client avec `DeckRules`. Il attribue les camps (hôte = PLAYER_ONE, client =
## PLAYER_TWO), exige PRÊT des deux côtés, puis génère la configuration
## autoritaire : match_id, graine, cases bloquées, premier joueur, participants.
## Aucun bouton, aucune scène, aucune règle de combat ici.
class_name LanLobbyCoordinator
extends RefCounted

const STATUS_HOSTING: String = "hosting"
const STATUS_CONNECTED: String = "connected"
const STATUS_READY: String = "ready"
const STATUS_BOTH_READY: String = "both_ready"
const STATUS_ERROR: String = "error"

const UNKNOWN_NAME: String = "En attente"
const INVALID_DECK_MESSAGE: String = "Deck incomplet ou invalide."
const FULL_MESSAGE: String = "Partie complète."

signal state_changed(state: Dictionary)
signal match_started(config: Dictionary)
signal failed(message: String)

var _transport: LanTransportLink = null
var _is_host := false
var _local_peer := 0
var _host_peer := LanProtocol.SERVER_ID
var _client_peer := 0
var _accepted_peer := 0
var _connected := false
var _started := false
var _status := STATUS_HOSTING
var _error := ""
var _match_id := ""
var _local: Dictionary = _empty_profile()
var _remote: Dictionary = _empty_profile()


static func _empty_profile() -> Dictionary:
	return {
		"name": UNKNOWN_NAME,
		"god_id": "",
		"deck": [],
		"deck_valid": false,
		"ready": false,
	}


## Branche le coordinateur sur un transport. `client_peer` n'est connu que de
## l'hôte, après la connexion ENet.
func attach(transport: LanTransportLink, is_host: bool, client_peer: int = 0) -> void:
	close()
	_transport = transport
	_is_host = is_host
	_client_peer = client_peer
	_local_peer = transport.local_peer_id()
	transport.message_received.connect(_on_message)
	transport.peer_joined.connect(_on_peer_joined)
	transport.peer_left.connect(_on_peer_left)
	transport.connected_to_host.connect(_on_connected_to_host)


func close() -> void:
	if _transport == null:
		return
	if _transport.message_received.is_connected(_on_message):
		_transport.message_received.disconnect(_on_message)
	if _transport.peer_joined.is_connected(_on_peer_joined):
		_transport.peer_joined.disconnect(_on_peer_joined)
	if _transport.peer_left.is_connected(_on_peer_left):
		_transport.peer_left.disconnect(_on_peer_left)
	if _transport.connected_to_host.is_connected(_on_connected_to_host):
		_transport.connected_to_host.disconnect(_on_connected_to_host)
	_transport = null


## Profil local annoncé au pair. Le deck est validé ici avec la règle unique.
func set_local_profile(player_name: String, god_id: String, deck: Array) -> void:
	_local["name"] = player_name.strip_edges()
	_local["god_id"] = god_id
	_local["deck"] = deck.duplicate()
	_local["deck_valid"] = DeckRules.is_deck_valid(deck, god_id)
	_publish()


func is_ready_local() -> bool:
	return bool(_local["ready"])


func press_ready() -> bool:
	if _started or not _connected:
		return false
	if not bool(_local["deck_valid"]):
		_error = INVALID_DECK_MESSAGE
		_status = STATUS_ERROR
		_publish()
		failed.emit(INVALID_DECK_MESSAGE)
		return false
	_local["ready"] = true
	if _is_host:
		_publish()
		_broadcast_lobby()
		_maybe_start()
	else:
		_transport.send_to(_host_peer, LanProtocol.KIND_READY, {"ready": true})
		_publish()
	return true


## Le client envoie sa poignée de main dès que le serveur ENet l'a accepté.
func client_connected() -> void:
	if _is_host:
		return
	_connected = true
	_status = STATUS_CONNECTED
	var hello := LanProtocol.identity_fields()
	hello.merge({
		"name": str(_local["name"]),
		"god_id": str(_local["god_id"]),
		"deck": (_local["deck"] as Array).duplicate(),
	})
	if not _transport.send_to(_host_peer, LanProtocol.KIND_HELLO, hello):
		_fail("Connexion impossible.")
		return
	_publish()


func state() -> Dictionary:
	var host := _local if _is_host else _remote
	var client := _remote if _is_host else _local
	return {
		"status": _status,
		"error": _error,
		"started": _started,
		"is_host": _is_host,
		"local_side": GameState.PLAYER_ONE if _is_host else GameState.PLAYER_TWO,
		"both_ready": bool(_local["ready"]) and bool(_remote["ready"]),
		"can_ready": _connected and bool(_local["deck_valid"]) and not _started,
		"host": (host as Dictionary).duplicate(true),
		"client": (client as Dictionary).duplicate(true),
	}


func host_summary() -> Dictionary:
	return (_local if _is_host else _remote).duplicate(true)


func client_summary() -> Dictionary:
	return (_remote if _is_host else _local).duplicate(true)


## ─── Réception ───────────────────────────────────────────────────────────────

func _on_message(from_peer: int, kind: String, payload: Dictionary) -> void:
	if _started and kind != LanProtocol.KIND_HELLO_REJECT:
		return
	if from_peer <= 0:
		return
	match kind:
		LanProtocol.KIND_HELLO:
			if _is_host:
				_on_hello(from_peer, payload)
		LanProtocol.KIND_HELLO_ACK:
			if not _is_host:
				_on_hello_ack(from_peer, payload)
		LanProtocol.KIND_HELLO_REJECT:
			_on_hello_reject(payload)
		LanProtocol.KIND_LOBBY_STATE:
			if not _is_host and from_peer == _host_peer:
				_on_lobby_state(payload)
		LanProtocol.KIND_READY:
			if _is_host and from_peer == _client_peer:
				_on_remote_ready(payload)
		LanProtocol.KIND_MATCH_START:
			if not _is_host and from_peer == _host_peer:
				_on_match_start(payload)
		_:
			pass


func _on_peer_joined(peer_id: int) -> void:
	if not _is_host:
		return
	if _client_peer != 0 and peer_id != _client_peer:
		return
	_client_peer = peer_id
	_connected = true
	_status = STATUS_CONNECTED
	_error = ""
	_publish()


func _on_connected_to_host() -> void:
	client_connected()


func _on_peer_left(peer_id: int) -> void:
	if not _is_host or (_client_peer != 0 and peer_id != _client_peer):
		return
	_client_peer = 0
	_accepted_peer = 0
	_connected = false
	_remote = _empty_profile()
	_local["ready"] = false
	# Un départ n'est pas une panne du salon : l'hôte reste disponible pour
	# un autre adversaire et le motif n'est qu'une information.
	_status = STATUS_HOSTING
	_error = ""
	_publish()
	if not _started:
		failed.emit("L'adversaire a quitté le salon.")


## ─── Hôte ────────────────────────────────────────────────────────────────────

func _on_hello(from_peer: int, payload: Dictionary) -> void:
	if _accepted_peer != 0 and from_peer != _accepted_peer:
		_reject(from_peer, FULL_MESSAGE)
		return
	var problem := LanProtocol.compatibility_problem(payload)
	if problem != "":
		_reject(from_peer, problem)
		return
	var god_id := str(payload.get("god_id", ""))
	var deck: Array = (payload.get("deck", []) as Array).duplicate()
	if not DeckRules.is_deck_valid(deck, god_id):
		_reject(from_peer, INVALID_DECK_MESSAGE)
		return
	_remote = {
		"name": str(payload.get("name", UNKNOWN_NAME)),
		"god_id": god_id,
		"deck": deck,
		"deck_valid": true,
		"ready": false,
	}
	_client_peer = from_peer
	_accepted_peer = from_peer
	_connected = true
	_error = ""
	_status = STATUS_CONNECTED
	var ack := LanProtocol.identity_fields()
	ack.merge({
		"name": str(_local["name"]),
		"god_id": str(_local["god_id"]),
		"you_are": GameState.PLAYER_TWO,
	})
	_transport.send_to(from_peer, LanProtocol.KIND_HELLO_ACK, ack)
	_publish()
	_broadcast_lobby()


func _reject(peer_id: int, reason: String) -> void:
	# Refuser un troisième appareil ne doit jamais interrompre le salon en cours.
	if peer_id > 0:
		_transport.send_to(peer_id, LanProtocol.KIND_HELLO_REJECT, {"reason": reason})


func _on_remote_ready(payload: Dictionary) -> void:
	_remote["ready"] = bool(payload.get("ready", false))
	_status = STATUS_BOTH_READY if state()["both_ready"] else STATUS_CONNECTED
	_publish()
	_broadcast_lobby()
	_maybe_start()


func _broadcast_lobby() -> void:
	if not _is_host or _transport == null:
		return
	var host := _summary(_local)
	var client := _summary(_remote)
	var payload := {"host": host, "client": client, "status": _status}
	_transport.broadcast(LanProtocol.KIND_LOBBY_STATE, payload)


static func _summary(profile: Dictionary) -> Dictionary:
	return {
		"name": str(profile["name"]),
		"god_id": str(profile["god_id"]),
		"deck_valid": bool(profile["deck_valid"]),
		"ready": bool(profile["ready"]),
	}


func _maybe_start() -> void:
	if not _is_host or _started:
		return
	if _accepted_peer == 0 or _client_peer == 0:
		return
	if not bool(_local["ready"]) or not bool(_remote["ready"]):
		return
	if not bool(_local["deck_valid"]) or not bool(_remote["deck_valid"]):
		return
	var config := _build_config()
	if not LanProtocol.validate(LanProtocol.KIND_MATCH_START, config)["ok"]:
		_fail("Configuration de partie invalide.")
		return
	_started = true
	_status = STATUS_BOTH_READY
	_transport.broadcast(LanProtocol.KIND_MATCH_START, config)
	_publish()
	match_started.emit(config)


## L'hôte est le seul à tirer la graine, le terrain et le premier joueur.
func _build_config() -> Dictionary:
	_match_id = "%d-%d" % [Time.get_ticks_usec(), _local_peer]
	return {
		"match_id": _match_id,
		"seed": randi(),
		"blocked_cells": BoardSetupGenerator.generate(),
		"starting_player": BoardSetupGenerator.draw_first_player(),
		"participants": [
			{
				"peer_id": _local_peer,
				"side": GameState.PLAYER_ONE,
				"name": str(_local["name"]),
				"god_id": str(_local["god_id"]),
				"deck": (_local["deck"] as Array).duplicate(),
			},
			{
				"peer_id": _client_peer,
				"side": GameState.PLAYER_TWO,
				"name": str(_remote["name"]),
				"god_id": str(_remote["god_id"]),
				"deck": (_remote["deck"] as Array).duplicate(),
			},
		],
	}


## ─── Client ──────────────────────────────────────────────────────────────────

func _on_hello_ack(from_peer: int, payload: Dictionary) -> void:
	if from_peer != _host_peer:
		return
	var problem := LanProtocol.compatibility_problem(payload)
	if problem != "":
		_fail(problem)
		return
	_remote = {
		"name": str(payload.get("name", UNKNOWN_NAME)),
		"god_id": str(payload.get("god_id", "")),
		"deck": [],
		"deck_valid": true,
		"ready": false,
	}
	_connected = true
	_error = ""
	_status = STATUS_CONNECTED
	_publish()


func _on_hello_reject(payload: Dictionary) -> void:
	_fail(str(payload.get("reason", "Connexion refusée.")))


func _on_lobby_state(payload: Dictionary) -> void:
	var host: Dictionary = payload.get("host", {})
	var client: Dictionary = payload.get("client", {})
	_remote = {
		"name": str(host.get("name", UNKNOWN_NAME)),
		"god_id": str(host.get("god_id", "")),
		"deck": (_remote.get("deck", []) as Array).duplicate(),
		"deck_valid": bool(host.get("deck_valid", false)),
		"ready": bool(host.get("ready", false)),
	}
	_local["deck_valid"] = bool(client.get("deck_valid", _local["deck_valid"]))
	_local["ready"] = bool(client.get("ready", _local["ready"]))
	_status = str(payload.get("status", STATUS_CONNECTED))
	_publish()


func _on_match_start(payload: Dictionary) -> void:
	if not LanProtocol.validate(LanProtocol.KIND_MATCH_START, payload)["ok"]:
		_fail("Configuration de partie invalide.")
		return
	var own_peer := _local_peer
	var host_entry := {}
	var own_entry := {}
	for entry in payload.get("participants", []):
		var participant: Dictionary = entry
		if int(participant.get("peer_id", 0)) == own_peer:
			own_entry = participant
		if int(participant.get("side", 0)) == GameState.PLAYER_ONE:
			host_entry = participant
	if own_entry.is_empty() or int(own_entry.get("side", 0)) != GameState.PLAYER_TWO:
		_fail("Configuration de partie invalide.")
		return
	if host_entry.is_empty() or int(host_entry.get("peer_id", 0)) == own_peer:
		_fail("Configuration de partie invalide.")
		return
	if not DeckRules.is_deck_valid(own_entry.get("deck", []), str(own_entry.get("god_id", ""))):
		_fail(INVALID_DECK_MESSAGE)
		return
	_match_id = str(payload.get("match_id", ""))
	_started = true
	_status = STATUS_BOTH_READY
	_publish()
	match_started.emit(payload)


## ─── Erreurs ─────────────────────────────────────────────────────────────────

func _fail(message: String) -> void:
	_error = message
	_status = STATUS_ERROR
	_publish()
	failed.emit(message)


func _publish() -> void:
	state_changed.emit(state())
