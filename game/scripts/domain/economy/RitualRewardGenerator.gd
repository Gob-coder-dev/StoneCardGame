## Tirage pur des Rituels. Il ne modifie jamais le profil : le service
## d'application décide ensuite comment attribuer ou compenser chaque lot.
class_name RitualRewardGenerator
extends RefCounted

const RARITY_PRIORITY := ["legendary", "epic", "rare", "common"]


static func generate(definition: Dictionary, inventory: PlayerInventory,
		seed: int) -> Dictionary:
	if definition.is_empty() or inventory == null:
		return _fail("Rituel invalide.")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rewards: Array = []
	var souls_min := maxi(0, int(definition.get("souls_min", 0)))
	var souls_max := maxi(souls_min, int(definition.get("souls_max", souls_min)))
	if souls_max > 0:
		rewards.append({"type": "souls", "amount": rng.randi_range(souls_min, souls_max)})
	if bool(definition.get("unique_missing", false)):
		var unique := _unique_missing(inventory, rng)
		if unique == "":
			return _fail("Aucune nouvelle carte ne reste à débloquer.")
		rewards.append(_card_reward(unique, 1))
		return {"ok": true, "reason": "", "lucky": false, "rewards": rewards}
	var lucky := float(definition.get("lucky_chance", 0.0)) > 0.0 \
		and rng.randf() < float(definition.get("lucky_chance", 0.0))
	var groups: Variant = definition.get("lucky" if lucky else "normal", [])
	if not groups is Array:
		return _fail("Composition du Rituel invalide.")
	var pools := _eligible_pools(inventory)
	var used := {}
	for raw_group in groups:
		if not raw_group is Dictionary:
			return _fail("Invocation invalide.")
		var group: Dictionary = raw_group
		var rarity := str(group.get("rarity", ""))
		for _slot in range(int(group.get("slots", 0))):
			var candidates: Array = (pools.get(rarity, []) as Array).filter(func(lineage_id):
				return not used.has(str(lineage_id)))
			if candidates.is_empty():
				return _fail("Pas assez de cartes %s éligibles." % rarity)
			var lineage_id := str(candidates[rng.randi_range(0, candidates.size() - 1)])
			used[lineage_id] = true
			var amount := rng.randi_range(int(group.get("min_copies", 1)),
				int(group.get("max_copies", 1)))
			rewards.append(_card_reward(lineage_id, amount))
	return {"ok": true, "reason": "", "lucky": lucky, "rewards": rewards}


static func has_unique_candidate(inventory: PlayerInventory) -> bool:
	for values in _missing_by_rarity(inventory).values():
		if not (values as Array).is_empty():
			return true
	return false


static func _unique_missing(inventory: PlayerInventory,
		rng: RandomNumberGenerator) -> String:
	var pools := _missing_by_rarity(inventory)
	for rarity in RARITY_PRIORITY:
		var candidates: Array = pools.get(rarity, [])
		if not candidates.is_empty():
			return str(candidates[rng.randi_range(0, candidates.size() - 1)])
	return ""


static func _eligible_pools(inventory: PlayerInventory) -> Dictionary:
	var result := {"common": [], "rare": [], "epic": [], "legendary": []}
	for lineage_id in _all_lineages():
		var stone_id := StoneLoader.variant_id(lineage_id, 1)
		var affinity := StoneLoader.stone_affinity(stone_id)
		if affinity != "neutral" and not inventory.has_god(affinity):
			continue
		var rarity := StoneLoader.stone_rarity(stone_id)
		if result.has(rarity):
			result[rarity].append(lineage_id)
	return result


static func _missing_by_rarity(inventory: PlayerInventory) -> Dictionary:
	var result := {"common": [], "rare": [], "epic": [], "legendary": []}
	for lineage_id in _all_lineages():
		var stone_id := StoneLoader.variant_id(lineage_id, 1)
		# Une récompense divine déjà rangée dans le coffre est acquise, même si
		# elle reste inutilisable jusqu'à l'achat de son dieu.
		if inventory.unlocked_level(lineage_id) > 0 \
				or int(inventory.pending_card_rewards.get(lineage_id, 0)) > 0:
			continue
		var rarity := StoneLoader.stone_rarity(stone_id)
		if result.has(rarity):
			result[rarity].append(lineage_id)
	return result


static func _all_lineages() -> Array[String]:
	var result: Array[String] = []
	var seen := {}
	for stone in StoneLoader.get_all_stones():
		var lineage_id := StoneLoader.stone_lineage(str(stone.get("id", "")))
		if lineage_id == "" or seen.has(lineage_id):
			continue
		seen[lineage_id] = true
		result.append(lineage_id)
	result.sort()
	return result


static func _card_reward(lineage_id: String, copies: int) -> Dictionary:
	var stone_id := StoneLoader.variant_id(lineage_id, 1)
	return {"type": "card", "lineage_id": lineage_id, "stone_id": stone_id,
		"rarity": StoneLoader.stone_rarity(stone_id), "copies": copies}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "rewards": []}
