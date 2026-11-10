extends "res://tests/support/CombatTestSuite.gd"
const Checks := preload("res://scripts/data/ContentValidator.gd")
const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const Opponent := preload("res://scripts/ai/OpponentModel.gd")
const Riposte := preload("res://scripts/ai/RiposteModel.gd")
const Endgame := preload("res://scripts/ai/EndgameSearch.gd")

func run() -> void:
	_test_catalogue()
	_test_form_assets()
	_test_deck_levels()
	_test_profile_decode()
	_test_grouped_probabilities()
	_test_grouped_search()


func _test_catalogue() -> void:
	var expected := {"avortons_des_caves": 4, "devoracle": 4, "valet_a_lenvers": 3, "eclat_cuirasse": 4,
		"echassier_des_brumes": 3, "le_porte_cercueil": 2, "porte_nid": 3, "le_collecteur_zero": 1}
	var coherent := true
	for lineage in expected:
		coherent = coherent and StoneLoader.lineage_max_level(lineage) == expected[lineage]
		for level in range(1, int(expected[lineage]) + 1):
			var id := StoneLoader.variant_id(lineage, level)
			coherent = coherent and StoneLoader.has_stone(id) and StoneLoader.stone_lineage(id) == lineage and StoneLoader.stone_level(id) == level
	_check(coherent, "les lignées de référence ont des identifiants stables et le nombre de formes de leur rareté")
	_check(StoneLoader.variant_id("avortons_des_caves", 0) == "" and StoneLoader.variant_id("avortons_des_caves", 5) == ""
		and StoneLoader.variant_id("inconnue", 1) == "", "un niveau inexistant est refusé explicitement")
	_check(StoneLoader.preview_variant("avortons_des_caves_n1", 4) == "avortons_des_caves_n4"
		and StoneLoader.preview_variant("echassier_des_brumes_n1", 4) == "echassier_des_brumes_n3"
		and StoneLoader.preview_variant("le_porte_cercueil_n1", 4) == "le_porte_cercueil_n2"
		and StoneLoader.preview_variant("le_collecteur_zero_n1", 4) == "le_collecteur_zero_n1",
		"l'aperçu niveau quatre conserve les rares, épiques et légendaires à leur vrai maximum")
	_check(StoneLoader.stone_cost("avortons_des_caves_n1") == 4.0 and StoneLoader.stone_cost("avortons_des_caves_n4") == 16.0
		and StoneLoader.stone_cost("devoracle_n1") == 3.0 and StoneLoader.stone_cost("echassier_des_brumes_n1") == 5.5,
		"chaque coût provient des symboles et d'un point fixe pour un pouvoir")
	var copy := StoneLoader.get_stone("avortons_des_caves_n4")
	copy["blades"]["top"] = 0
	_check(StoneLoader.get_stone("avortons_des_caves_n4")["blades"]["top"] == 4
		and StoneLoader.get_stone("avortons_des_caves_n1")["blades"]["top"] == 1,
		"les lectures et les niveaux ne partagent pas leurs dictionnaires modifiables")
	_check(not Checks.lineage_problems({"id": "broken", "rarity": "common", "levels": []}).is_empty()
		and not Checks.lineage_problems({"id": "broken", "rarity": "legendary", "levels": [{"id": "x", "god_id": "veskar"}]}).is_empty(),
		"une évolution manquante ou qui change de famille est signalée avant l'indexation")
	_check(not Checks.lineage_problems({"id": "broken", "rarity": "legendary", "levels": [{"id": "fraction", "blades": {"top": 1.5}}]}).is_empty()
		and not Checks.lineage_problems({"id": "broken", "rarity": "legendary", "levels": [{"id": "overflow", "blades": {"top": 3}, "shields": {"top": 2}}]}).is_empty(),
		"des symboles fractionnaires ou plus de quatre marqueurs sur une face sont refusés avant indexation")


func _test_deck_levels() -> void:
	var deck := ["le_nud_hurlant_n2", "avortons_des_caves_n1", "de_boiteux_n1"]
	var changed := DeckRules.try_set_level(deck, "avortons_des_caves", 3, "veskar")
	_check(changed["success"] and changed["deck"] == ["le_nud_hurlant_n2", "avortons_des_caves_n3", "de_boiteux_n1"]
		and deck[1] == "avortons_des_caves_n1", "changer le niveau conserve l'emplacement et ne modifie pas le tableau reçu")
	_check(not DeckRules.try_add(deck, "avortons_des_caves_n4", "veskar")["success"]
		and not DeckRules.try_replace(deck, "le_nud_hurlant_n2", "avortons_des_caves_n4", "veskar")["success"]
		and not DeckRules.validate_deck(["avortons_des_caves_n1", "avortons_des_caves_n2"], false, "veskar")["valid"],
		"deux niveaux de la même lignée sont refusés à l'ajout, au remplacement et à la validation")
	_check(DeckRules.sanitize_deck(["avortons_des_caves_n3", "avortons_des_caves_n1"], "veskar") == ["avortons_des_caves_n3"]
		and not DeckRules.try_set_level(deck, "avortons_des_caves", 5, "veskar")["success"],
		"le nettoyage garde la première forme et une écriture ne sature jamais un niveau invalide")
	var expensive := ["avortons_des_caves_n1"]
	for index in range(7):
		_register("evo_budget_%d" % index, 4, 4, 2, 0)
		expensive.append("evo_budget_%d" % index)
	var rejected := DeckRules.try_set_level(expensive, "avortons_des_caves", 4, "veskar")
	_check(DeckRules.is_deck_valid(expensive, "veskar") and not rejected["success"]
		and rejected["reason"] == DeckRules.REASON_BUDGET and rejected["deck"] == expensive,
		"un passage de niveau qui ferait dépasser les 80 points conserve le deck précédent")


