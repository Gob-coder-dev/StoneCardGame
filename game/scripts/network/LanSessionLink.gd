## LanSessionLink.gd
## Relaie la façade de transport vers l'autoload `LanSession`.
##
## Ce fichier est la seule passerelle entre les coordinateurs et ENet : aucun
## coordinateur n'appelle directement `multiplayer` ni `rpc`.
class_name LanSessionLink
extends LanTransportLink

var _session: Node = null


func attach(session: Node) -> void:
	detach()
	if session == null:
		return
	_session = session
	if not session.message_received.is_connected(_on_message):
		session.message_received.connect(_on_message)
	if not session.peer_joined.is_connected(_on_peer_joined):
		session.peer_joined.connect(_on_peer_joined)
	if not session.peer_left.is_connected(_on_peer_left):
		session.peer_left.connect(_on_peer_left)
	if session.has_signal("connected_to_host") and not session.connected_to_host.is_connected(_on_connected):
		session.connected_to_host.connect(_on_connected)


func detach() -> void:
	if not is_instance_valid(_session):
		_session = null
		return
	if _session.message_received.is_connected(_on_message):
		_session.message_received.disconnect(_on_message)
	if _session.peer_joined.is_connected(_on_peer_joined):
		_session.peer_joined.disconnect(_on_peer_joined)
	if _session.peer_left.is_connected(_on_peer_left):
		_session.peer_left.disconnect(_on_peer_left)
	if _session.has_signal("connected_to_host") and _session.connected_to_host.is_connected(_on_connected):
		_session.connected_to_host.disconnect(_on_connected)
	_session = null


func is_attached() -> bool:
	return is_instance_valid(_session)


func send_to(peer_id: int, kind: String, payload: Dictionary) -> bool:
	if not is_instance_valid(_session):
		return false
	return _session.send_to(peer_id, kind, payload)


func broadcast(kind: String, payload: Dictionary) -> bool:
	if not is_instance_valid(_session):
		return false
	return _session.broadcast(kind, payload)


func local_peer_id() -> int:
	if not is_instance_valid(_session):
		return 0
	return _session.local_peer_id()


func is_online() -> bool:
	return is_instance_valid(_session) and _session.is_online()


func _on_message(from_peer: int, kind: String, payload: Dictionary) -> void:
	message_received.emit(from_peer, kind, payload)


func _on_peer_joined(peer_id: int) -> void:
	peer_joined.emit(peer_id)


func _on_peer_left(peer_id: int) -> void:
	peer_left.emit(peer_id)


func _on_connected() -> void:
	connected_to_host.emit()
