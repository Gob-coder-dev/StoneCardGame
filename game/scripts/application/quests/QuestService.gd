## QuestService.gd
## Orchestration des quêtes : gel du tirage quotidien, comptage des actions déjà
## validées par le jeu et réclamation atomique des récompenses.
##
## Une réclamation écrit l'état de quête, les monnaies et les récompenses de
## contenu dans le même profil : une coupure ne peut ni payer deux fois ni
## marquer une quête sans payer.
## L'identifiant de transaction réutilise le registre idempotent de l'inventaire.
## Le service est consommé par `preload` : aucun nom global n'est nécessaire.
extends RefCounted

const ConfigModel := preload("res://scripts/data/quests/QuestConfig.gd")
const StateModel := preload("res://scripts/domain/quests/QuestState.gd")
const Rules := preload("res://scripts/domain/quests/QuestRules.gd")
const DrawModel := preload("res://scripts/domain/quests/QuestDraw.gd")
const Calendar := preload("res://scripts/domain/quests/QuestCalendar.gd")
const MetricsModel := preload("res://scripts/application/quests/QuestMetrics.gd")
const RitualServiceModel := preload("res://scripts/application/economy/RitualService.gd")
const RitualConfigModel := preload("res://scripts/data/economy/RitualConfig.gd")
const Compensation := preload("res://scripts/domain/economy/CardCompensation.gd")
const InventoryModel := preload("res://scripts/domain/economy/PlayerInventory.gd")
const AccessServiceModel := preload("res://scripts/application/progression/ProgressionAccessService.gd")

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
	var changed := _sync_gate_activations(state)
	changed = _ensure_daily(state) or changed
	if changed:
		var rollover_error := _commit(state)
		if rollover_error != OK:
			return {"ok": false, "reason": "Quêtes non enregistrées (%s)."
				% error_string(rollover_error), "daily": [], "unique": [],
				"claimable": 0, "seconds_to_reset": Calendar.seconds_to_reset()}
	var inventory := InventoryModel.from_dict(PlayerData.inventory_dict())
	var daily: Array = []
	for quest_id in state.daily_ids:
		var definition := ConfigModel.definition(quest_id)
		if not definition.is_empty():
			daily.append(_entry(definition, state, true, inventory))
	var unique: Array = []
	for definition in ConfigModel.uniques():
		if definition is Dictionary and _is_accessible(definition):
			unique.append(_entry(definition, state, false, inventory))
	# Les paliers récoltables passent devant, puis les objectifs en cours ;
	# l'ordre du catalogue départage les égalités de façon stable.
	for index in range(unique.size()):
		unique[index]["sort_order"] = index
	unique.sort_custom(_sort_uniques)
	for entry in unique:
		entry.erase("sort_order")
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
	var rolled := _sync_gate_activations(state)
	rolled = _ensure_daily(state) or rolled
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
	if not _is_accessible(definition):
		return _fail("Cette quête n'est pas encore accessible.")
	_metrics = MetricsModel.new()
	var state := StateModel.from_dict(PlayerData.quests_dict())
	_sync_gate_activations(state)
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
	var granted: Array = []
	var opening: Dictionary = {}
	if not already_paid:
		next.souls += int(reward["souls"])
		next.candles += int(reward["candles"])
		var cards := _grant_cards(next, reward.get("cards", []))
		if not bool(cards.get("ok", false)):
			return _fail(str(cards.get("reason", "Récompense de carte impossible.")))
		granted = cards.get("cards", [])
		var ritual_id := str(reward.get("ritual", ""))
		if ritual_id != "":
			var prepared := RitualServiceModel.grant(ritual_id, next,
				hash("quest|%s|%d" % [quest_id, tier]))
			if not bool(prepared.get("ok", false)):
				return _fail(str(prepared.get("reason", "Rituel indisponible.")))
			opening = (prepared.get("opening", {}) as Dictionary).duplicate(true)
			opening["return_to"] = "quests"
		next.mark_transaction(transaction)
	state.mark_claimed(quest_id, tier + 1, daily)
	var error := PlayerData.commit_economy(next, null, state.to_dict())
	if error != OK:
		return _fail("Récompense non enregistrée (%s)." % error_string(error))
	return {"ok": true, "reason": "", "already_paid": already_paid,
		"souls": 0 if already_paid else int(reward["souls"]),
		"candles": 0 if already_paid else int(reward["candles"]),
		"cards": granted, "opening": opening}


## ─── Tri de la liste ─────────────────────────────────────────────────────────

static func _sort_uniques(a: Variant, b: Variant) -> bool:
	var left: Dictionary = a
	var right: Dictionary = b
	var left_rank := _unique_rank(left)
	var right_rank := _unique_rank(right)
	if left_rank != right_rank:
		return left_rank < right_rank
	return int(left.get("sort_order", 0)) < int(right.get("sort_order", 0))


static func _unique_rank(entry: Dictionary) -> int:
	if bool(entry.get("claimable", false)):
		return 0
	return 2 if bool(entry.get("finished", false)) else 1


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
	if not _is_accessible(quest):
		return false
	if PlayerData.souls() < int(quest.get("min_souls", 0)):
		return false
	if PlayerData.candles() < int(quest.get("min_candles", 0)):
		return false
	if PlayerData.unlocked_god_ids().size() < int(quest.get("min_gods", 0)):
		return false
	return _metrics.value("campaign_nodes") >= int(quest.get("min_nodes", 0))


