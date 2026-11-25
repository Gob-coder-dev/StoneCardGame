## Décisions d'équipement et publication du deck, indépendantes des panneaux.
extends RefCounted

const CatalogueModel := preload("res://scripts/data/MonsterLoader.gd")
const REASON_NOT_OWNED := "not_owned"

var _catalogue: CatalogueModel
var _owns_card: Callable
var _write_deck: Callable


func _init(catalogue: CatalogueModel, owns_card: Callable, write_deck: Callable) -> void:
	_catalogue = catalogue
	_owns_card = owns_card
	_write_deck = write_deck


func equip(deck: Array, monster_id: String, god_id: String) -> Dictionary:
	if not _owns_card.call(monster_id):
		return {"success": false, "reason": REASON_NOT_OWNED}
	var lineage := _catalogue.monster_lineage(monster_id)
	var index := DeckRules.lineage_index(deck, lineage, _catalogue)
	if index >= 0:
		return DeckRules.try_replace(deck, str(deck[index]), monster_id, god_id, _catalogue)
	return DeckRules.try_add(deck, monster_id, god_id, _catalogue)


func replace(deck: Array, old_id: String, new_id: String, god_id: String) -> Dictionary:
	return DeckRules.try_replace(deck, old_id, new_id, god_id, _catalogue)


func commit(deck: Array) -> bool:
	return bool(_write_deck.call(deck))
