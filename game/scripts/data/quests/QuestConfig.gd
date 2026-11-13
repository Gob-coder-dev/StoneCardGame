## QuestConfig.gd
## Catalogue des quêtes. Ajouter une mission ne demande aucune ligne de code :
## une entrée dans data/quests/quests.json suffit, et sa cohérence est vérifiée
## au chargement comme pour l'économie et les Rituels.
class_name QuestConfig
extends RefCounted

const PATH := "res://data/quests/quests.json"
const MetricsModel := preload("res://scripts/application/quests/QuestMetrics.gd")
const RitualConfigModel := preload("res://scripts/data/economy/RitualConfig.gd")
const GateConfigModel := preload("res://scripts/data/progression/ContentGateConfig.gd")

static var _cache: Dictionary = {}


static func get_config() -> Dictionary:
	if _cache.is_empty():
		_cache = _read()
	return _cache.duplicate(true)


static func clear_cache_for_tests() -> void:
	_cache.clear()


static func dailies() -> Array:
	var raw: Variant = get_config().get("daily", [])
	return raw if raw is Array else []


static func uniques() -> Array:
	var raw: Variant = get_config().get("unique", [])
	return raw if raw is Array else []


static func daily_count() -> int:
	return maxi(1, int(get_config().get("daily_count", 3)))


## Bougies offertes à la quotidienne la plus exigeante du tirage.
static func candle_reward() -> int:
	return maxi(0, int(get_config().get("candle_reward", 0)))


static func definition(quest_id: String) -> Dictionary:
	for quest in dailies() + uniques():
		if quest is Dictionary and str(quest.get("id", "")) == quest_id:
			return quest
	return {}


static func problems(config: Dictionary = {}) -> Array[String]:
	var value := get_config() if config.is_empty() else config
	var result: Array[String] = []
	var daily_entries: Variant = value.get("daily", [])
	var unique_entries: Variant = value.get("unique", [])
	if not daily_entries is Array or not unique_entries is Array:
		return ["Le catalogue des quêtes est invalide."]
	if int(value.get("daily_count", 0)) < 1:
		result.append("Le nombre de quêtes quotidiennes doit être positif.")
	var seen := {}
	var gate_ids := {}
	for gate in GateConfigModel.get_config().get("gates", []):
		if gate is Dictionary:
			gate_ids[str(gate.get("id", ""))] = true
	for kind in ["daily", "unique"]:
		var entries: Array = value.get(kind, [])
		for raw in entries:
			if not raw is Dictionary:
				result.append("Une quête '%s' n'est pas un objet." % kind)
				continue
			var quest: Dictionary = raw
			var quest_id := str(quest.get("id", ""))
			if quest_id == "":
				result.append("Une quête '%s' n'a pas d'identifiant." % kind)
				continue
			if seen.has(quest_id):
				result.append("Identifiant de quête en double : %s." % quest_id)
			seen[quest_id] = true
			var metric := str(quest.get("metric", ""))
			var required_gate := str(quest.get("required_gate", ""))
			if required_gate != "" and not gate_ids.has(required_gate):
				result.append("Jalon inconnu pour '%s' : %s." % [quest_id, required_gate])
			var progress_policy := str(quest.get("progress_policy", "lifetime"))
			if not ["lifetime", "since_gate"].has(progress_policy):
				result.append("Politique de progression inconnue pour '%s'." % quest_id)
			if not MetricsModel.is_known(metric):
				result.append("Métrique inconnue pour '%s' : %s." % [quest_id, metric])
			elif kind == "daily" and MetricsModel.is_derived(metric):
				result.append("Une quotidienne ne peut pas lire une métrique dérivée : %s." % quest_id)
			if str(quest.get("title", "")) == "":
				result.append("Titre manquant pour '%s'." % quest_id)
			var tiers: Variant = quest.get("tiers", [])
			if not tiers is Array or tiers.is_empty():
				result.append("Paliers manquants pour '%s'." % quest_id)
				continue
			var previous := 0
			for raw_tier in tiers:
				if not raw_tier is Dictionary:
					result.append("Palier invalide pour '%s'." % quest_id)
					continue
				var tier: Dictionary = raw_tier
				var threshold := int(tier.get("threshold", 0))
				if threshold <= previous:
					result.append("Paliers non croissants pour '%s'." % quest_id)
				previous = threshold
				var raw_cards: Variant = tier.get("cards", [])
				var reward_cards: Array = raw_cards if raw_cards is Array else []
				if raw_cards != null and not raw_cards is Array:
					result.append("Récompenses de cartes invalides pour '%s'." % quest_id)
				for raw_card in reward_cards:
					if not raw_card is Dictionary:
						result.append("Récompense de carte invalide pour '%s'." % quest_id)
						continue
					var card: Dictionary = raw_card
					var lineage_id := str(card.get("lineage_id", ""))
					if lineage_id == "" or StoneLoader.variant_id(lineage_id, 1) == "":
						result.append("Lignée inconnue pour '%s' : %s." % [quest_id, lineage_id])
					elif int(card.get("copies", 0)) <= 0:
						result.append("Copies invalides pour '%s'." % quest_id)
					else:
						var stone_id := StoneLoader.variant_id(lineage_id, 1)
						var rarity := StoneLoader.stone_rarity(stone_id)
						if rarity == "epic" and required_gate == "":
							result.append("Récompense épique sans jalon pour '%s'." % quest_id)
						elif rarity == "legendary" and required_gate != "legendary_cards":
							result.append("Récompense légendaire sans jalon pour '%s'." % quest_id)
				var ritual := str(tier.get("ritual", ""))
				if ritual != "" and RitualConfigModel.definition(ritual).is_empty():
					result.append("Rituel inconnu pour '%s' : %s." % [quest_id, ritual])
				elif ritual == "unique":
					result.append("Le Rituel unique ne peut pas être offert par une quête.")
				if int(tier.get("souls", 0)) <= 0 and int(tier.get("candles", 0)) <= 0 \
						and reward_cards.is_empty() and ritual == "":
					result.append("Palier sans récompense pour '%s'." % quest_id)
	return result


static func _read() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("QuestConfig: impossible d'ouvrir %s." % PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("QuestConfig: JSON invalide.")
		return {}
	return parsed
