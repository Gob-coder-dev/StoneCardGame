## PlayerInventory.gd
## Valeur sérialisable de progression économique. Les méthodes renvoient des
## copies afin que seul PlayerData publie une mutation après sauvegarde réussie.
class_name PlayerInventory
extends RefCounted

const ProgressionRules := preload("res://scripts/domain/economy/CardProgressionRules.gd")

var souls: int = 0
var unlocked_gods: Dictionary = {}
var cards: Dictionary = {}
var first_god_discount_used: bool = false
var applied_transactions: Dictionary = {}
var shop_state: Dictionary = {}


static func from_dict(raw: Variant) -> PlayerInventory:
	var result := PlayerInventory.new()
	if not raw is Dictionary:
		return result
	result.souls = maxi(0, int(raw.get("souls", 0)))
	var gods: Variant = raw.get("unlocked_god_ids", [])
	if gods is Array:
		for value in gods:
			var god_id := StoneLoader.resolve_saved_god_id(str(value))
			if not StoneLoader.get_god(god_id).is_empty():
				result.unlocked_gods[god_id] = true
	var raw_cards: Variant = raw.get("cards", {})
	if raw_cards is Dictionary:
		for lineage_id in raw_cards:
			var clean := ProgressionRules.sanitize_entry(str(lineage_id), raw_cards[lineage_id])
			if int(clean["unlocked_level"]) > 0 or int(clean["copies"]) > 0:
				result.cards[str(lineage_id)] = clean
	result.first_god_discount_used = bool(raw.get("first_god_discount_used", false))
	for field in ["applied_transactions", "shop_state"]:
		var source: Variant = raw.get(field, {})
		if source is Dictionary:
			result.set(field, (source as Dictionary).duplicate(true))
	return result


func to_dict() -> Dictionary:
	var god_ids: Array = unlocked_gods.keys()
	god_ids.sort()
	return {
		"souls": souls,
		"unlocked_god_ids": god_ids,
		"cards": cards.duplicate(true),
		"first_god_discount_used": first_god_discount_used,
		"applied_transactions": applied_transactions.duplicate(true),
		"shop_state": shop_state.duplicate(true),
	}


func duplicate_inventory() -> PlayerInventory:
	return PlayerInventory.from_dict(to_dict())


func has_god(god_id: String) -> bool:
	return unlocked_gods.has(god_id)


func entry(lineage_id: String) -> Dictionary:
	return (cards.get(lineage_id, ProgressionRules.default_entry()) as Dictionary).duplicate(true)


func unlocked_level(lineage_id: String) -> int:
	return int(cards.get(lineage_id, {}).get("unlocked_level", 0))


func owns_stone(stone_id: String) -> bool:
	return StoneLoader.has_stone(stone_id) \
		and unlocked_level(StoneLoader.stone_lineage(stone_id)) >= StoneLoader.stone_level(stone_id)


func add_copies(lineage_id: String, amount: int) -> bool:
	var maximum := StoneLoader.lineage_max_level(lineage_id)
	if maximum <= 0 or amount <= 0:
		return false
	cards[lineage_id] = ProgressionRules.add_copies(entry(lineage_id), amount, maximum)
	return true


func unlock_god(god_id: String) -> bool:
	if StoneLoader.get_god(god_id).is_empty():
		return false
	unlocked_gods[god_id] = true
	return true


func has_transaction(transaction_id: String) -> bool:
	return transaction_id != "" and applied_transactions.has(transaction_id)


func mark_transaction(transaction_id: String) -> void:
	if transaction_id != "":
		applied_transactions[transaction_id] = true
