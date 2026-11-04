## Transport mémoire pour les tests : aucune socket, aucun Wi-Fi.
## Il valide chaque envoi comme `LanSession` le fait, délivre les messages au
## pair simulé et permet d'injecter un paquet brut (`push`) comme le ferait un
## appareil mal intentionné.
extends "res://scripts/network/LanTransportLink.gd"

var local_id: int = 1
## Lien faible : deux transports qui se référencent fortement formeraient un
## cycle `RefCounted` et resteraient en mémoire après la fin du test.
var remote: LanTransportLink:
	set(value):
		_remote = weakref(value) if value != null else null
	get:
		return _remote.get_ref() if _remote != null else null
var sent: Array = []
var online: bool = true

var _remote: WeakRef = null


func send_to(peer_id: int, kind: String, payload: Dictionary) -> bool:
	if not online or not LanProtocol.validate(kind, payload)["ok"]:
		return false
	sent.append({"to": peer_id, "kind": kind, "payload": payload.duplicate(true)})
	return _deliver(local_id, kind, payload)


func broadcast(kind: String, payload: Dictionary) -> bool:
	if not online or not LanProtocol.validate(kind, payload)["ok"]:
		return false
	sent.append({"to": 0, "kind": kind, "payload": payload.duplicate(true)})
	return _deliver(local_id, kind, payload)


## Paquet forcé : contourne la validation de l'émetteur simulé et arrive sur
## l'appareil d'en face, comme un message reçu de `from_peer`.
func push(from_peer: int, kind: String, payload: Dictionary) -> void:
	_deliver(from_peer, kind, payload)


func local_peer_id() -> int:
	return local_id


func is_online() -> bool:
	return online


func sent_of(kind: String) -> Array:
	var result: Array = []
	for message in sent:
		if str(message["kind"]) == kind:
			result.append(message)
	return result


func last_sent() -> Dictionary:
	return sent[-1] if not sent.is_empty() else {}


func clear_sent() -> void:
	sent.clear()


func _deliver(from_peer: int, kind: String, payload: Dictionary) -> bool:
	var target := remote
	if not online or target == null:
		return false
	target.message_received.emit(from_peer, kind, payload.duplicate(true))
	return true
