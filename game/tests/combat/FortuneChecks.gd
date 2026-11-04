extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_random_blades()
	await _test_coin_flip()

func _test_random_blades() -> void:
	var expected := int(StoneLoader.get_stone("de_boiteux_n1").get("random_blades", 0))
	var first := _state_with_hands(["de_boiteux_n1"], [])
	first.set_random_seed(1337)
	var first_result := CombatResolverModel.apply_move(first, 1, 1, "de_boiteux_n1", GameState.PLAYER_HUMAN)
	var first_stone: BattleStoneModel = first.get_cell(1, 1)["stone"]
	var second := _state_with_hands(["de_boiteux_n1"], [])
	second.set_random_seed(1337)
	CombatResolverModel.apply_move(second, 1, 1, "de_boiteux_n1", GameState.PLAYER_HUMAN)
	var second_stone: BattleStoneModel = second.get_cell(1, 1)["stone"]
	_check(expected > 0 and first_result["placement"]["placement_effects"].size() == expected,
		"les lames Fortune du catalogue sont révélées")
	_check(_sum(first_stone.random_blades) == expected, "les lames aléatoires sont conservées dans l'instance")
	_check(first_stone.random_blades == second_stone.random_blades, "un seed identique reproduit le tirage")
	var under_cap := true
	for side in BattleStoneModel.SIDES:
		under_cap = under_cap and first_stone.marker_count(side) <= 4
	_check(under_cap, "le hasard respecte quatre symboles maximum par face")


func _test_coin_flip() -> void:
	var saw_heads := false
	var saw_tails := false
	for seed in range(1, 80):
		var state := _state_with_hands(["jumeau_de_cuivre_n1"], [])
		state.set_random_seed(seed)
		CombatResolverModel.apply_move(state, 1, 1, "jumeau_de_cuivre_n1", GameState.PLAYER_HUMAN)
		var stone: BattleStoneModel = state.get_cell(1, 1)["stone"]
		if stone.coin_flipped:
			saw_heads = true
			_check(stone.base_blades["left"] == 0 and stone.base_blades["right"] == 3, "pile ou face échange les faces prévues")
		else:
			saw_tails = true
		if saw_heads and saw_tails:
			break
	_check(saw_heads and saw_tails, "les deux issues du pile ou face existent")
	var vertical := _state_with_hands(["valet_a_lenvers_n1"], [])
	var result := CombatResolverModel.apply_move(vertical, 1, 1, "valet_a_lenvers_n1", GameState.PLAYER_HUMAN)
	var events: Array = result["placement"]["placement_effects"]
	_check(events.size() == 1 and events[0].get("axis", "") == "vertical",
		"le Valet à l'envers possède uniquement le pile ou face vertical")
	var expected_count := int(StoneLoader.get_stone("de_boiteux_n1").get("random_blades", 0))
	var badge: Dictionary = Symbols.badges_for(StoneLoader.get_stone("de_boiteux_n1"))[0]
	_check(badge.get("kind") == "fortune" and badge.get("count") == expected_count,
		"le badge de Dé boiteux annonce exactement les lames à révéler")
