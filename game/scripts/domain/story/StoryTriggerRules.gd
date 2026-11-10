## StoryTriggerRules.gd
## Règles pures de sélection d'un déclencheur de scénario. Aucune scène,
## aucun accès disque : le service fournit le contexte et l'état « déjà vu ».
class_name StoryTriggerRules
extends RefCounted

const EVENTS: Array[String] = [
	"level_start",
	"match_start",
	"turn_start",
	"series_end",
	"level_won",
	"level_lost",
	"level_draw",
]

const WAIT_EVENTS: Array[String] = [
	"anchor_pressed",
	"card_selected",
	"cell_pressed",
	"stone_placed",
	"stone_captured",
	"turn_started",
	"tutorial_advance",
	"screen_opened",
	"campaign_node_opened",
	"prebattle_ready",
	"match_won",
	"collection_card_opened",
	"replacement_opened",
	"deck_card_replaced",
]


static func state_key(trigger_id: String) -> String:
	return "seq:%s:seen" % trigger_id


static func matches(trigger: Dictionary, node_id: String, event: String,
		context: Dictionary = {}) -> bool:
	if trigger.is_empty():
		return false
	var trigger_node := str(trigger.get("node_id", ""))
	if trigger_node != "" and trigger_node != node_id:
		return false
	if str(trigger.get("event", "")) != event:
		return false
	if trigger.has("outcome") \
			and str(trigger.get("outcome", "")) != str(context.get("outcome", "")):
		return false
	var turn := int(context.get("turn", 0))
	if trigger.has("min_turn") and turn < int(trigger.get("min_turn", 0)):
		return false
	if trigger.has("max_turn") and turn > int(trigger.get("max_turn", 0)):
		return false
	return true


static func first_matching(triggers: Array, node_id: String, event: String,
		seen: Dictionary, context: Dictionary = {}) -> Dictionary:
	for value in triggers:
		if not value is Dictionary:
			continue
		var trigger: Dictionary = value
		if not matches(trigger, node_id, event, context):
			continue
		var trigger_id := str(trigger.get("id", ""))
		if bool(trigger.get("once", true)) and bool(seen.get(state_key(trigger_id), false)):
			continue
		return trigger
	return {}
