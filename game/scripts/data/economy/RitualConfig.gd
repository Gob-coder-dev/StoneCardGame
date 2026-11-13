## Charge les Rituels comme des données de contenu. Aucun prix, taux ou lot
## n'est codé dans les services ou dans l'interface.
class_name RitualConfig
extends RefCounted

const PATH := "res://data/economy/rituals.json"
const RARITIES := ["common", "rare", "epic", "legendary"]
const GateConfigModel := preload("res://scripts/data/progression/ContentGateConfig.gd")
static var _cache: Array = []


static func definitions() -> Array:
	if _cache.is_empty():
		_cache = _read()
	return _cache.duplicate(true)


static func definition(ritual_id: String) -> Dictionary:
	for value in definitions():
		if str(value.get("id", "")) == ritual_id:
			return value.duplicate(true)
	return {}


static func clear_cache_for_tests() -> void:
	_cache.clear()


static func problems(values: Array = []) -> Array[String]:
	var source := definitions() if values.is_empty() else values
	var result: Array[String] = []
	var ids := {}
	var gate_ids := {}
	for gate in GateConfigModel.get_config().get("gates", []):
		if gate is Dictionary:
			gate_ids[str(gate.get("id", ""))] = true
	if source.size() != 4:
		result.append("La boutique doit proposer exactement quatre Rituels.")
	for raw in source:
		if not raw is Dictionary:
			result.append("Une définition de Rituel est invalide.")
			continue
		var value: Dictionary = raw
		var ritual_id := str(value.get("id", ""))
		if ritual_id == "" or ids.has(ritual_id):
			result.append("Identifiant de Rituel absent ou dupliqué.")
		ids[ritual_id] = true
		if int(value.get("price_candles", 0)) <= 0:
			result.append("Prix de bougies invalide pour '%s'." % ritual_id)
		var required_gate := str(value.get("required_gate", ""))
		if required_gate != "" and not gate_ids.has(required_gate):
			result.append("Jalon inconnu pour '%s' : %s." % [ritual_id, required_gate])
		var minimum := int(value.get("souls_min", -1))
		var maximum := int(value.get("souls_max", -1))
		if minimum < 0 or maximum < minimum:
			result.append("Fourchette d'âmes invalide pour '%s'." % ritual_id)
		if bool(value.get("unique_missing", false)):
			continue
		_validate_groups(value.get("normal", []), ritual_id, result)
		var chance := float(value.get("lucky_chance", 0.0))
		if chance < 0.0 or chance > 1.0:
			result.append("Probabilité chanceuse invalide pour '%s'." % ritual_id)
		elif chance > 0.0:
			_validate_groups(value.get("lucky", []), ritual_id, result)
		var profiles: Variant = value.get("progression_profiles", {})
		if not profiles is Dictionary:
			result.append("Profils de progression invalides pour '%s'." % ritual_id)
			continue
		for raw_profile_id in profiles:
			var profile_id := str(raw_profile_id)
			if profile_id != "base" and not gate_ids.has(profile_id):
				result.append("Profil de progression inconnu pour '%s' : %s." % [ritual_id, profile_id])
				continue
			var profile: Variant = profiles[raw_profile_id]
			if not profile is Dictionary:
				result.append("Profil '%s' invalide pour '%s'." % [profile_id, ritual_id])
				continue
			if (profile as Dictionary).has("normal"):
				_validate_groups(profile.get("normal", []), ritual_id, result)
			if (profile as Dictionary).has("lucky"):
				_validate_groups(profile.get("lucky", []), ritual_id, result)
	return result


static func _validate_groups(raw_groups: Variant, ritual_id: String,
		result: Array[String]) -> void:
	if not raw_groups is Array or raw_groups.is_empty():
		result.append("Invocations absentes pour '%s'." % ritual_id)
		return
	for raw in raw_groups:
		if not raw is Dictionary:
			result.append("Invocation invalide pour '%s'." % ritual_id)
			continue
		var group: Dictionary = raw
		var rarity := str(group.get("rarity", ""))
		var minimum := int(group.get("min_copies", 0))
		var maximum := int(group.get("max_copies", 0))
		if not RARITIES.has(rarity) or int(group.get("slots", 0)) <= 0 \
				or minimum <= 0 or maximum < minimum:
			result.append("Invocation '%s' invalide pour '%s'." % [rarity, ritual_id])


static func _read() -> Array:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("RitualConfig: impossible d'ouvrir %s." % PATH)
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("rituals", []) is Array:
		push_error("RitualConfig: JSON invalide.")
		return []
	return (parsed.get("rituals", []) as Array).duplicate(true)