func _test_form_assets() -> void:
	var saved_stones := StoneLoader._stones.duplicate()
	var saved_list := StoneLoader._stones_list.duplicate()
	var saved_lineages := StoneLoader._lineages.duplicate(true)
	var forms: Array = []
	for level in range(1, 5):
		forms.append({"id": "evo_asset_%d" % level, "asset": "res://future_art/form_%d.png" % level})
	forms[1].erase("asset")
	StoneLoader._index_lineage({"id": "evo_assets", "rarity": "common", "god_id": "neutral",
		"asset": "res://future_art/base.png",
		"blades": {"top": 1, "bottom": 1, "left": 1, "right": 1}, "levels": forms})
	_check(StoneLoader.get_stone("evo_asset_1")["asset"] == "res://future_art/form_1.png"
		and StoneLoader.get_stone("evo_asset_2")["asset"] == "res://future_art/base.png"
		and StoneLoader.get_stone("evo_asset_4")["asset"] == "res://future_art/form_4.png",
		"chaque forme hérite de l'illustration commune et peut utiliser sa propre image")
	StoneLoader._stones = saved_stones
	StoneLoader._stones_list = saved_list
	StoneLoader._lineages = saved_lineages


func _test_profile_decode() -> void:
	var raw := Codec.decode({"player_god_id": "veskar", "player_deck": ["le_nud_hurlant_n2", "de_boiteux_n1"]})
	for god in raw["decks_by_god"]:
		for slot in range(3):
			raw["decks_by_god"][god][slot] = [StoneLoader.variant_id("avortons_des_caves", slot + 1)]
	raw["player_name"] = "Évolutions"
	raw["stats"]["wins"] = 9
	var decoded := Codec.decode(JSON.parse_string(JSON.stringify(raw)))
	_check(decoded["decks_by_god"] == raw["decks_by_god"] and decoded["player_name"] == "Évolutions"
		and decoded["stats"]["wins"] == 9, "le format quatre conserve les niveaux distincts des dix-huit decks, le pseudo et les statistiques")


func _test_grouped_probabilities() -> void:
	var ids := ["avortons_des_caves_n1", "avortons_des_caves_n2", "avortons_des_caves_n3", "avortons_des_caves_n4",
		"devoracle_n1", "devoracle_n2", "devoracle_n3", "devoracle_n4", "de_boiteux_n1"]
	var values: Array[float] = [-2.0, 1.0, 3.0, 0.0, 4.0, -1.0, 1.0, 2.0, 2.0]
	var groups := [[-2.0, 1.0, 3.0, 0.0], [4.0, -1.0, 1.0, 2.0], [2.0]]
	var exact := true
	for hand_size in range(1, 4):
		for prefer_high in [true, false]:
			var enumerated := _enumerate(groups, hand_size, 0, -INF if prefer_high else INF, prefer_high)
			var actual := Opponent.expected_from_variants(ids, values, hand_size, prefer_high)
			exact = exact and is_equal_approx(actual, enumerated.x / enumerated.y)
	_check(exact, "les probabilités par lignée correspondent à l'énumération de toutes les mains légales, avec valeurs négatives et égalités")
	var one: Array[float] = [0.0, 4.0, 0.0]
	_check(is_equal_approx(Opponent.expected_from_variants(["avortons_des_caves_n1", "avortons_des_caves_n4", "de_boiteux_n1"], one, 1), 1.0),
		"une lignée à plusieurs niveaux conserve le même poids qu'une lignée à un seul niveau")
	var state := _state_with_hands([""], [])
	state.human_god_id = "veskar"
	_force_instance(state, 0, 0, "avortons_des_caves_n2", GameState.PLAYER_HUMAN)
	state.get_cell(0, 0)["owner"] = GameState.PLAYER_AI
	var possible := Opponent.possible_cards(state)
	var removed := true
	for form in StoneLoader.variant_ids("avortons_des_caves"):
		removed = removed and not possible.has(form)
	_check(removed and possible.has("devoracle_n4"), "poser une forme exclut toute sa lignée des prévisions, même après sa capture")


## Énumération indépendante du polynôme de production, uniquement pour petites fixtures.
func _enumerate(groups: Array, remaining: int, start: int, best: float, prefer_high: bool) -> Vector2:
	if remaining == 0:
		return Vector2(best, 1.0)
	var total := Vector2.ZERO
	for index in range(start, groups.size() - remaining + 1):
		for value in groups[index]:
			var next := maxf(best, value) if prefer_high else minf(best, value)
			total += _enumerate(groups, remaining - 1, index + 1, next, prefer_high) / groups[index].size()
	return total


func _test_grouped_search() -> void:
	_register("evo_wall2", 2, 2, 2, 2)
	var state := _state_with_hands([""], [])
	state.human_god_id = "veskar"
	_force_instance(state, 1, 1, "evo_wall2", GameState.PLAYER_AI)
	var catalog := _use_catalog(["avortons_des_caves_n1", "avortons_des_caves_n4", "fx_plain"])
	_check(is_equal_approx(Riposte.new(state.clone_for_ai()).threat(state), 0.25),
		"la riposte utilise les probabilités par lignée pour les niveaux possibles")
	_restore_catalog(catalog)
	var final_state := _state_with_hands(["avortons_des_caves_n1", "avortons_des_caves_n4", "fx_plain"], [])
	for index in range(1, GameState.total_cells()):
		_force_instance(final_state, index / GameState.BOARD_SIZE, index % GameState.BOARD_SIZE, "fx_plain", GameState.PLAYER_AI)
	_check(is_equal_approx(Endgame.evaluate(final_state, 1), 6.5),
		"la fin de partie pondère les formes d'une même lignée sans surestimer leur présence")
