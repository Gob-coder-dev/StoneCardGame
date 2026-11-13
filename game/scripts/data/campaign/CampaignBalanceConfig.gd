## Charge la courbe d'authoring utilisee par le generateur et les controles de
## livraison. Le runtime de combat continue de lire uniquement le JSON compile.
class_name CampaignBalanceConfig
extends RefCounted

const PATH := "res://data/campaign/authoring/balance_stages.json"
static var _cache: Dictionary = {}


static func get_config() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file == null:
			return {}
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			_cache = (parsed as Dictionary).duplicate(true)
	return _cache.duplicate(true)


static func chapter(chapter_name: String) -> Dictionary:
	var value: Variant = get_config().get("chapters", {}).get(chapter_name, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func problems(config: Dictionary = {}) -> Array[String]:
	var source := get_config() if config.is_empty() else config
	var result: Array[String] = []
	var chapters: Variant = source.get("chapters", {})
	if not chapters is Dictionary or (chapters as Dictionary).is_empty():
		return ["La courbe d'equilibrage ne contient aucun chapitre."]
	var required_gap := float(source.get("required_boss_precision_gap", -1.0))
	if required_gap <= 0.0 or required_gap > 0.25:
		result.append("L'ecart de precision des boss obligatoires est invalide.")
	for chapter_name in chapters:
		var raw: Variant = chapters[chapter_name]
		if not raw is Dictionary:
			result.append("Profil invalide pour '%s'." % chapter_name)
			continue
		var profile: Dictionary = raw
		var minimum := float(profile.get("precision_min", -1.0))
		var maximum := float(profile.get("precision_max", -1.0))
		var challenge := float(profile.get("challenge_precision_max", -1.0))
		if minimum < 0.0 or maximum < minimum or challenge < maximum or challenge > 1.0:
			result.append("Precisions invalides pour '%s'." % chapter_name)
		var average := (minimum + maximum) * 0.5
		if average > 0.0 and challenge > minf(1.0, average * 2.0 + 0.001):
			result.append("Pic de difficulte excessif pour '%s'." % chapter_name)
		if int(profile.get("tier_min", 0)) < 1 \
				or int(profile.get("tier_max", 0)) < int(profile.get("tier_min", 0)):
			result.append("Paliers invalides pour '%s'." % chapter_name)
		var modes: Variant = profile.get("allowed_modes", [])
		if not modes is Array or (modes as Array).is_empty():
			result.append("Modes absents pour '%s'." % chapter_name)
	return result
