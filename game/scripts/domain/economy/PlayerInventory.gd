## PlayerInventory.gd
## Valeur sérialisable de progression économique. Les méthodes renvoient des
## copies afin que seul PlayerData publie une mutation après sauvegarde réussie.
class_name PlayerInventory
extends RefCounted

const Integer := preload("res://scripts/domain/IntegerValue.gd")
const Ledger := preload("res://scripts/domain/economy/TransactionLedger.gd")
const ProgressionRules := preload("res://scripts/domain/economy/CardProgressionRules.gd")

var souls: int = 0
var candles: int = 0
var unlocked_gods: Dictionary = {}
var cards: Dictionary = {}
## Copies de cartes divines gagnées avant le déblocage de leur dieu.
## Elles ne font pas partie de la collection et sont libérées atomiquement
## lorsque le dieu correspondant est acheté.
var pending_card_rewards: Dictionary = {}
var first_god_discount_used: bool = false
var applied_transactions: Dictionary = {}
var transaction_cursors: Dictionary = {}
var shop_state: Dictionary = {}
var ritual_purchase_counter: int = 0


static func from_dict(raw: Variant) -> PlayerInventory:
	var result := PlayerInventory.new()
	if not raw is Dictionary:
		return result
	result.souls = Integer.read(raw.get("souls"))
	result.candles = Integer.read(raw.get("candles"))
	var gods: Variant = raw.get("unlocked_god_ids", [])
	if gods is Array:
		for value in gods:
			var god_id := str(value)
			if not StoneLoader.get_god(god_id).is_empty():
				result.unlocked_gods[god_id] = true
	var raw_cards: Variant = raw.get("cards", {})
	if raw_cards is Dictionary:
		for lineage_id in raw_cards:
			var clean := ProgressionRules.sanitize_entry(str(lineage_id), raw_cards[lineage_id])
			var affinity := _lineage_affinity(str(lineage_id))
			if affinity != "" and affinity != "neutral" and not result.has_god(affinity):
				# Migration des récompenses divines accordées par les anciennes
				# versions malgré un dieu encore verrouillé.
				var deferred_amount := maxi(int(clean["copies"]),
					1 if int(clean["unlocked_level"]) > 0 else 0)
				if deferred_amount > 0:
					result.defer_copies(str(lineage_id), deferred_amount)
			elif int(clean["unlocked_level"]) > 0 or int(clean["copies"]) > 0:
				result.cards[str(lineage_id)] = clean
	var raw_pending: Variant = raw.get("pending_card_rewards", {})
	if raw_pending is Dictionary:
		for lineage_id in raw_pending:
			var amount := Integer.read(raw_pending[lineage_id])
			var affinity := _lineage_affinity(str(lineage_id))
			if amount <= 0 or affinity == "":
				continue
			if affinity == "neutral" or result.has_god(affinity):
				result.add_copies(str(lineage_id), amount)
			else:
				result.defer_copies(str(lineage_id), amount)
	result.first_god_discount_used = bool(raw.get("first_god_discount_used", false))
	var ledger := Ledger.restore(raw.get("applied_transactions"), raw.get("transaction_cursors"))
	result.applied_transactions = ledger["keys"]
	result.transaction_cursors = ledger["cursors"]
	result.shop_state = _clean_shop_state(raw.get("shop_state"))
	# Les versions 7 et antérieures pouvaient conserver une animation de Rituel.
	# Les récompenses étaient déjà attribuées : cette présentation obsolète est
	# volontairement ignorée et ne doit jamais être reprise après redémarrage.
	result.ritual_purchase_counter = Integer.read(raw.get("ritual_purchase_counter"))
	return result


