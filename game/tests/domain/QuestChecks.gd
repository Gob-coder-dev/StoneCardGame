## Contrats des quêtes : horloge locale, tirage déterministe, paliers cumulatifs,
## réclamation atomique et format de sauvegarde version 10.
extends "res://tests/support/CombatTestSuite.gd"

const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const Config := preload("res://scripts/data/quests/QuestConfig.gd")
const Calendar := preload("res://scripts/domain/quests/QuestCalendar.gd")
const StateModel := preload("res://scripts/domain/quests/QuestState.gd")
const Rules := preload("res://scripts/domain/quests/QuestRules.gd")
const DrawModel := preload("res://scripts/domain/quests/QuestDraw.gd")
const Service := preload("res://scripts/application/quests/QuestService.gd")
const InventoryModel := preload("res://scripts/domain/economy/PlayerInventory.gd")
const Fixture := preload("res://tests/support/PlayerProfileFixture.gd")


func run() -> void:
	var fixture := Fixture.new(Codec.starter_profile())
	_test_calendar()
	_test_configuration()
	_test_draw()
	_test_tiers()
	_test_state_round_trip()
	_test_save_format()
	_test_daily()
	_test_claim()
	fixture.restore()


func _test_calendar() -> void:
	_check(Calendar.day_index(0, 0) == 0 and Calendar.day_index(86399, 0) == 0
		and Calendar.day_index(86400, 0) == 1,
		"quêtes : une journée locale commence à minuit")
	_check(Calendar.day_index(23 * 3600, 60) == 1
		and Calendar.day_index(22 * 3600 + 3599, 60) == 0,
		"quêtes : le biais de l'appareil décale la frontière d'une heure")
	_check(Calendar.seconds_until_next_day(0, 0) == 86400
		and Calendar.seconds_until_next_day(86399, 0) == 1,
		"quêtes : le compte à rebours vise le prochain minuit local")


func _test_configuration() -> void:
	var config := Config.get_config()
	_check(Config.problems(config).is_empty(),
		"quêtes : le catalogue livré est cohérent (métriques, paliers, récompenses)")
	_check(Config.daily_count() == 3 and Config.dailies().size() >= 10
		and Config.candle_reward() == 5,
		"quêtes : trois quotidiennes sont tirées d'un vivier large, une seule paie cinq bougies")
	_check(str(Config.definition("daily_pvp").get("metric", "")) == "pvp_matches"
		and str(Config.definition("family_owned_nerava").get("id", "")) == "",
		"quêtes : chaque définition reste identifiée par son métrique")


func _test_draw() -> void:
	var eligible := func(_quest: Dictionary) -> bool: return true
	var first := DrawModel.draw(Config.dailies(), 42, 3, eligible, [])
	var again := DrawModel.draw(Config.dailies(), 42, 3, eligible, [])
	var tomorrow := DrawModel.draw(Config.dailies(), 43, 3, eligible, [])
	_check(first["ids"] == again["ids"] and first["ids"].size() == 3,
		"quêtes : le tirage est stable pour une même journée")
	_check(first["ids"] != tomorrow["ids"],
		"quêtes : le tirage change d'une journée à l'autre")
	var pvp_only := func(quest: Dictionary) -> bool: return quest["id"] == "daily_pvp"
	var forced := DrawModel.draw(Config.dailies(), 42, 3, pvp_only, [])
	_check(forced["ids"] == ["daily_pvp"] and forced["carrier"] == "daily_pvp",
		"quêtes : une quête inéligible n'est jamais proposée")
	_check((first["ids"] as Array).has(str(first["carrier"])),
		"quêtes : le porteur des bougies appartient au tirage du jour")
	var excluded := DrawModel.draw(Config.dailies(), 43, 3, eligible, first["ids"])
	var overlap := false
	for quest_id in excluded["ids"]:
		overlap = overlap or (first["ids"] as Array).has(quest_id)
	_check(not overlap,
		"quêtes : les quêtes de la veille sont écartées quand le vivier suffit")


func _test_tiers() -> void:
	var definition := {"tiers": [{"threshold": 1, "souls": 60},
		{"threshold": 5, "souls": 150}, {"threshold": 10, "candles": 2}]}
	_check(Rules.claimable_count(definition, 0, 0) == 0
		and Rules.claimable_count(definition, 0, 5) == 2
		and Rules.claimable_count(definition, 1, 5) == 1,
		"quêtes : les paliers atteints sont cumulativement réclamables")
	_check(Rules.next_tier(definition, 2) == 2 and Rules.next_tier(definition, 3) == -1,
		"quêtes : une quête terminée ne propose plus de palier")
	_check(int(Rules.reward(definition, 2, 5)["candles"]) == 7,
		"quêtes : les bougies du jour s'ajoutent à la récompense du palier")


