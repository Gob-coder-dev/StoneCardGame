extends "res://tests/support/CombatTestSuite.gd"
const Effects := preload("res://scripts/domain/StoneEffects.gd")
const ContentChecks := preload("res://scripts/data/ContentValidator.gd")
const Board := preload("res://scripts/engine/combat/CombatBoard.gd")

func run() -> void:
	await _test_catalog_and_decks()
	await _test_immutable_catalog()
	_test_content_validation()
	_test_active_power_rule()


func _test_active_power_rule() -> void:
	_check(StoneLoader.stone_affinity("e06_n1") == "okuninushi"
		and StoneLoader.stone_affinity("n12_n2") == "neutral"
		and StoneLoader.stone_affinity("pierre_inconnue") == "",
		"le catalogue fournit l'affinité brute, sans confondre une inconnue et une neutre")
	_check(not StoneLoader.is_stone_available_to_god("n12_n2", "dieu_inconnu")
		and not StoneLoader.is_stone_available_to_god("pierre_inconnue", "inari"),
		"une carte ou un dieu inconnu ne devient pas disponible par défaut")
	var state := _state_with_hands([], [])
	state.human_god_id = "okuninushi"
	state.ai_god_id = "izanami"
	_check(not Board.has_active_power(state, state.get_cell(0, 0), Effects.SWARM),
		"une case vide n'active aucun pouvoir")
	_force_instance(state, 1, 1, "fx_swarm_okuni_a", GameState.PLAYER_HUMAN)
	var cell := state.get_cell(1, 1)
	_check(Board.has_active_power(state, cell, Effects.SWARM)
		and not Board.has_active_power(state, cell, Effects.WEAKEN_ADJACENT),
		"une pierre active seulement le pouvoir qu'elle possède dans le camp de son dieu")
	cell["owner"] = GameState.PLAYER_AI
	_check(not Board.has_active_power(state, cell, Effects.SWARM),
		"une capture par un autre dieu désactive le pouvoir continu")
	state.ai_god_id = "okuninushi"
	_check(Board.has_active_power(state, cell, Effects.SWARM),
		"une capture par le même dieu conserve le pouvoir continu")
	_force_instance(state, 0, 0, "fx_weaken_local", GameState.PLAYER_AI)
	var neutral := state.get_cell(0, 0)
	_check(Board.has_active_power(state, neutral, Effects.WEAKEN_ADJACENT),
		"un pouvoir continu neutre reste actif quel que soit le dieu")
	neutral["owner"] = GameState.PLAYER_NONE
	_check(not Board.has_active_power(state, neutral, Effects.WEAKEN_ADJACENT),
		"sans propriétaire, même une pierre neutre n'active pas son pouvoir")


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
	var npc := StoneLoader.get_npc("hiro")
	npc["ai"] = {"precison": 0.5, "anticipation": false}
	problems = ContentChecks.find_problems([], gods, [npc], StoneLoader.default_god_id())
	_check(problems.size() == 2 and problems[0].contains("precison") and problems[1].contains("précision"),
		"un réglage d'IA mal orthographié dans npcs.json est signalé au chargement")

