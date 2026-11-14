## Loadout.gd
## Enveloppe PVP d'un GameLoadout : camp et identifiants réseau de préparation.
## Le dieu, le deck et le total restent définis par la classe générique parente.
class_name Loadout
extends "res://scripts/domain/GameLoadout.gd"

var series_id: String = ""
var preparation_id: String = ""
var round_index: int = 1
var rules_revision: int = 0
var side: int = GameState.PLAYER_NONE
static func create(p_god_id: String, p_deck: Array, p_side: int = GameState.PLAYER_NONE,
		p_series_id: String = "", p_preparation_id: String = "",
		p_round_index: int = 1, p_rules_revision: int = 0) -> Loadout:
	var loadout := Loadout.new()
	loadout.god_id = p_god_id
	loadout.deck = p_deck.duplicate()
	loadout.side = p_side
	loadout.series_id = p_series_id
	loadout.preparation_id = p_preparation_id
	loadout.round_index = p_round_index
	loadout.rules_revision = p_rules_revision
	loadout.total_quarters = DeckRules.deck_quarters(loadout.deck)
	return loadout


static func from_dict(data: Dictionary) -> Loadout:
	var loadout := Loadout.new()
	loadout.series_id = str(data.get("series_id", ""))
	loadout.preparation_id = str(data.get("preparation_id", ""))
	loadout.round_index = int(data.get("round_index", 1))
	loadout.rules_revision = int(data.get("rules_revision", 0))
	loadout.side = int(data.get("side", GameState.PLAYER_NONE))
	loadout.god_id = str(data.get("god_id", ""))
	loadout.deck = (data.get("deck", []) as Array).duplicate()
	loadout.total_quarters = int(data.get("total_quarters",
		DeckRules.deck_quarters(loadout.deck)))
	loadout.generation_seed = int(data.get("seed", 0))
	return loadout


func copy() -> Loadout:
	return Loadout.from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"series_id": series_id,
		"preparation_id": preparation_id,
		"round_index": round_index,
		"rules_revision": rules_revision,
		"side": side,
		"god_id": god_id,
		"deck": deck.duplicate(),
		"total_quarters": total_quarters,
		"seed": generation_seed,
	}


