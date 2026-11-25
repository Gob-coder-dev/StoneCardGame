## Récompenses de campagne : âmes déterministes, bougies par chapitre, cartes de
## première victoire et protection idempotente via l'inventaire du profil.
class_name CampaignRewardService
extends RefCounted

const Economy := preload("res://scripts/application/economy/EconomyService.gd")
const Config := preload("res://scripts/data/economy/EconomyConfig.gd")


## Prépare la récompense et son reçu pour la même écriture que le résultat.
static func prepare_victory(service: CampaignService, node_id: String,
		first_victory: bool, attempt: int) -> Dictionary:
	if service == null or not service.has_node(node_id):
		return {"ok": false, "reason": "Niveau de campagne inconnu.", "error": ERR_DOES_NOT_EXIST}
	var node := service.node(node_id)
	var reward := node.reward_definition()
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
				starter_cards.append(MonsterLoader.variant_id(
					str(card_reward.get("lineage_id", "")), 1))
	var result := Economy.new().prepare_reward(transaction_id, souls, cards,
		starter_cards, candles)
	if result["ok"]:
		result["receipt"]["first_victory"] = first_victory
		result["receipt"]["transaction_id"] = transaction_id
	return result


## Accepte le format actuel (lignee + copies) et l'ancien identifiant de forme
## afin que les fixtures et les sauvegardes de developpement restent lisibles.
static func _normalize_card_reward(raw_reward: Variant) -> Dictionary:
	if raw_reward is Dictionary:
		var lineage_id := str(raw_reward.get("lineage_id", ""))
		var copies := int(raw_reward.get("copies", 0))
		if MonsterLoader.lineage_max_level(lineage_id) > 0 and copies > 0:
			return {"lineage_id": lineage_id, "copies": copies}
		return {}
	var monster_id := str(raw_reward)
	if MonsterLoader.has_monster(monster_id):
		return {"lineage_id": MonsterLoader.monster_lineage(monster_id), "copies": 1}
	return {}


static func _candles_for_chapter(chapter: String) -> int:
	return Config.campaign_candles(chapter)


static func _deterministic_amount(key: String, minimum: int, maximum: int) -> int:
	if maximum <= minimum:
		return minimum
	var span := maximum - minimum + 1
	return minimum + posmod(key.hash(), span)
