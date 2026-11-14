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
const Calendar := preload("res://scripts/domain/quests/QuestCalendar.gd")
const MetricsModel := preload("res://scripts/application/quests/QuestMetrics.gd")
const RitualServiceModel := preload("res://scripts/application/economy/RitualService.gd")
const RitualConfigModel := preload("res://scripts/data/economy/RitualConfig.gd")
const Compensation := preload("res://scripts/domain/economy/CardCompensation.gd")
const InventoryModel := preload("res://scripts/domain/economy/PlayerInventory.gd")
const AccessServiceModel := preload("res://scripts/application/progression/ProgressionAccessService.gd")

const Journal := preload("res://scripts/application/quests/QuestJournal.gd")
const CardGrant := preload("res://scripts/domain/economy/CardRewardGrant.gd")
const TRANSACTION_PREFIX := "quest:"

var _metrics := MetricsModel.new()
var _journal: Journal


func _init(day_override: int = -1) -> void:
	_journal = Journal.new(day_override)


## Projection complète consommée par l'écran et par la pastille de navigation.
func view() -> Dictionary:
	_metrics = MetricsModel.new()
	var state := StateModel.from_dict(PlayerData.quests_dict())
	var changed := _journal.sync(state)
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
	var state := StateModel.from_dict(PlayerData.quests_dict())
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	if not _journal.stage_event(state, next, kind, payload, key):
		return OK
	return PlayerData.commit_economy(next, null, state.to_dict())


func claim(quest_id: String) -> Dictionary:
	var definition := ConfigModel.definition(quest_id)
	if definition.is_empty():
		return _fail("Quête inconnue.")
	if not _is_accessible(definition):
		return _fail("Cette quête n'est pas encore accessible.")
	_metrics = MetricsModel.new()
	var state := StateModel.from_dict(PlayerData.quests_dict())
	_journal.sync(state)
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
	var already_paid := not daily and next.has_transaction(transaction)
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
		# daily_claimed et day_index forment ensemble la preuve atomique du paiement.
		# Les anciennes clés sans date ne doivent jamais bloquer un nouveau jour.
		if not daily:
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


## Projection d'une quête et de son prochain palier pour l'interface.
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


func _in_daily_pool(quest_id: String) -> bool:
	for quest in ConfigModel.dailies():
		if quest is Dictionary and str(quest.get("id", "")) == quest_id:
			return true
	return false


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
		var result := CardGrant.apply(inventory, raw)
		if not bool(result.get("ok", false)):
			return result
		var reward: Dictionary = result["reward"]
		var first := StoneLoader.variant_id(str(reward["lineage_id"]), 1)
		reward["name"] = str(StoneLoader.get_stone(first).get("name", ""))
		granted.append(reward)
	return {"ok": true, "cards": granted}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "souls": 0, "candles": 0,
		"cards": [], "opening": {}}
