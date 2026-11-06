## Possède la présence PVP persistante indépendamment des données de match.
## Elle survit aux changements de scène jusqu'à la fermeture réelle du salon.
class_name PvpPresenceSession
extends RefCounted

var value: LanPvpPresence = null


func adopt(presence: RefCounted) -> void:
	if presence == value:
		return
	close()
	value = presence as LanPvpPresence


func ensure(link: RefCounted, remote_peer: int) -> LanPvpPresence:
	if value != null and value.is_for(link as LanTransportLink, remote_peer):
		return value
	close()
	value = LanPvpPresence.new()
	value.attach(link as LanTransportLink, remote_peer)
	return value


func set_local(presence_value: String) -> bool:
	return value != null and value.set_local(presence_value)


func close() -> void:
	if value != null:
		value.close()
	value = null
