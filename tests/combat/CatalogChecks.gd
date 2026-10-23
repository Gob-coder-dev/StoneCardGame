extends "res://tests/support/CombatTestSuite.gd"
const Effects := preload("res://scripts/domain/StoneEffects.gd")
const ContentChecks := preload("res://scripts/data/ContentValidator.gd")

func run() -> void:
	await _test_catalog_and_decks()
	await _test_immutable_catalog()
	_test_content_validation()


func _test_content_validation() -> void:
	var gods := {}
	for god in StoneLoader.get_all_gods():
		gods[god["id"]] = god
	var real := ContentChecks.find_problems(StoneLoader.get_all_stones(), gods,
		StoneLoader.get_npcs_ordered(), StoneLoader.default_god_id())
	_check(real.is_empty(), "le catalogue réel ne contient aucune incohérence")
	var typo := {"id": "typo", "god_id": "neutral", "blades": {"top": 1, "bottom": 1, "left": 1, "right": 1},
		"effects": ["swarn"], "coin_flip": "horizonal"}
	var problems := ContentChecks.find_problems([typo], gods, [], StoneLoader.default_god_id())
	_check(problems.size() == 2 and problems[0].contains("horizonal") and problems[1].contains("swarn"),
		"un pouvoir ou un axe de pile ou face mal orthographié est signalé au chargement")

func _test_catalog_and_decks() -> void:
	_check(StoneLoader.get_all_gods().size() == 6, "six dieux sont chargés")
	_check(StoneLoader.get_stones_for_god("inari").size() == 10, "Inari voit 7 neutres et 3 cartes de famille")
	_check(StoneLoader.is_stone_available_to_god("kappa", "inari"), "Kappa est disponible pour Inari")
	_check(not StoneLoader.is_stone_available_to_god("kappa", "hachiman"), "Kappa est exclusif à Inari")
	_check(StoneLoader.is_stone_available_to_god("kitsune", "hachiman"), "une carte neutre reste disponible")
	_check(is_equal_approx(StoneLoader.stone_cost("kappa"), 7.0), "les lames aléatoires coûtent 0,5")
	_check(is_equal_approx(StoneLoader.stone_cost("ashigaru"), 5.0), "les boucliers coûtent 0,5")
	_check(is_equal_approx(StoneLoader.stone_cost("yumi_archer"), 8.0), "les deux lames longues ont leur coût renforcé")
	var yasha_effects: Array = StoneLoader.get_stone("yasha").get("effects", [])
	_check(yasha_effects == [Effects.WEAKEN_ADJACENT] and is_equal_approx(StoneLoader.stone_cost("yasha"), 13.0),
		"Yasha possède seulement le Miasme et paie un seul pouvoir")
	var decline_cards_are_exclusive := true
	for stone_id in ["shinobi", "kunoichi", "yasha"]:
		var count := 0
		for effect in StoneLoader.get_stone(stone_id).get("effects", []):
			if Effects.DECLINE.has(effect):
				count += 1
		decline_cards_are_exclusive = decline_cards_are_exclusive and count == 1
	_check(decline_cards_are_exclusive, "chaque carte Déclin possède exactement un pouvoir")
	var catalog_respects_slots := true
	for definition in StoneLoader.get_all_stones():
		var preview := BattleStoneModel.new()
		preview.configure(str(definition.get("id", "")), definition)
		for side in BattleStoneModel.SIDES:
			catalog_respects_slots = catalog_respects_slots and preview.marker_count(side) <= 4
	_check(catalog_respects_slots, "tout le catalogue respecte quatre symboles communs par face")
	var inari_deck := ["kappa", "tanuki", "ronin", "naginata_monk", "kitsune"]
	_check(DeckRules.is_deck_valid(inari_deck, "inari"), "un deck dieu + neutres est valide")
	_check(not DeckRules.is_deck_valid(inari_deck, "hachiman"), "le même deck est refusé par un autre dieu")
	_check(DeckRules.sanitize_deck(inari_deck, "hachiman") == ["naginata_monk", "kitsune"], "le changement de dieu retire seulement les exclusives")
	_check(StoneLoader.best_god_for_deck(["samurai_red", "samurai_blue", "susanoo", "kappa", "kitsune"]) == "susanoo", "la migration choisit le dieu qui conserve le plus de cartes")


func _test_immutable_catalog() -> void:
	var definition := StoneLoader.get_stone("kappa")
	definition["blades"]["top"] = 99
	_check(StoneLoader.get_stone("kappa")["blades"]["top"] != 99,
		"modifier une définition retournée ne modifie pas le catalogue")
	_check(StoneLoader.has_stone("kappa") and not StoneLoader.has_stone("pierre_inconnue")
		and StoneLoader.has_effect("oni_minor", Effects.SWARM) and not StoneLoader.has_effect("kappa", Effects.SWARM),
		"les lectures indexées sans copie répondent comme le catalogue")
