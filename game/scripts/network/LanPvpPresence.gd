## LanPvpPresence.gd
## Présence PVP indépendante de la scène : chaque camp annonce uniquement son
## écran courant. Un message de présence ne déclenche jamais la navigation du
## pair ; il sert au salon à afficher PRÊT / PAS PRÊT / EN PARTIE et à bloquer
## un démarrage tant que l'autre joueur n'est pas revenu.
class_name LanPvpPresence
extends RefCounted

const LOBBY := "lobby"
const PREPARATION := "preparation"
const PRE_BATTLE := "pre_battle"
const IN_MATCH := "in_match"
const RESULT := "result"

signal changed(local_presence: String, remote_presence: String)
signal remote_changed(remote_presence: String)
signal both_in_lobby_reached

var _link: LanTransportLink = null
var _remote_peer := 0
var _local := ""
var _remote := ""


func attach(link: LanTransportLink, remote_peer: int) -> void:
	close()
	_link = link
	_remote_peer = remote_peer
	if _link != null and not _link.message_received.is_connected(_on_message):
		_link.message_received.connect(_on_message)


func set_local(presence: String) -> bool:
	if not LanProtocol.PRESENCES.has(presence):
		return false
	_local = presence
	if _link != null and _remote_peer > 0:
		_link.send_to(_remote_peer, LanProtocol.KIND_PVP_PRESENCE, {"presence": presence})
	_emit()
	return true


func local_presence() -> String:
	return _local


func remote_presence() -> String:
	return _remote


func is_attached() -> bool:
	return _link != null and _link.is_online()


func is_for(link: LanTransportLink, remote_peer: int) -> bool:
	return _link == link and _remote_peer == remote_peer


func both_in_lobby() -> bool:
	return _local == LOBBY and _remote == LOBBY


func close() -> void:
	if _link != null and _link.message_received.is_connected(_on_message):
		_link.message_received.disconnect(_on_message)
	_link = null
	_remote_peer = 0
	_local = ""
	_remote = ""


func _on_message(from_peer: int, kind: String, payload: Dictionary) -> void:
	if _link == null or from_peer != _remote_peer:
		return
	if kind != LanProtocol.KIND_PVP_PRESENCE:
		return
	if not LanProtocol.validate(kind, payload)["ok"]:
		return
	var presence := str(payload.get("presence", ""))
	if not LanProtocol.PRESENCES.has(presence):
		return
	if _remote == presence:
		return
	_remote = presence
	remote_changed.emit(_remote)
	_emit()


func _emit() -> void:
	changed.emit(_local, _remote)
	if _local == LOBBY and _remote == LOBBY:
		both_in_lobby_reached.emit()