func to_dict() -> Dictionary:
	var god_ids: Array = unlocked_gods.keys()
	god_ids.sort()
	return {
		"souls": souls,
		"candles": candles,
		"unlocked_god_ids": god_ids,
		"cards": cards.duplicate(true),
		"pending_card_rewards": pending_card_rewards.duplicate(true),
		"first_god_discount_used": first_god_discount_used,
		"applied_transactions": applied_transactions.duplicate(true),
		"transaction_cursors": transaction_cursors.duplicate(true),
		"shop_state": shop_state.duplicate(true),
		"ritual_purchase_counter": ritual_purchase_counter,
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


func defer_copies(lineage_id: String, amount: int) -> bool:
	var affinity := _lineage_affinity(lineage_id)
	if amount <= 0 or affinity == "" or affinity == "neutral" or has_god(affinity):
		return false
	pending_card_rewards[lineage_id] = int(pending_card_rewards.get(lineage_id, 0)) + amount
	return true


func pending_lineage_count() -> int:
	return pending_card_rewards.size()


func pending_copy_count() -> int:
	var total := 0
	for amount in pending_card_rewards.values():
		total += maxi(0, int(amount))
	return total


## Vue défensive regroupée par dieu. Les cartes sans affinité divine valide
## sont déjà éliminées lors du chargement de l'inventaire.
func pending_rewards_by_god() -> Dictionary:
	var result := {}
	for raw_lineage_id in pending_card_rewards:
		var lineage_id := str(raw_lineage_id)
		var god_id := _lineage_affinity(lineage_id)
		var amount := maxi(0, int(pending_card_rewards[raw_lineage_id]))
		if god_id == "" or god_id == "neutral" or amount <= 0:
			continue
		if not result.has(god_id):
			result[god_id] = []
		result[god_id].append({"lineage_id": lineage_id, "copies": amount})
	return result


## Transfère toutes les récompenses du dieu vers la collection. Le résultat
## sert à informer l'interface d'achat sans exposer la structure interne.
func release_pending_for_god(god_id: String) -> Array:
	if not has_god(god_id):
		return []
	var released: Array = []
	var lineage_ids: Array = pending_card_rewards.keys()
	lineage_ids.sort()
	for raw_lineage_id in lineage_ids:
		var lineage_id := str(raw_lineage_id)
		if _lineage_affinity(lineage_id) != god_id:
			continue
		var amount := maxi(0, int(pending_card_rewards.get(lineage_id, 0)))
		pending_card_rewards.erase(lineage_id)
		if amount > 0 and add_copies(lineage_id, amount):
			released.append({"lineage_id": lineage_id, "copies": amount})
	return released


func unlock_god(god_id: String) -> bool:
	if StoneLoader.get_god(god_id).is_empty():
		return false
	unlocked_gods[god_id] = true
	return true


func has_transaction(transaction_id: String) -> bool:
	return transaction_id != "" and Ledger.contains(applied_transactions, transaction_cursors, transaction_id)


func mark_transaction(transaction_id: String) -> void:
	Ledger.mark(applied_transactions, transaction_cursors, transaction_id)


## Une rotation mal formée est régénérée par ShopService, jamais utilisée pour acheter.
static func _clean_shop_state(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not raw.get("offers") is Array \
			or not raw.get("purchased_offer_ids", {}) is Dictionary:
		return {}
	var rotation := Integer.read(raw.get("rotation_id"), -1, -1)
	if rotation < 0:
		return {}
	var offers: Array = []
	for value in raw["offers"]:
		if not value is Dictionary:
			return {}
		var lineage := str(value.get("lineage_id", ""))
		var stone := StoneLoader.variant_id(lineage, 1)
		var quantity := Integer.read(value.get("quantity"))
		var price := Integer.read(value.get("price"))
		if not value.get("id") is String or stone == "" or quantity <= 0 or price <= 0:
			return {}
		offers.append({"id": value["id"], "lineage_id": lineage, "stone_id": stone,
			"rarity": StoneLoader.stone_rarity(stone), "quantity": quantity, "price": price})
	var purchased := {}
	for id in raw.get("purchased_offer_ids", {}):
		if id is String and raw["purchased_offer_ids"][id] == true:
			purchased[id] = true
	return {"rotation_id": rotation, "offers": offers, "purchased_offer_ids": purchased,
		"access_revision": Integer.read(raw.get("access_revision"), -1, -1)}


static func _lineage_affinity(lineage_id: String) -> String:
	var first_form := StoneLoader.variant_id(lineage_id, 1)
	return StoneLoader.stone_affinity(first_form) if first_form != "" else ""
