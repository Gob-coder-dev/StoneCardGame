## EconomyConfig.gd
## Charge et valide la configuration économique. Le gameplay ne dépend jamais
## de valeurs écrites dans une scène ou un contrôleur UI.
class_name EconomyConfig
extends RefCounted

const PATH := "res://data/economy/economy_config.json"
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
	if int(value.get("shop_rotation_seconds", 0)) <= 0:
		result.append("La durée de rotation doit être positive.")
	if int(value.get("shop_offer_count", 0)) != 4:
		result.append("La boutique doit contenir exactement quatre offres.")
	if float(value.get("repeat_reward_multiplier", -1.0)) < 0.0:
		result.append("Le multiplicateur de répétition est invalide.")
	var shop: Variant = value.get("shop", {})
	var expected_prices := {"common": 5, "rare": 15, "epic": 30}
	if not shop is Dictionary:
		result.append("La configuration de la boutique est absente.")
	else:
		for rarity in expected_prices:
			var rule: Variant = shop.get(rarity, {})
			if not rule is Dictionary \
					or int(rule.get("souls_per_copy", 0)) != int(expected_prices[rarity]):
				result.append("Prix unitaire invalide pour la rareté '%s'." % rarity)
	var starter: Variant = value.get("starter", {})
	if not starter is Dictionary or not starter.get("deck", []) is Array:
		result.append("Le profil de départ est invalide.")
	else:
		var deck: Array = starter.get("deck", [])
		if deck.size() != 5:
			result.append("Le deck de départ doit contenir cinq cartes.")
		for stone_id in deck:
			if not StoneLoader.has_stone(str(stone_id)):
				result.append("Carte de départ inconnue : %s." % stone_id)
			elif StoneLoader.stone_affinity(str(stone_id)) != "neutral" \
					or StoneLoader.stone_rarity(str(stone_id)) != "common" \
					or StoneLoader.stone_level(str(stone_id)) != 1:
				result.append("La carte de départ '%s' doit être une commune neutre N1." % stone_id)
	var candle_rewards: Variant = value.get("campaign_candles_by_chapter", {})
	if not candle_rewards is Dictionary or candle_rewards.is_empty():
		result.append("La progression des bougies de campagne est absente.")
	else:
		for chapter in candle_rewards:
			if int(candle_rewards[chapter]) <= 0:
				result.append("Récompense de bougies invalide pour '%s'." % chapter)
	var gifts: Variant = value.get("god_gifts", {})
	if not gifts is Dictionary:
		result.append("Les cadeaux des dieux sont absents.")
	else:
		for god in StoneLoader.get_all_gods():
			var god_id := str(god.get("id", ""))
			var lines: Variant = gifts.get(god_id, [])
			if not lines is Array or lines.size() != 2:
				result.append("Le dieu '%s' doit offrir deux cartes." % god_id)
				continue
			for lineage_id in lines:
				var stone_id := StoneLoader.variant_id(str(lineage_id), 1)
				if stone_id == "" or StoneLoader.stone_affinity(stone_id) != god_id \
						or StoneLoader.stone_rarity(stone_id) != "common":
					result.append("Cadeau commun invalide '%s' pour '%s'." % [lineage_id, god_id])
	return result


static func _read() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("EconomyConfig: impossible d'ouvrir %s." % PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("EconomyConfig: JSON invalide.")
		return {}
	return parsed