func _test_catalog_and_decks() -> void:
	_check(StoneLoader.get_all_gods().size() == 6, "six dieux sont chargés")
	var neutral_count := 0
	var family_counts := {}
	for definition in StoneLoader.get_all_stones():
		var family := str(definition.get("god_id", "neutral"))
		if family == "neutral":
			neutral_count += 1
		else:
			family_counts[family] = int(family_counts.get(family, 0)) + 1
	var pools_match := true
	for god in StoneLoader.get_all_gods():
		var god_id := str(god["id"])
		pools_match = pools_match and StoneLoader.get_stones_for_god(god_id).size() == neutral_count + int(family_counts.get(god_id, 0))
	_check(pools_match and neutral_count > 0 and family_counts.size() == 6,
		"chaque dieu voit ses cartes de famille et toutes les neutres")
	_check(StoneLoader.is_stone_available_to_god("f03_n1", "inari"), "Dé boiteux est disponible pour Véskar")
	_check(not StoneLoader.is_stone_available_to_god("f03_n1", "hachiman"), "Dé boiteux est exclusif à Fortune")
	_check(StoneLoader.is_stone_available_to_god("n12_n2", "hachiman"), "une carte neutre reste disponible")
	_check(is_equal_approx(StoneLoader.stone_cost("f03_n1"), 2.0), "les lames aléatoires coûtent 0,5")
	_check(is_equal_approx(StoneLoader.stone_cost("r05_n1"), 3.5), "les boucliers coûtent 0,5 et le Rempart 0,5")
	_check(is_equal_approx(StoneLoader.stone_cost("h05_n1"), 4.5), "les deux lames longues coûtent 1,25 chacune")
	var decline_effects: Array = StoneLoader.get_stone("d09_n2").get("effects", [])
	# Depuis l'équilibrage 4×4, le pouvoir de Déclin ne coûte rien : seules les lames sont facturées.
	_check(decline_effects == [Effects.WEAKEN_ADJACENT] and is_equal_approx(StoneLoader.stone_cost("d09_n2"), 9.0),
		"le Porte-cercueil possède seulement le Miasme, sans supplément de pouvoir")
	var decline_cards_are_exclusive := true
	for stone_id in ["d02_n3", "d07_n2", "d09_n2"]:
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
	_check(StoneLoader.get_all_stones().size() == 275 and StoneLoader.get_lineages_for_god("inari").size() == 36,
		"le catalogue contient 275 formes et chaque dieu voit 24 neutres et ses 12 lignées")
	_check(not StoneLoader.has_stone("kappa") and StoneLoader.get_stone("ashigaru").is_empty()
		and not StoneLoader.has_stone("seed_balanced_n1"), "les cartes japonaises et les prototypes ne sont plus jouables")
	_check(StoneLoader.get_stone("n21_n1")["name"] == "Le Voyeur"
		and StoneLoader.get_stone("f01_n1")["random_blades"] == 4
		and StoneLoader.get_stone("f01_n2")["random_blades"] == 5
		and StoneLoader.stone_cost("f01_n1") == 2.0 and StoneLoader.stone_cost("r01_n2") == 4.5,
		"les modifications de l'utilisateur sont intégrées avec les coûts calculés")
	var inari_deck := ["f03_n1", "f07_n1", "f08_n1", "n14_n1", "n12_n2", "f05_n1", "f02_n2", "f01_n2"]
	_check(DeckRules.is_deck_valid(inari_deck, "inari"), "un deck dieu + neutres est valide")
	_check(not DeckRules.is_deck_valid(inari_deck, "hachiman"), "le même deck est refusé par un autre dieu")
	_check(DeckRules.sanitize_deck(inari_deck, "hachiman") == ["n14_n1", "n12_n2"], "le nettoyage d'un deck incompatible conserve les cartes neutres")
	var npc_decks_valid := true
	for npc in StoneLoader.get_npcs_ordered():
		npc_decks_valid = npc_decks_valid and DeckRules.is_deck_valid(npc["deck"], npc["god_id"])
	_check(npc_decks_valid, "chaque adversaire a huit lignées compatibles, dans le budget de 80 points")
	_check(StoneLoader.best_god_for_deck(["p08_n1", "p09_n2", "p12_n1", "f03_n1", "n12_n2"]) == "susanoo", "la migration choisit le dieu qui conserve le plus de cartes")


func _test_immutable_catalog() -> void:
	var definition := StoneLoader.get_stone("f03_n1")
	definition["blades"]["top"] = 99
	_check(StoneLoader.get_stone("f03_n1")["blades"]["top"] != 99,
		"modifier une définition retournée ne modifie pas le catalogue")
	_check(StoneLoader.has_stone("f03_n1") and not StoneLoader.has_stone("pierre_inconnue")
		and StoneLoader.has_effect("e06_n1", Effects.SWARM) and not StoneLoader.has_effect("f03_n1", Effects.SWARM),
		"les lectures indexées sans copie répondent comme le catalogue")
