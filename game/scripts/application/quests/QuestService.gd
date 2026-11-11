## QuestService.gd
## Orchestration des quêtes : gel du tirage quotidien, comptage des actions déjà
## validées par le jeu et réclamation atomique des récompenses.
##
## Une réclamation écrit l'état de quête et les monnaies dans le même profil :
## une coupure ne peut ni payer deux fois ni marquer une quête sans payer.
## L'identifiant de transaction réutilise le registre idempotent de l'inventaire.
## Le service est consommé par `preload` : aucun nom global n'est nécessaire.
extends RefCounted

const ConfigModel := preload("res://scripts/data/quests/QuestConfig.gd")
const StateModel := preload("res://scripts/domain/quests/QuestState.gd")
const Rules := preload("res://scripts/domain/quests/QuestRules.gd")
const DrawModel := preload("res://scripts/domain/quests/QuestDraw.gd")
const Calendar := preload("res://scripts/domain/quests/QuestCalendar.gd")
const MetricsModel := preload("res://scripts/application/quests/QuestMetrics.gd")
const InventoryModel := preload("res://scripts/domain/economy/PlayerInventory.gd")

const TRANSACTION_PREFIX := "quest:"
## La manche parfaite exige le score maximal du jeu : 16 à 0 sur un plateau
## complet de 4 × 4. Les plateaux réduits du tutoriel ne comptent jamais.
const PERFECT_SCORE := 16
const PERFECT_BOARD_SIZE := 4

var _metrics := MetricsModel.new()


## Projection complète consommée par l'écran et par la pastille de navigation.
func view() -> Dictionary:
	_metrics = MetricsModel.new()
	var state := StateModel.from_dict(PlayerData.quests_dict())
	if _ensure_daily(state):
		var rollover_error := _commit(state)
		if rollover_error != OK:
			return {"ok": false, "reason": "Quêtes non enregistrées (%s)."
				% error_string(rollover_error), "daily": [], "unique": [],
				"claimable": 0, "seconds_to_reset": Calendar.seconds_to_reset()}
	var daily: Array = []
	for quest_id in state.daily_ids:
		var definition := ConfigModel.definition(quest_id)
		if not definition.is_empty():
			daily.append(_entry(definition, state, true))
	var unique: Array = []
	for definition in ConfigModel.uniques():
		if definition is Dictionary:
			unique.append(_entry(definition, state, false))
	var claimable := 0
	for entry in daily + unique:
		claimable += int(entry.get("claimable_tiers", 0))
	return {"ok": true, "reason": "", "daily": daily, "unique": unique,
		"claimable": claimable, "seconds_to_reset": Calendar.seconds_to_reset(),
		"day_index": state.day_index}


func claimable_count() -> int:
	return int(view().get("claimable", 0))


## `kind` identifie l'action déjà acceptée par le jeu. `key` est l'identifiant
## d'idempotence de cette action : une nouvelle tentative ne compte pas deux fois.
func record_event(kind: String, payload: Dictionary, key: String = "") -> Error:
	_metrics = MetricsModel.new()
	var state := StateModel.from_dict(PlayerData.quests_dict())
	var rolled := _ensure_daily(state)
	var increments := _event_counters(kind, payload)
	if increments.is_empty() and not rolled:
		return OK
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	var transaction := TRANSACTION_PREFIX + key
	if key != "" and next.has_transaction(transaction):
		return OK
	for metric in increments:
		state.bump(str(metric), int(increments[metric]), false)
		state.bump(str(metric), int(increments[metric]), true)
	if key != "":
		next.mark_transaction(transaction)
	return PlayerData.commit_economy(next, null, state.to_dict())


func claim(quest_id: String) -> Dictionary:
	var definition := ConfigModel.definition(quest_id)
	if definition.is_empty():
		return _fail("Quête inconnue.")
	_metrics = MetricsModel.new()
	var state := StateModel.from_dict(PlayerData.quests_dict())
	_ensure_daily(state)
	var daily := state.daily_ids.has(quest_id)
	if not daily and _in_daily_pool(quest_id):
		return _fail("Cette quête n'est pas active aujourd'hui.")
	var claimed := state.claimed_tier(quest_id, daily)
	var tier := Rules.next_tier(definition, claimed)
	if tier < 0:
		return _fail("Cette quête est déjà terminée.")
	if _value(definition, state, daily) < Rules.threshold(definition, tier):
		return _fail("Cette quête n'est pas terminée.")
	var bonus := ConfigModel.candle_reward() if daily \
		and quest_id == state.daily_carrier else 0
	var reward := Rules.reward(definition, tier, bonus)
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	var transaction := "%s%s:%d" % [TRANSACTION_PREFIX, quest_id, tier]
	var already_paid := next.has_transaction(transaction)
	if not already_paid:
		next.souls += int(reward["souls"])
		next.candles += int(reward["candles"])
		next.mark_transaction(transaction)
	state.mark_claimed(quest_id, tier + 1, daily)
	var error := PlayerData.commit_economy(next, null, state.to_dict())
	if error != OK:
		return _fail("Récompense non enregistrée (%s)." % error_string(error))
	return {"ok": true, "reason": "", "already_paid": already_paid,
		"souls": 0 if already_paid else int(reward["souls"]),
		"candles": 0 if already_paid else int(reward["candles"])}


## ─── Journal quotidien ───────────────────────────────────────────────────────

func _ensure_daily(state: StateModel) -> bool:
	var today := Calendar.today()
	if state.day_index == today:
		return false
	var eligible := Callable(self, "_eligible")
	var previous: Array = DrawModel.draw(ConfigModel.dailies(), today - 1,
		ConfigModel.daily_count(), eligible, []).get("ids", [])
	var drawn := DrawModel.draw(ConfigModel.dailies(), today,
		ConfigModel.daily_count(), eligible, previous)
	state.reset_daily(today, _string_array(drawn.get("ids", [])),
		str(drawn.get("carrier", "")))
	return true


