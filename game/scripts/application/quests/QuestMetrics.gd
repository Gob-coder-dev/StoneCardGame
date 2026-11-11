## QuestMetrics.gd
## Métriques déduites de l'état réel du joueur. Aucune n'est stockée : une
## collection déjà complète est donc comptée immédiatement, sans migration ni
## script de rattrapage. Les compteurs d'événements, eux, vivent dans QuestState.
class_name QuestMetrics
extends RefCounted

const EVENT_METRICS: Array[String] = [
	"god_wins", "campaign_wins", "high_diff_wins", "captures", "shop_offers",
	"copies_gained", "souls_spent", "upgrades", "rituals", "mode_wins_classic",
	"mode_wins_random", "mode_wins_mirror", "mode_wins_draft", "pvp_matches",
	"boss_wins", "perfect_rounds", "series_ft2_wins", "series_ft3_wins",
]

const DERIVED_METRICS: Array[String] = [
	"tutorial_done", "n2_owned", "n3_owned", "n4_owned", "neutral_owned",
	"aleator_owned", "legendary_owned", "campaign_nodes", "lineages_owned",
	"gods_unlocked", "total_captures", "best_streak",
]

const FAMILY_PREFIX := "family_owned_"

## Niveaux débloqués et liste des lignées, lus une seule fois par instance.
## Le service recrée la projection à chaque lecture : aucun cache ne survit à
## une modification de l'inventaire.
var _levels: Dictionary = {}
var _lineages_cache: Array[String] = []


static func is_derived(metric: String) -> bool:
	return DERIVED_METRICS.has(metric) or metric.begins_with(FAMILY_PREFIX)


static func is_known(metric: String) -> bool:
	return EVENT_METRICS.has(metric) or is_derived(metric)


func value(metric: String) -> int:
	if metric.begins_with(FAMILY_PREFIX):
		return _family_owned(metric.trim_prefix(FAMILY_PREFIX))
	match metric:
		"tutorial_done":
			return 1 if _tutorial_completed() else 0
		"n2_owned":
			return _owned_at_level(2)
		"n3_owned":
			return _owned_at_level(3)
		"n4_owned":
			return _owned_at_level(4)
		"neutral_owned":
			return _family_owned("neutral")
		"aleator_owned":
			return _family_owned("veskar")
		"legendary_owned":
			return _legendary_owned()
		"campaign_nodes":
			return _campaign_nodes()
		"lineages_owned":
			return _owned_at_level(1)
		"gods_unlocked":
			return PlayerData.unlocked_god_ids().size()
		"total_captures":
			return maxi(0, int(PlayerData.stats.get("total_captures", 0)))
		"best_streak":
			return maxi(0, int(PlayerData.stats.get("best_streak", 0)))
	return 0


func _lineages() -> Array[String]:
	if _lineages_cache.is_empty():
		_lineages_cache = StoneLoader.lineage_ids()
	return _lineages_cache


func _unlocked(lineage_id: String) -> int:
	if not _levels.has(lineage_id):
		_levels[lineage_id] = int(PlayerData.card_entry(lineage_id)
			.get("unlocked_level", 0))
	return int(_levels[lineage_id])


func _owned_at_level(level: int) -> int:
	var total := 0
	for lineage_id in _lineages():
		if _unlocked(lineage_id) >= level:
			total += 1
	return total


func _family_owned(god_id: String) -> int:
	var total := 0
	for lineage_id in _lineages():
		if _unlocked(lineage_id) <= 0:
			continue
		if _affinity(lineage_id) == god_id:
			total += 1
	return total


func _legendary_owned() -> int:
	var total := 0
	for lineage_id in _lineages():
		if _unlocked(lineage_id) <= 0:
			continue
		var first := StoneLoader.variant_id(lineage_id, 1)
		if first != "" and StoneLoader.stone_rarity(first) == "legendary":
			total += 1
	return total


func _affinity(lineage_id: String) -> String:
	var first := StoneLoader.variant_id(lineage_id, 1)
	return StoneLoader.stone_affinity(first) if first != "" else ""


func _tutorial_completed() -> bool:
	var service := CampaignContext.get_service()
	return service != null and service.is_ready() and service.is_completed("tuto_05")


func _campaign_nodes() -> int:
	var service := CampaignContext.get_service()
	if service == null or not service.is_ready():
		return 0
	return service.progress().completed.size()