func _entry(definition: Dictionary, state: StateModel, daily: bool,
		inventory: PlayerInventory) -> Dictionary:
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
	var reward := {"souls": 0, "candles": 0, "cards": [], "ritual": ""}
	if not finished:
		reward = Rules.reward(definition, display, bonus)
	var cards: Array = []
	for raw_card in reward.get("cards", []):
		var card := _card_entry(raw_card, inventory)
		if not card.is_empty():
			cards.append(card)
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
		"cards": cards,
		"ritual": _ritual_entry(str(reward.get("ritual", ""))),
	}


func _value(definition: Dictionary, state: StateModel, daily: bool) -> int:
	var metric := str(definition.get("metric", ""))
	var raw := 0
	if daily:
		raw = state.counter(metric, true)
	elif MetricsModel.is_derived(metric):
		raw = _metrics.value(metric)
	else:
		raw = state.counter(metric, false)
	if not daily and str(definition.get("progress_policy", "lifetime")) == "since_gate":
		raw = maxi(0, raw - state.activation_baseline(str(definition.get("id", ""))))
	return raw


func _is_accessible(definition: Dictionary) -> bool:
	return AccessServiceModel.new().is_gate_unlocked(
		str(definition.get("required_gate", "")))


## Active chaque défi conditionnel une seule fois et photographie sa métrique.
## Les statistiques historiques restent partagées, mais ne peuvent pas remplir
## rétroactivement un objectif qui n'existait pas encore pour le joueur.
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


## ─── Récompenses de contenu ──────────────────────────────────────────────────

func _card_entry(raw: Variant, inventory: PlayerInventory) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var lineage_id := str((raw as Dictionary).get("lineage_id", ""))
	var copies := maxi(0, int((raw as Dictionary).get("copies", 0)))
	if lineage_id == "" or copies <= 0:
		return {}
	var stone_id := StoneLoader.variant_id(lineage_id, 1)
	if stone_id == "":
		return {}
	var stone := StoneLoader.get_stone(stone_id)
	var affinity := StoneLoader.stone_affinity(stone_id)
	var maxed := inventory.unlocked_level(lineage_id) \
		>= StoneLoader.lineage_max_level(lineage_id)
	return {
		"lineage_id": lineage_id,
		"copies": copies,
		"name": str(stone.get("name", lineage_id)),
		"asset": str(stone.get("asset", "")),
		"rarity": str(stone.get("rarity", "common")),
		"god_id": affinity,
		"deferred": affinity != "neutral" and not inventory.has_god(affinity),
		"maxed": maxed,
		"compensation_souls": Compensation.souls_for(lineage_id, copies) if maxed else 0,
	}


func _ritual_entry(ritual_id: String) -> Dictionary:
	if ritual_id == "":
		return {}
	var definition := RitualConfigModel.definition(ritual_id)
	if definition.is_empty():
		return {}
	return {"id": ritual_id, "name": str(definition.get("name", "Rituel")),
		"sigil": str(definition.get("sigil", "triangle")),
		"color": str(definition.get("blood_color", "#a62f35"))}


func _grant_cards(inventory: PlayerInventory, raw_cards: Variant) -> Dictionary:
	var granted: Array = []
	if not raw_cards is Array:
		return {"ok": true, "cards": granted}
	for raw in raw_cards:
		if not raw is Dictionary:
			return {"ok": false, "reason": "Récompense de carte invalide."}
		var lineage_id := str((raw as Dictionary).get("lineage_id", ""))
		var copies := maxi(0, int((raw as Dictionary).get("copies", 0)))
		if lineage_id == "" or copies <= 0:
			return {"ok": false, "reason": "Récompense de carte invalide."}
		var stone_id := StoneLoader.variant_id(lineage_id, 1)
		if stone_id == "":
			return {"ok": false, "reason": "Carte inconnue : %s." % lineage_id}
		var affinity := StoneLoader.stone_affinity(stone_id)
		var resolved: Dictionary = (raw as Dictionary).duplicate(true)
		resolved["name"] = str(StoneLoader.get_stone(stone_id).get("name", lineage_id))
		if inventory.unlocked_level(lineage_id) >= StoneLoader.lineage_max_level(lineage_id):
			var compensation := Compensation.souls_for(lineage_id, copies)
			inventory.souls += compensation
			resolved["maxed"] = true
			resolved["compensation_souls"] = compensation
		elif affinity != "neutral" and not inventory.has_god(affinity):
			if not inventory.defer_copies(lineage_id, copies):
				return {"ok": false, "reason": "Carte impossible à réserver : %s." % lineage_id}
			resolved["deferred"] = true
			resolved["god_id"] = affinity
		elif not inventory.add_copies(lineage_id, copies):
			return {"ok": false, "reason": "Carte impossible à ajouter : %s." % lineage_id}
		granted.append(resolved)
	return {"ok": true, "cards": granted}


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
	return {"ok": false, "reason": reason, "souls": 0, "candles": 0,
		"cards": [], "opening": {}}