## Le tirage ne propose jamais une quête que le joueur ne peut pas réaliser
## aujourd'hui : ni mode non atteint, ni Rituel sans bougies, ni achat sans âmes.
func _eligible(quest: Dictionary) -> bool:
	if PlayerData.souls() < int(quest.get("min_souls", 0)):
		return false
	if PlayerData.candles() < int(quest.get("min_candles", 0)):
		return false
	if PlayerData.unlocked_god_ids().size() < int(quest.get("min_gods", 0)):
		return false
	return _metrics.value("campaign_nodes") >= int(quest.get("min_nodes", 0))


func _entry(definition: Dictionary, state: StateModel, daily: bool) -> Dictionary:
	var quest_id := str(definition.get("id", ""))
	var claimed := state.claimed_tier(quest_id, daily)
	var tier := Rules.next_tier(definition, claimed)
	var total_tiers := Rules.tiers(definition).size()
	var finished := tier < 0
	var display := claimed if not finished else total_tiers - 1
	var value := _value(definition, state, daily)
	var claimable_tiers := Rules.claimable_count(definition, claimed, value)
	var bonus := ConfigModel.candle_reward() if daily \
		and quest_id == state.daily_carrier else 0
	var reward := {"souls": 0, "candles": 0}
	if not finished:
		reward = Rules.reward(definition, display, bonus)
	return {
		"id": quest_id,
		"title": str(definition.get("title", "")),
		"description": str(definition.get("description", "")),
		"kind": "daily" if daily else "unique",
		"value": value,
		"threshold": maxi(1, Rules.threshold(definition, display)),
		"tier_index": claimed,
		"tiers": total_tiers,
		"claimable_tiers": claimable_tiers,
		"claimable": claimable_tiers > 0,
		"finished": finished,
		"carrier": daily and quest_id == state.daily_carrier,
		"souls": int(reward["souls"]),
		"candles": int(reward["candles"]),
	}


func _value(definition: Dictionary, state: StateModel, daily: bool) -> int:
	var metric := str(definition.get("metric", ""))
	if daily:
		return state.counter(metric, true)
	if MetricsModel.is_derived(metric):
		return _metrics.value(metric)
	return state.counter(metric, false)


func _in_daily_pool(quest_id: String) -> bool:
	for quest in ConfigModel.dailies():
		if quest is Dictionary and str(quest.get("id", "")) == quest_id:
			return true
	return false


static func _string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for value in raw:
			result.append(str(value))
	return result


func _commit(state: StateModel, inventory: Variant = null) -> Error:
	if inventory is PlayerInventory:
		return PlayerData.commit_economy(inventory, null, state.to_dict())
	return PlayerData.commit_economy(
		InventoryModel.from_dict(PlayerData.inventory_dict()), null, state.to_dict())


## ─── Traduction des actions du jeu en métriques ──────────────────────────────

func _event_counters(kind: String, payload: Dictionary) -> Dictionary:
	var result := {}
	match kind:
		"campaign_result":
			_add(result, "captures", int(payload.get("captures", 0)))
			if int(payload.get("winner", 0)) != GameState.PLAYER_HUMAN:
				return result
			_add(result, "campaign_wins", 1)
			if str(payload.get("opponent_god_id", "")) != "":
				_add(result, "god_wins", 1)
			if bool(payload.get("boss", false)):
				_add(result, "boss_wins", 1)
			if int(payload.get("score_local", 0)) \
					- int(payload.get("score_opponent", 0)) >= 6:
				_add(result, "high_diff_wins", 1)
			if bool(payload.get("series_complete", false)):
				var series := str(payload.get("series", ""))
				if series == SeriesRules.SERIES_FT2:
					_add(result, "series_ft2_wins", 1)
				elif series == SeriesRules.SERIES_FT3:
					_add(result, "series_ft3_wins", 1)
			_add(result, _mode_wins_metric(str(payload.get("mode", ""))), 1)
			if _is_perfect(payload):
				_add(result, "perfect_rounds", 1)
		"pvp_result":
			_add(result, "pvp_matches", 1)
			if _is_perfect(payload):
				_add(result, "perfect_rounds", 1)
		"shop_purchase":
			_add(result, "shop_offers", 1)
			_add(result, "copies_gained", int(payload.get("copies", 0)))
			_add(result, "souls_spent", int(payload.get("souls", 0)))
		"ritual_purchase":
			_add(result, "rituals", 1)
		"upgrade_purchase":
			_add(result, "upgrades", 1)
			_add(result, "souls_spent", int(payload.get("souls", 0)))
	return result


static func _mode_wins_metric(mode: String) -> String:
	if mode == GameModeRules.MODE_CLASSIC:
		return "mode_wins_classic"
	if mode == GameModeRules.MODE_RANDOM:
		return "mode_wins_random"
	if mode == GameModeRules.MODE_MIRROR:
		return "mode_wins_mirror"
	if mode == GameModeRules.MODE_DRAFT:
		return "mode_wins_draft"
	return ""


static func _is_perfect(payload: Dictionary) -> bool:
	if int(payload.get("board_size", PERFECT_BOARD_SIZE)) != PERFECT_BOARD_SIZE:
		return false
	return int(payload.get("score_local", 0)) == PERFECT_SCORE \
		and int(payload.get("score_opponent", 0)) == 0


static func _add(target: Dictionary, metric: String, amount: int) -> void:
	if metric == "" or amount <= 0:
		return
	target[metric] = int(target.get(metric, 0)) + amount


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "souls": 0, "candles": 0}
