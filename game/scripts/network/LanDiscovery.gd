## LanDiscovery.gd
## Découverte des parties sur le réseau local, sans serveur ni service externe.
##
## L'hôte diffuse un petit beacon JSON sur le port de découverte ; les clients
## écoutent sur ce même port, distinct du port ENet du match. `poll()` est
## appelé chaque image : aucune boucle bloquante, aucun thread.
class_name LanDiscovery
extends RefCounted

const BROADCAST_ADDRESS: String = "255.255.255.255"
const BEACON_INTERVAL: float = 1.0
## Une annonce disparaît de la liste si elle n'est plus reçue depuis ce délai.
const ENTRY_TTL: float = 3.5
const MAX_ENTRIES: int = 8
## Garde-fou : un pair ne peut pas monopoliser une image avec des paquets.
const MAX_PACKETS_PER_POLL: int = 16

enum Mode { NONE, BROADCAST, LISTEN }

var last_error: String = ""

var _mode: Mode = Mode.NONE
var _socket: PacketPeerUDP = null
var _beacon_text: String = ""
var _until_beacon: float = 0.0
var _clock: float = 0.0
## clé "ip:port" -> { "info": Dictionary, "seen": float }
var _entries: Dictionary = {}


## Diffuse périodiquement l'annonce fournie. Renvoie false si le socket ou
## l'activation du broadcast échoue : le salon reste utilisable en IP manuelle.
func start_broadcast(beacon: Dictionary) -> bool:
	stop()
	if not LanProtocol.validate_beacon(beacon)["ok"]:
		last_error = "Annonce de partie invalide."
		return false
	var socket := PacketPeerUDP.new()
	# Le broadcast UDP n'exige pas de bind local sur le port de découverte.
	socket.set_broadcast_enabled(true)
	var error := socket.set_dest_address(BROADCAST_ADDRESS, LanProtocol.DISCOVERY_PORT)
	if error != OK:
		last_error = "Diffusion indisponible (%s)." % error_string(error)
		return false
	_socket = socket
	_beacon_text = JSON.stringify(beacon)
	_mode = Mode.BROADCAST
	_until_beacon = 0.0
	return true


## Écoute les annonces des hôtes sur le port de découverte.
func start_listening() -> bool:
	stop()
	var socket := PacketPeerUDP.new()
	var error := socket.bind(LanProtocol.DISCOVERY_PORT, "*")
	if error != OK:
		last_error = "Recherche indisponible (%s)." % error_string(error)
		return false
	_socket = socket
	_mode = Mode.LISTEN
	return true


func stop() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	_beacon_text = ""
	_mode = Mode.NONE
	_entries.clear()


func is_active() -> bool:
	return _mode != Mode.NONE


func mode() -> Mode:
	return _mode


## Avance les minuteurs, envoie ou lit les paquets disponibles, puis oublie les
## annonces périmées. Ne bloque jamais et borne le travail par image.
func poll(delta: float) -> void:
	if _socket == null:
		return
	_clock += delta
	if _mode == Mode.BROADCAST:
		_until_beacon -= delta
		if _until_beacon <= 0.0:
			_until_beacon = BEACON_INTERVAL
			_socket.put_packet(_beacon_text.to_utf8_buffer())
	elif _mode == Mode.LISTEN:
		var available := mini(_socket.get_available_packet_count(), MAX_PACKETS_PER_POLL)
		for _index in range(available):
			_read_packet()
	_expire()


func _read_packet() -> void:
	var packet := _socket.get_packet()
	var address := _socket.get_packet_ip()
	if packet.is_empty() or address == "":
		return
	var text := packet.get_string_from_utf8()
	if text.length() == 0 or text.length() > LanProtocol.MAX_MESSAGE_CHARS:
		return
	var parsed: Variant = JSON.parse_string(text)
	if not LanProtocol.validate_beacon(parsed)["ok"]:
		return
	var payload: Dictionary = parsed
	var port := int(payload["port"])
	var info := {
		"address": address,
		"port": port,
		"name": str(payload["name"]),
		"players": int(payload["players"]),
		"app_version": str(payload["app_version"]),
		"compatible": str(payload["app_version"]) == LanProtocol.app_version()
			and str(payload["catalogue"]) == LanProtocol.catalogue_fingerprint(),
	}
	_entries["%s:%d" % [address, port]] = {"info": info, "seen": _clock}
	while _entries.size() > MAX_ENTRIES:
		_forget_oldest()


func _forget_oldest() -> void:
	var oldest_key := ""
	var oldest_seen := INF
	for key in _entries:
		var seen := float(_entries[key]["seen"])
		if seen < oldest_seen:
			oldest_seen = seen
			oldest_key = key
	if oldest_key != "":
		_entries.erase(oldest_key)


func _expire() -> void:
	for key in _entries.keys():
		if _clock - float(_entries[key]["seen"]) > ENTRY_TTL:
			_entries.erase(key)


## Parties découvertes, triées par nom d'hôte. La liste est une copie : le
## contrôleur peut l'afficher sans exposer l'état interne.
func games() -> Array:
	var result: Array = []
	for key in _entries:
		var info: Dictionary = (_entries[key]["info"] as Dictionary).duplicate(true)
		info["key"] = key
		result.append(info)
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return str(first.get("name", "")) < str(second.get("name", "")))
	return result


func game_count() -> int:
	return _entries.size()
