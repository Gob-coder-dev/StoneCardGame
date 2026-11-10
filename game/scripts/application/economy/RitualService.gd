## Point d'entrée transactionnel des Rituels. L'achat, le tirage et toutes les
## récompenses sont enregistrés avant que l'animation transitoire ne commence.
class_name RitualService
extends RefCounted

const InventoryModel := preload("res://scripts/domain/economy/PlayerInventory.gd")
const Generator := preload("res://scripts/domain/economy/RitualRewardGenerator.gd")
const Rituals := preload("res://scripts/data/economy/RitualConfig.gd")
const EconomyConfigModel := preload("res://scripts/data/economy/EconomyConfig.gd")


func state() -> Dictionary:
	var inventory := InventoryModel.from_dict(PlayerData.inventory_dict())
	var entries: Array = []
	for definition in Rituals.definitions():
		var copy: Dictionary = definition.duplicate(true)
		var has_candidate := not bool(copy.get("unique_missing", false)) \
			or Generator.has_unique_candidate(inventory)
		copy["available"] = has_candidate
		copy["unavailable_reason"] = "" if has_candidate \
			else "Toutes les cartes ont déjà été obtenues."
		entries.append(copy)
	return {"ok": Rituals.problems().is_empty(), "candles": inventory.candles,
		"rituals": entries}


func purchase(ritual_id: String, seed_override: Variant = null) -> Dictionary:
	var definition := Rituals.definition(ritual_id)
	if definition.is_empty():
		return _fail("Ce Rituel n'existe pas.")
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	var price := int(definition.get("price_candles", 0))
	if price <= 0:
		return _fail("Prix du Rituel invalide.")
	if next.candles < price:
		return _fail("Pas assez de bougies.")
	if bool(definition.get("unique_missing", false)) \
			and not Generator.has_unique_candidate(next):
		return _fail("Toutes les cartes ont déjà été obtenues.")
	var purchase_number := next.ritual_purchase_counter + 1
	var seed := int(seed_override) if seed_override != null else _fresh_seed(purchase_number)
	var generated := Generator.generate(definition, next, seed)
	if not bool(generated.get("ok", false)):
		return generated
	var resolved: Array = []
	for raw_reward in generated.get("rewards", []):
		if not raw_reward is Dictionary:
			return _fail("Récompense de Rituel invalide.")
		var reward: Dictionary = raw_reward.duplicate(true)
		match str(reward.get("type", "")):
			"souls":
				var amount := maxi(0, int(reward.get("amount", 0)))
				next.souls += amount
			"card":
				var lineage_id := str(reward.get("lineage_id", ""))
				var copies := maxi(0, int(reward.get("copies", 0)))
				if lineage_id == "" or copies <= 0:
					return _fail("Carte de Rituel invalide.")
				var stone_id := StoneLoader.variant_id(lineage_id, 1)
				var affinity := StoneLoader.stone_affinity(stone_id)
				var entry := next.entry(lineage_id)
				if int(entry.get("unlocked_level", 0)) >= StoneLoader.lineage_max_level(lineage_id):
					var compensation := _compensation(lineage_id, copies)
					next.souls += compensation
					reward["maxed"] = true
					reward["compensation_souls"] = compensation
				elif affinity != "neutral" and not next.has_god(affinity):
					if not next.defer_copies(lineage_id, copies):
						return _fail("Impossible de mettre la carte '%s' au coffre." % lineage_id)
					reward["deferred"] = true
					reward["god_id"] = affinity
				elif not next.add_copies(lineage_id, copies):
					return _fail("Impossible d'ajouter la carte '%s'." % lineage_id)
			_:
				return _fail("Type de récompense inconnu.")
		resolved.append(reward)
	next.candles -= price
	next.ritual_purchase_counter = purchase_number
	var opening := {
		"purchase_id": "ritual:%d" % purchase_number,
		"ritual_id": ritual_id,
		"ritual_name": str(definition.get("name", "Rituel")),
		"seed": seed,
		"lucky": bool(generated.get("lucky", false)),
		"rewards": resolved,
	}
	var error := PlayerData.commit_inventory(next)
	if error != OK:
		return _save_fail(error)
	return {"ok": true, "reason": "", "price_candles": price,
		"opening": opening.duplicate(true)}

static func _compensation(lineage_id: String, copies: int) -> int:
	var stone_id := StoneLoader.variant_id(lineage_id, 1)
	var rarity := StoneLoader.stone_rarity(stone_id)
	var rule: Dictionary = EconomyConfigModel.get_config().get("shop", {}).get(rarity, {})
	var unit_price := int(rule.get("fixed_price", 0))
	if unit_price <= 0:
		unit_price = int(rule.get("souls_per_copy", 0))
	return int(ceil(float(maxi(0, copies) * maxi(0, unit_price)) * 0.5))


static func _fresh_seed(purchase_number: int) -> int:
	return hash("ritual|%d|%d|%d" % [purchase_number,
		Time.get_unix_time_from_system(), Time.get_ticks_usec()])


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _save_fail(error: Error) -> Dictionary:
	return {"ok": false,
		"reason": "Sauvegarde impossible (%s)." % error_string(error), "error": error}
