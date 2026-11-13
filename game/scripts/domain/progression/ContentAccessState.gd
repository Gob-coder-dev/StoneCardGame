## Projection immuable des accès de contenu. Les services consommateurs ne
## connaissent ni les boss ni le format de la sauvegarde de campagne.
class_name ContentAccessState
extends RefCounted

var revision: int = 0
var unlocked_gates: Dictionary = {}
var unlocked_rarities: Dictionary = {}


static func build(gates: Dictionary, rarities: Dictionary,
		value_revision: int) -> ContentAccessState:
	var state := ContentAccessState.new()
	state.unlocked_gates = gates.duplicate()
	state.unlocked_rarities = rarities.duplicate()
	state.revision = maxi(0, value_revision)
	return state


func has_gate(gate_id: String) -> bool:
	return gate_id == "" or unlocked_gates.has(gate_id)


func allows_rarity(rarity: String) -> bool:
	return unlocked_rarities.has(rarity)


func rarities() -> Array[String]:
	var ordered: Array[String] = []
	for rarity in ["common", "rare", "epic", "legendary"]:
		if unlocked_rarities.has(rarity):
			ordered.append(rarity)
	return ordered


func to_dict() -> Dictionary:
	var gates: Array = unlocked_gates.keys()
	gates.sort()
	return {
		"revision": revision,
		"unlocked_gates": gates,
		"unlocked_rarities": rarities(),
	}
