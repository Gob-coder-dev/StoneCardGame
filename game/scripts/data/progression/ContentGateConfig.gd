## Catalogue des jalons globaux de contenu. Ce chargeur ne lit aucune
## sauvegarde : il valide uniquement les données qui relient les boss aux accès.
class_name ContentGateConfig
extends RefCounted

const PATH := "res://data/progression/content_gates.json"
const KNOWN_RARITIES: Array[String] = ["common", "rare", "epic", "legendary"]

static var _cache: Dictionary = {}


static func get_config() -> Dictionary:
	if _cache.is_empty():
		_cache = _read()
	return _cache.duplicate(true)


static func clear_cache_for_tests() -> void:
	_cache.clear()


static func problems(config: Dictionary = {}) -> Array[String]:
	var value := get_config() if config.is_empty() else config
	var result: Array[String] = []
	var defaults: Variant = value.get("default_rarities", [])
	if not defaults is Array or (defaults as Array).is_empty():
		result.append("Les raretés accessibles au départ sont absentes.")
	else:
		_validate_rarities(defaults, "départ", result)
	var raw_gates: Variant = value.get("gates", [])
	if not raw_gates is Array or (raw_gates as Array).is_empty():
		result.append("Aucun jalon de contenu n'est défini.")
		return result
	var seen := {}
	for raw in raw_gates:
		if not raw is Dictionary:
			result.append("Un jalon de contenu est invalide.")
			continue
		var gate: Dictionary = raw
		var gate_id := str(gate.get("id", ""))
		if gate_id == "" or seen.has(gate_id):
			result.append("Identifiant de jalon absent ou dupliqué.")
		seen[gate_id] = true
		if str(gate.get("required_campaign_node", "")) == "":
			result.append("Niveau requis absent pour '%s'." % gate_id)
		_validate_rarities(gate.get("unlocked_rarities", []), gate_id, result)
	return result


static func _validate_rarities(raw: Variant, owner: String,
		result: Array[String]) -> void:
	if not raw is Array:
		result.append("Raretés invalides pour '%s'." % owner)
		return
	for value in raw:
		var rarity := str(value)
		if not KNOWN_RARITIES.has(rarity):
			result.append("Rareté inconnue '%s' pour '%s'." % [rarity, owner])


static func _read() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("ContentGateConfig: impossible d'ouvrir %s." % PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("ContentGateConfig: JSON invalide.")
		return {}
	return (parsed as Dictionary).duplicate(true)
