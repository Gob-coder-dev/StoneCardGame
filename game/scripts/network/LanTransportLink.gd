## LanTransportLink.gd
## Contrat minimal entre les coordinateurs réseau et un transport concret.
##
## Les coordinateurs ne connaissent ni ENet ni RPC : ils reçoivent des messages
## validés et renvoient des messages par cette façade. Les tests fournissent une
## implémentation en mémoire ; le jeu fournit `LanSessionLink`, qui relaie les
## RPC fiables et ordonnés de `LanSession`.
class_name LanTransportLink
extends RefCounted

## Contrat de signaux : ils sont émis par LanSessionLink et FakeLanTransport,
## puis consommés par les coordinateurs ; le compilateur n'analyse que cette base.
@warning_ignore("unused_signal")
signal message_received(from_peer: int, kind: String, payload: Dictionary)
@warning_ignore("unused_signal")
signal peer_joined(peer_id: int)
@warning_ignore("unused_signal")
signal peer_left(peer_id: int)
@warning_ignore("unused_signal")
signal connected_to_host()


func send_to(_peer_id: int, _kind: String, _payload: Dictionary) -> bool:
	return false


func broadcast(_kind: String, _payload: Dictionary) -> bool:
	return false


func local_peer_id() -> int:
	return 0


func is_online() -> bool:
	return false
