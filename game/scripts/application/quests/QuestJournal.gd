## Journal des quêtes : activation, tirage quotidien et application des événements.
## Prépare un état candidat sans écriture ; achats et résultats peuvent ainsi
## enregistrer leurs compteurs dans la même transaction que leur effet métier.
extends RefCounted

const ConfigModel := preload("res://scripts/data/quests/QuestConfig.gd")
const StateModel := preload("res://scripts/domain/quests/QuestState.gd")
const DrawModel := preload("res://scripts/domain/quests/QuestDraw.gd")
const Calendar := preload("res://scripts/domain/quests/QuestCalendar.gd")
const MetricsModel := preload("res://scripts/application/quests/QuestMetrics.gd")
const AccessServiceModel := preload("res://scripts/application/progression/ProgressionAccessService.gd")
const Events := preload("res://scripts/domain/quests/QuestEventRules.gd")

var _metrics := MetricsModel.new()
var _day_override := -1


## Une date injectable rend les changements de jour reproductibles dans les tests.
func _init(day_override: int = -1) -> void:
	_day_override = day_override


func sync(state: StateModel) -> bool:
	_metrics = MetricsModel.new()
	var changed := _sync_gate_activations(state)
	return _ensure_daily(state) or changed


func stage_event(state: StateModel, inventory: PlayerInventory, kind: String,
		payload: Dictionary, key: String = "") -> bool:
	var changed := sync(state)
	var transaction := "quest:" + key
	if key != "" and inventory.has_transaction(transaction):
		return changed
	var increments := Events.increments(kind, payload)
	for metric in increments:
		state.bump(str(metric), int(increments[metric]), false)
		state.bump(str(metric), int(increments[metric]), true)
	if key != "" and not increments.is_empty():
		inventory.mark_transaction(transaction)
	return changed or not increments.is_empty()


func _ensure_daily(state: StateModel) -> bool:
	var today := _day_override if _day_override >= 0 else Calendar.today()
	# Un recul de l'horloge ne réouvre pas une journée déjà récompensée.
	if state.day_index >= today:
		return false
	var eligible := Callable(self, "_eligible")
	var previous: Array = DrawModel.draw(ConfigModel.dailies(), today - 1,
		ConfigModel.daily_count(), eligible, []).get("ids", [])
	var drawn := DrawModel.draw(ConfigModel.dailies(), today,
		ConfigModel.daily_count(), eligible, previous)
	state.reset_daily(today, _string_array(drawn.get("ids", [])),
		str(drawn.get("carrier", "")))
	return true


## Le tirage écarte les objectifs que le profil ne peut pas encore réaliser.
func _eligible(quest: Dictionary) -> bool:
	if not _is_accessible(quest):
		return false
	if PlayerData.souls() < int(quest.get("min_souls", 0)):
		return false
	if PlayerData.candles() < int(quest.get("min_candles", 0)):
		return false
	if PlayerData.unlocked_god_ids().size() < int(quest.get("min_gods", 0)):
		return false
	return _metrics.value("campaign_nodes") >= int(quest.get("min_nodes", 0))


func _is_accessible(definition: Dictionary) -> bool:
	return AccessServiceModel.new().is_gate_unlocked(
		str(definition.get("required_gate", "")))


func _sync_gate_activations(state: StateModel) -> bool:
	var changed := false
	for raw in ConfigModel.uniques():
		if not raw is Dictionary:
			continue
		var definition: Dictionary = raw
		var quest_id := str(definition.get("id", ""))
		if str(definition.get("progress_policy", "lifetime")) != "since_gate" \
				or state.is_activated(quest_id) or not _is_accessible(definition):
			continue
		var metric := str(definition.get("metric", ""))
		var baseline := _metrics.value(metric) if MetricsModel.is_derived(metric) \
			else state.counter(metric, false)
		state.activate(quest_id, baseline)
		changed = true
	return changed


static func _string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for value in raw:
			result.append(str(value))
	return result
