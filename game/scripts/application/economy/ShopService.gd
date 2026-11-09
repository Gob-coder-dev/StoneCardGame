## ShopService.gd
## Génère quatre offres déterministes par fenêtre de trois heures et applique
## les achats. Les offres de la fenêtre courante sont figées dans le profil :
## acheter un dieu ne les remplace pas sous les yeux du joueur.
class_name ShopService
extends RefCounted

const InventoryModel := preload("res://scripts/domain/economy/PlayerInventory.gd")
const ConfigModel := preload("res://scripts/data/economy/EconomyConfig.gd")


func state(now_unix: int = 0) -> Dictionary:
	var timestamp := now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())
	var config := ConfigModel.get_config()
	var duration := maxi(1, int(config.get("shop_rotation_seconds", 10800)))
	var rotation_id := timestamp / duration
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	var saved_rotation := int(next.shop_state.get("rotation_id", -1))
	if saved_rotation != rotation_id:
		next.shop_state = {
			"rotation_id": rotation_id,
			"offers": _generate_offers(rotation_id, next, config),
			"purchased_offer_ids": {},
		}
		var error := PlayerData.commit_inventory(next)
		if error != OK:
			return {"ok": false, "reason": "Boutique non enregistrée (%s)." % error_string(error)}
	var offers: Array = (next.shop_state.get("offers", []) as Array).duplicate(true)
	var purchased: Dictionary = (next.shop_state.get("purchased_offer_ids", {}) as Dictionary).duplicate()
	for offer in offers:
		offer["purchased"] = purchased.has(str(offer.get("id", "")))
	return {"ok": true, "reason": "", "rotation_id": rotation_id,
		"ends_at": (rotation_id + 1) * duration, "offers": offers}


func buy_offer(offer_id: String, now_unix: int = 0) -> Dictionary:
	var current := state(now_unix)
	if not bool(current.get("ok", false)):
		return current
	var selected: Dictionary = {}
	for raw in current.get("offers", []):
		if raw is Dictionary and str(raw.get("id", "")) == offer_id:
			selected = raw
			break
	if selected.is_empty():
		return {"ok": false, "reason": "Cette offre n'existe plus."}
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	var purchased: Dictionary = next.shop_state.get("purchased_offer_ids", {})
	if purchased.has(offer_id):
		return {"ok": false, "reason": "Cette offre a déjà été achetée."}
	var price := int(selected.get("price", 0))
	if next.souls < price:
		return {"ok": false, "reason": "Pas assez d'âmes."}
	var lineage_id := str(selected.get("lineage_id", ""))
	var amount := int(selected.get("quantity", 0))
	if not _lineage_is_eligible(lineage_id, next) or amount <= 0:
		return {"ok": false, "reason": "Cette carte n'est pas disponible."}
	next.souls -= price
	next.add_copies(lineage_id, amount)
	purchased[offer_id] = true
	next.shop_state["purchased_offer_ids"] = purchased
	var error := PlayerData.commit_inventory(next)
	if error != OK:
		return {"ok": false, "reason": "Achat non enregistré (%s)." % error_string(error)}
	return {"ok": true, "reason": "", "price": price,
		"lineage_id": lineage_id, "copies": amount}


func _generate_offers(rotation_id: int, inventory: PlayerInventory,
		config: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	var gods: Array = inventory.unlocked_gods.keys()
	gods.sort()
	rng.seed = hash("samstone-shop|%d|%s" % [rotation_id, ",".join(gods)])
	var by_rarity := _eligible_by_rarity(inventory)
	var slots: Array = config.get("shop", {}).get("slot_rarities", [])
	var count := int(config.get("shop_offer_count", 4))
	var used := {}
	var result: Array = []
	for index in range(count):
		var weights: Dictionary = slots[index] if index < slots.size() \
			and slots[index] is Dictionary else {"common": 1}
		var rarity := _weighted_rarity(weights, by_rarity, used, rng)
		var candidates := _unused(by_rarity.get(rarity, []), used)
		if candidates.is_empty():
			candidates = _all_unused(by_rarity, used)
		if candidates.is_empty():
			break
		var lineage_id := str(candidates[rng.randi_range(0, candidates.size() - 1)])
		used[lineage_id] = true
		var first_form := StoneLoader.variant_id(lineage_id, 1)
		rarity = StoneLoader.stone_rarity(first_form)
		var rule: Dictionary = config.get("shop", {}).get(rarity, {})
		var quantity := rng.randi_range(int(rule.get("min_quantity", 1)),
			int(rule.get("max_quantity", 1)))
		var price := int(rule.get("fixed_price", 0))
		if price <= 0:
			price = quantity * int(rule.get("souls_per_copy", 0))
		result.append({
			"id": "%d:%d" % [rotation_id, index],
			"lineage_id": lineage_id,
			"stone_id": first_form,
			"rarity": rarity,
			"quantity": quantity,
			"price": price,
		})
	return result


func _eligible_by_rarity(inventory: PlayerInventory) -> Dictionary:
	var result := {"common": [], "rare": [], "epic": [], "legendary": []}
	var seen := {}
	for stone in StoneLoader.get_all_stones():
		var stone_id := str(stone.get("id", ""))
		var lineage_id := StoneLoader.stone_lineage(stone_id)
		if seen.has(lineage_id):
			continue
		seen[lineage_id] = true
		if not _lineage_is_eligible(lineage_id, inventory):
			continue
		var rarity := StoneLoader.stone_rarity(stone_id)
		if result.has(rarity):
			result[rarity].append(lineage_id)
	return result


func _lineage_is_eligible(lineage_id: String, inventory: PlayerInventory) -> bool:
	var first := StoneLoader.variant_id(lineage_id, 1)
	if first == "":
		return false
	var affinity := StoneLoader.stone_affinity(first)
	if affinity != "neutral" and not inventory.has_god(affinity):
		return false
	return inventory.unlocked_level(lineage_id) < StoneLoader.lineage_max_level(lineage_id)


static func _weighted_rarity(weights: Dictionary, pools: Dictionary, used: Dictionary,
		rng: RandomNumberGenerator) -> String:
	var choices: Array = []
	var total := 0
	for rarity in weights:
		if _unused(pools.get(rarity, []), used).is_empty():
			continue
		var weight := maxi(0, int(weights[rarity]))
		if weight > 0:
			choices.append([str(rarity), weight])
			total += weight
	if total <= 0:
		return ""
	var roll := rng.randi_range(1, total)
	for choice in choices:
		roll -= int(choice[1])
		if roll <= 0:
			return str(choice[0])
	return str(choices.back()[0])


static func _unused(values: Array, used: Dictionary) -> Array:
	return values.filter(func(value): return not used.has(str(value)))


static func _all_unused(pools: Dictionary, used: Dictionary) -> Array:
	var result: Array = []
	for values in pools.values():
		result.append_array(_unused(values, used))
	return result
