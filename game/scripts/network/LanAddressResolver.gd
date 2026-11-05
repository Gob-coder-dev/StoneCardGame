## Normalisation et classement des adresses proposées par le salon local.
## Aucune scène ni socket ici : ces fonctions pures sont testables isolément.
class_name LanAddressResolver
extends RefCounted


## Accepte une IPv4 avec port, une URL copiée ou une IPv6 entre crochets.
static func host_only(address: String) -> String:
	var clean := address.strip_edges()
	if clean.contains("://"):
		clean = clean.split("://", true, 1)[1]
	var slash := clean.find("/")
	if slash >= 0:
		clean = clean.left(slash)
	if clean.begins_with("["):
		var closing := clean.find("]")
		return clean.substr(1, closing - 1).strip_edges() if closing > 1 else ""
	## Une seule paire de deux-points désigne `hôte:port`. Plusieurs indiquent
	## une IPv6 nue, que ENet sait recevoir sans que nous la tronquions.
	if clean.count(":") == 1:
		clean = clean.get_slice(":", 0)
	return clean.strip_edges()


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


## Pour l'adresse affichée automatiquement, les IPv4 privées restent
## prioritaires. Les boucles locales, liens locaux et IPv6 sont écartés : une
## IPv6 peut toujours être saisie manuellement si le réseau l'exige.
static func rank_addresses(addresses: Array) -> Array:
	var result: Array = []
	for entry in addresses:
		var address := str(entry)
		if address.contains(":") or address.begins_with("127.") \
				or address.begins_with("169.254."):
			continue
		result.append(address)
	result.sort_custom(_sorts_before)
	return result


static func _sorts_before(first: String, second: String) -> bool:
	var rank_first := address_rank(first)
	var rank_second := address_rank(second)
	return rank_first < rank_second if rank_first != rank_second else first < second
