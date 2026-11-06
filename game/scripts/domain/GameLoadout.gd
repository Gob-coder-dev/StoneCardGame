## Loadout générique d'un participant. Aucune métadonnée de réseau ou de série.
class_name GameLoadout
extends RefCounted

var god_id: String = ""
var deck: Array = []
var total_quarters: int = 0
var seed: int = 0


static func create(p_god_id: String, p_deck: Array, p_seed: int = 0) -> GameLoadout:
	var loadout := GameLoadout.new()
	loadout.god_id = p_god_id
	loadout.deck = p_deck.duplicate()
	loadout.total_quarters = DeckRules.deck_quarters(loadout.deck)
	loadout.seed = p_seed
	return loadout


static func from_dict(data: Dictionary) -> GameLoadout:
	var loadout := GameLoadout.new()
	loadout.god_id = str(data.get("god_id", ""))
	loadout.deck = (data.get("deck", []) as Array).duplicate()
	loadout.total_quarters = int(data.get("total_quarters",
		DeckRules.deck_quarters(loadout.deck)))
	loadout.seed = int(data.get("seed", 0))
	return loadout


func copy() -> GameLoadout:
	return GameLoadout.from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"god_id": god_id,
		"deck": deck.duplicate(),
		"total_quarters": total_quarters,
		"seed": seed,
	}


func total_points() -> float:
	return float(total_quarters) / float(StoneCostRules.COST_SCALE)


func is_valid() -> bool:
	return DeckRules.is_deck_valid(deck, god_id)
