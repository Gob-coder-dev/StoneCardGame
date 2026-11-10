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
		for raw_stone_id in reward.get("card_rewards", []):
			var stone_id := str(raw_stone_id)
			if not StoneLoader.has_stone(stone_id):
				return {"ok": false, "reason": "Récompense inconnue : %s." % stone_id,
					"error": ERR_INVALID_DATA}
			cards.append({"lineage_id": StoneLoader.stone_lineage(stone_id), "copies": 1})
		if node_id == "tuto_01":
			# Les trois premières complètent automatiquement le deck ; la quatrième
			# reste dans la collection pour faire découvrir l'éditeur de deck.
			starter_cards = (reward.get("card_rewards", []) as Array).slice(0, 3)
	var result := Economy.new().grant_reward(transaction_id, souls, cards,
		starter_cards, candles)
	result["first_victory"] = first_victory
	result["transaction_id"] = transaction_id
	return result


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
