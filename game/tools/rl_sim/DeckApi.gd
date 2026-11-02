## Façade de catalogue et validation des decks pour les outils hors ligne.
## Toutes les contraintes restent déléguées à StoneLoader et DeckRules.
extends RefCounted


static func catalog() -> Dictionary:
	var gods: Array = []
	for god in StoneLoader.get_all_gods():
		gods.append({"id": str(god.get("id", "")), "name": str(god.get("name", ""))})
	var variants: Array = []
	for stone in StoneLoader.get_all_stones():
		var stone_id := str(stone.get("id", ""))
		variants.append({
			"stone_id": stone_id,
			"lineage_id": StoneLoader.stone_lineage(stone_id),
			"level": StoneLoader.stone_level(stone_id),
			"max_level": StoneLoader.lineage_max_level(StoneLoader.stone_lineage(stone_id)),
			"affinity": StoneLoader.stone_affinity(stone_id),
			"cost": StoneLoader.stone_cost(stone_id)
		})
	variants.sort_custom(func(a: Dictionary, b: Dictionary): return str(a["stone_id"]) < str(b["stone_id"]))
	var snapshot := {
		"schema_version": 1,
		"deck_size": DeckRules.DECK_SIZE,
		"deck_budget": DeckRules.DECK_BUDGET,
		"gods": gods,
		"variants": variants
	}
	snapshot["checksum"] = _checksum(snapshot)
	return snapshot


static func validate_deck(stone_ids: Array, god_id: String) -> Dictionary:
	var result := DeckRules.validate_deck(stone_ids, true, god_id)
	return {
		"valid": bool(result.get("valid", false)),
		"reason": str(result.get("reason", "")),
		"cost": DeckRules.deck_cost(stone_ids) if bool(result.get("valid", false)) else -1.0
	}


static func validate_decks(requests: Array) -> Array:
	var results: Array = []
	for request in requests:
		if not request is Dictionary:
			results.append({"valid": false, "reason": "requete invalide", "cost": -1.0})
			continue
		var result := validate_deck(request.get("stone_ids", []), str(request.get("god_id", "")))
		result["candidate_id"] = str(request.get("candidate_id", ""))
		results.append(result)
	return results


static func engine_manifest() -> Dictionary:
	var catalogue := catalog()
	return {
		"protocol_version": 2,
		"observation_schema": 1,
		"catalogue_checksum": catalogue["checksum"],
		"game_version": str(ProjectSettings.get_setting("application/config/version", "development")),
		"godot_version": Engine.get_version_info().get("string", "unknown")
	}


static func _checksum(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(value).to_utf8_buffer())
	return context.finish().hex_encode()