func _test_state_round_trip() -> void:
	var state := StateModel.from_dict({})
	state.reset_daily(12, ["a", "b", "c"], "b")
	state.bump("captures", 3, true)
	state.bump("captures", 7, false)
	state.mark_claimed("a", 1, true)
	var loaded := StateModel.from_dict(state.to_dict())
	_check(loaded.day_index == 12 and loaded.daily_ids == ["a", "b", "c"]
		and loaded.daily_carrier == "b" and loaded.counter("captures", true) == 3
		and loaded.counter("captures", false) == 7
		and loaded.claimed_tier("a", true) == 1,
		"quêtes : l'état sérialisé conserve jour, tirage, compteurs et paliers")


func _test_save_format() -> void:
	var state := StateModel.from_dict({})
	state.reset_daily(12, ["a"], "a")
	var inventory := InventoryModel.new().to_dict()
	var profile := Codec.encode({}, {}, "", "Joueur", Codec.default_stats(),
		inventory, state.to_dict())
	_check(int(Codec.decode(profile).get("quests", {}).get("day_index", -1)) == 12,
		"quêtes : le profil version 10 conserve l'état des quêtes")
	var legacy := profile.duplicate(true)
	legacy.erase("quests")
	legacy["save_version"] = 9
	_check((Codec.decode(legacy).get("quests", {}) as Dictionary).is_empty(),
		"quêtes : un profil antérieur se charge avec un état vide, sans erreur")


func _test_daily() -> void:
	var service := Service.new()
	PlayerData.commit_economy(InventoryModel.from_dict(PlayerData.inventory_dict()),
		null, StateModel.from_dict({}).to_dict())
	var view := service.view()
	var daily: Array = view.get("daily", [])
	var carriers := 0
	for entry in daily:
		if bool(entry.get("carrier", false)):
			carriers += 1
	_check(bool(view.get("ok", false)) and daily.size() == 3 and carriers == 1,
		"quêtes : trois quotidiennes sont tirées et une seule porte les bougies")
	var ids := _daily_ids(view)
	var inventory := InventoryModel.from_dict(PlayerData.inventory_dict())
	inventory.souls += 500
	PlayerData.commit_economy(inventory, null, PlayerData.quests_dict())
	_check(_daily_ids(service.view()) == ids and ids.size() == 3,
		"quêtes : le tirage du jour reste figé même si l'inventaire change")
	var previous := StateModel.from_dict(PlayerData.quests_dict())
	previous.day_index = Calendar.today() - 1
	PlayerData.commit_economy(InventoryModel.from_dict(PlayerData.inventory_dict()),
		null, previous.to_dict())
	var rolled := service.view()
	_check(int(rolled.get("day_index", -1)) == Calendar.today()
		and _daily_ids(rolled).size() == 3,
		"quêtes : un nouveau jour remplace le tirage et remet les compteurs à zéro")


func _test_claim() -> void:
	PlayerData._apply_profile(Codec.starter_profile())
	var state := StateModel.from_dict({})
	state.day_index = Calendar.today()
	state.bump("upgrades", 1, false)
	PlayerData.commit_economy(InventoryModel.from_dict(PlayerData.inventory_dict()),
		null, state.to_dict())
	var service := Service.new()
	var souls_before := PlayerData.souls()
	var first := service.claim("upgrades")
	_check(bool(first.get("ok", false)) and PlayerData.souls() == souls_before + 100,
		"quêtes : réclamer un palier verse exactement sa récompense")
	var again := service.claim("upgrades")
	_check(not bool(again.get("ok", false)) and PlayerData.souls() == souls_before + 100,
		"quêtes : un second clic ne paie jamais deux fois")
	var missing := service.claim("n2_cards")
	_check(not bool(missing.get("ok", false)),
		"quêtes : un palier non atteint ne peut pas être réclamé")
	var entry := {}
	for candidate in service.view().get("unique", []):
		if str(candidate.get("id", "")) == "upgrades":
			entry = candidate
	_check(int(entry.get("tier_index", -1)) == 1 and not bool(entry.get("claimable", true)),
		"quêtes : le palier réclamé laisse la place au suivant sans double paiement")


func _daily_ids(view: Dictionary) -> Array:
	var ids: Array = []
	for entry in view.get("daily", []):
		ids.append(str(entry.get("id", "")))
	return ids
