## Récompenses de campagne : âmes déterministes, bougies par chapitre, cartes de
## première victoire et protection idempotente via l'inventaire du profil.
class_name CampaignRewardService
extends RefCounted

const Economy := preload("res://scripts/application/economy/EconomyService.gd")
const Config := preload("res://scripts/data/economy/EconomyConfig.gd")


static func apply_victory(service: CampaignService, node_id: String) -> Dictionary:
	if service == null or not service.has_node(node_id):
		return {"ok": false, "reason": "Niveau de campagne inconnu.", "error": ERR_DOES_NOT_EXIST}
	var node := service.node(node_id)
	var reward := node.reward_definition()
	var first_victory := not service.is_completed(node_id)
	var attempt := maxi(1, service.progress().attempts_for(node_id))
	var transaction_id := "campaign:%d:%s:%s" % [service.graph().campaign_version,
		node_id, "first" if first_victory else "replay:%d" % attempt]
	var minimum := maxi(0, int(reward.get("souls_min", 0)))
	var maximum := maxi(minimum, int(reward.get("souls_max", minimum)))
	var souls := _deterministic_amount(transaction_id, minimum, maximum)
	var candles := _candles_for_chapter(node.chapter)
	if not first_victory:
		souls = int(round(float(souls) * float(Config.get_config().get("repeat_reward_multiplier", 0.25))))
	var cards: Array = []
	var starter_cards: Array = []
	if first_victory:
		for raw_reward in reward.get("card_rewards", []):
			var normalized := _normalize_card_reward(raw_reward)
			if normalized.is_empty():
				return {"ok": false, "reason": "Récompense de carte inconnue.",
					"error": ERR_INVALID_DATA}
			cards.append(normalized)
		if node_id == "tuto_01":
			# Les trois premières complètent automatiquement le deck ; la quatrième
			# reste dans la collection pour faire découvrir l'éditeur de deck.
			for card_reward in cards.slice(0, 3):
				starter_cards.append(StoneLoader.variant_id(
					str(card_reward.get("lineage_id", "")), 1))
	var result := Economy.new().grant_reward(transaction_id, souls, cards,
		starter_cards, candles)
	result["first_victory"] = first_victory
	result["transaction_id"] = transaction_id
	return result


## Accepte le format actuel (lignee + copies) et l'ancien identifiant de forme
## afin que les fixtures et les sauvegardes de developpement restent lisibles.
static func _normalize_card_reward(raw_reward: Variant) -> Dictionary:
	if raw_reward is Dictionary:
		var lineage_id := str(raw_reward.get("lineage_id", ""))
		var copies := int(raw_reward.get("copies", 0))
		if StoneLoader.lineage_max_level(lineage_id) > 0 and copies > 0:
			return {"lineage_id": lineage_id, "copies": copies}
		return {}
	var stone_id := str(raw_reward)
	if StoneLoader.has_stone(stone_id):
		return {"lineage_id": StoneLoader.stone_lineage(stone_id), "copies": 1}
	return {}


static func _candles_for_chapter(chapter: String) -> int:
	var values: Variant = Config.get_config().get("campaign_candles_by_chapter", {})
	if not values is Dictionary:
		return 1
	return maxi(1, int(values.get(chapter, 1)))


static func _deterministic_amount(key: String, minimum: int, maximum: int) -> int:
	if maximum <= minimum:
		return minimum
	var span := maximum - minimum + 1
	return minimum + posmod(key.hash(), span)
