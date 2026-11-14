## QuestState.gd
## Valeur sérialisable de la progression des quêtes. Les compteurs ne
## décroissent jamais et le palier réclamé est un index qui avance de un.
##
## Le tirage quotidien est conservé ici, avec sa date : une quête tirée le matin
## reste la même toute la journée, même si l'inventaire change entre-temps.
class_name QuestState
extends RefCounted

const VERSION := 2
const Integer := preload("res://scripts/domain/IntegerValue.gd")

## Jour local du tirage courant. -1 signifie « jamais initialisé ».
var day_index: int = -1
var daily_ids: Array[String] = []
var daily_carrier: String = ""
var daily_counters: Dictionary = {}
var daily_claimed: Dictionary = {}
var counters: Dictionary = {}
var claimed: Dictionary = {}
## Valeur de la métrique au moment où un défi conditionnel devient accessible.
## Sa présence marque aussi l'activation : une valeur nulle reste donc valide.
var activation_baselines: Dictionary = {}


static func from_dict(raw: Variant) -> QuestState:
	var state := QuestState.new()
	if not raw is Dictionary:
		return state
	var data: Dictionary = raw
	state.day_index = Integer.read(data.get("day_index"), -1, -1)
	var daily: Dictionary = data.get("daily", {}) if data.get("daily") is Dictionary else {}
	var raw_ids: Variant = daily.get("ids", [])
	if raw_ids is Array:
		for value in raw_ids:
			var quest_id := str(value)
			if quest_id != "":
				state.daily_ids.append(quest_id)
	state.daily_carrier = str(daily.get("carrier", ""))
	state.daily_counters = _clean_counters(daily.get("counters", {}))
	state.daily_claimed = _clean_counters(daily.get("claimed", {}))
	state.counters = _clean_counters(data.get("counters", {}))
	state.claimed = _clean_counters(data.get("claimed", {}))
	state.activation_baselines = _clean_counters(data.get("activation_baselines", {}))
	return state


## JSON relit les nombres en float : normaliser ici garde une sauvegarde stable
## et empêche un compteur négatif d'atteindre les règles.
static func _clean_counters(raw: Variant) -> Dictionary:
	var result := {}
	if not raw is Dictionary:
		return result
	for key in raw:
		if key is String:
			result[key] = Integer.read(raw[key])
	return result


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"day_index": day_index,
		"daily": {
			"ids": daily_ids.duplicate(),
			"carrier": daily_carrier,
			"counters": daily_counters.duplicate(),
			"claimed": daily_claimed.duplicate(),
		},
		"counters": counters.duplicate(),
		"claimed": claimed.duplicate(),
		"activation_baselines": activation_baselines.duplicate(),
	}


func duplicate_state() -> QuestState:
	return QuestState.from_dict(to_dict())


func counter(metric: String, daily: bool) -> int:
	var source: Dictionary = daily_counters if daily else counters
	return maxi(0, int(source.get(metric, 0)))


func bump(metric: String, amount: int, daily: bool) -> void:
	if metric == "" or amount <= 0:
		return
	var source: Dictionary = daily_counters if daily else counters
	source[metric] = int(source.get(metric, 0)) + amount


func claimed_tier(quest_id: String, daily: bool) -> int:
	var source: Dictionary = daily_claimed if daily else claimed
	return maxi(0, int(source.get(quest_id, 0)))


func mark_claimed(quest_id: String, tier: int, daily: bool) -> void:
	if quest_id == "":
		return
	var source: Dictionary = daily_claimed if daily else claimed
	source[quest_id] = maxi(0, tier)


func is_activated(quest_id: String) -> bool:
	return activation_baselines.has(quest_id)


func activate(quest_id: String, baseline: int) -> void:
	if quest_id != "" and not activation_baselines.has(quest_id):
		activation_baselines[quest_id] = maxi(0, baseline)


func activation_baseline(quest_id: String) -> int:
	return maxi(0, int(activation_baselines.get(quest_id, 0)))


## Nouveau jour : le tirage et les compteurs quotidiens sont remplacés, les
## compteurs historiques restent intacts.
func reset_daily(index: int, ids: Array[String], carrier: String) -> void:
	day_index = index
	daily_ids = ids.duplicate()
	daily_carrier = carrier
	daily_counters.clear()
	daily_claimed.clear()
