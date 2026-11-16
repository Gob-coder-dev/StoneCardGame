## Façade de catalogue et validation des decks pour les outils hors ligne.
## Toutes les contraintes restent déléguées à MonsterLoader et DeckRules.
extends RefCounted

const Identity := preload("res://scripts/ai/neural/RLIdentity.gd")


static func catalog() -> Dictionary:
	var gods: Array = []
	for god in MonsterLoader.get_all_gods():
		gods.append({"id": str(god.get("id", "")), "name": str(god.get("name", ""))})
	var variants: Array = []
	for monster in MonsterLoader.get_all_monsters():
		var monster_id := str(monster.get("id", ""))
		variants.append({
			"monster_id": monster_id,
			"lineage_id": MonsterLoader.monster_lineage(monster_id),
			"level": MonsterLoader.monster_level(monster_id),
			"max_level": MonsterLoader.lineage_max_level(MonsterLoader.monster_lineage(monster_id)),
			"affinity": MonsterLoader.monster_affinity(monster_id),
			"cost": MonsterLoader.monster_cost(monster_id)
		})
	variants.sort_custom(func(a: Dictionary, b: Dictionary): return str(a["monster_id"]) < str(b["monster_id"]))
	var snapshot := {
		"schema_version": 1,
		"deck_size": DeckRules.DECK_SIZE,
		"deck_budget": DeckRules.DECK_BUDGET,
		"gods": gods,
		"variants": variants
	}
	snapshot["checksum"] = Identity.content_checksum()
	snapshot["deck_checksum"] = _checksum(snapshot)
	return snapshot


static func validate_deck(monster_ids: Array, god_id: String) -> Dictionary:
	var result := DeckRules.validate_deck(monster_ids, true, god_id)
	return {
		"valid": bool(result.get("valid", false)),
		"reason": str(result.get("reason", "")),
		"cost": DeckRules.deck_cost(monster_ids) if bool(result.get("valid", false)) else -1.0
	}


static func validate_decks(requests: Array) -> Array:
	var results: Array = []
	for request in requests:
		if not request is Dictionary:
			results.append({"valid": false, "reason": "requete invalide", "cost": -1.0})
			continue
		var result := validate_deck(request.get("monster_ids", []), str(request.get("god_id", "")))
		result["candidate_id"] = str(request.get("candidate_id", ""))
		results.append(result)
	return results


static func engine_manifest() -> Dictionary:
	var catalogue := catalog()
	return {
		"protocol_version": 2,
		"observation_schema": 1,
		"catalogue_checksum": catalogue["checksum"],
		"deck_checksum": catalogue["deck_checksum"],
		"rules_checksum": Identity.rules_checksum(),
		"action_feature_schema": 2,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "development")),
		"godot_version": Engine.get_version_info().get("string", "unknown")
	}


static func _checksum(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(value).to_utf8_buffer())
	return context.finish().hex_encode()
