extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_shields()
	await _test_long_range()
	await _test_attack_paths()

func _test_shields() -> void:
	var state := _state_with_hands(["fx_wall"], [])
	CombatResolverModel.apply_move(state, 1, 1, "fx_wall", GameState.PLAYER_HUMAN)
	var wall: BattleStoneModel = state.get_cell(1, 1)["stone"]
	_check(wall.attack("top") == 1, "un bouclier n'augmente pas l'attaque")
	_check(wall.defense("top") == 2, "un bouclier ajoute un point de défense")
	var rikishi := BattleStoneModel.new()
	rikishi.configure("sumo", StoneLoader.get_stone("sumo"))
	_check(rikishi.marker_count("bottom") == 4 and rikishi.attack("bottom") == 2 and rikishi.defense("bottom") == 4,
		"Rikishi partage ses quatre emplacements du bas entre deux lames et deux boucliers")
	var duel := _state_with_hands(["fx_attack2"], [])
	_force_instance(duel, 1, 1, "fx_wall", GameState.PLAYER_AI)
	var result := CombatResolverModel.apply_move(duel, 1, 0, "fx_attack2", GameState.PLAYER_HUMAN)
	_check(result["captures"].is_empty(), "le bouclier empêche une capture à égalité")


func _test_long_range() -> void:
	var useful_catalog := true
	for stone_id in ["yumi_archer", "tengu", "fujin"]:
		var definition := StoneLoader.get_stone(stone_id)
		var strongest_long_face := 0
		for value in definition.get("long_blades", {}).values():
			strongest_long_face = maxi(strongest_long_face, int(value))
		useful_catalog = useful_catalog and strongest_long_face >= 2
	_check(useful_catalog, "chaque carte Horizon possède au moins une face avec plusieurs lames longues")
	var pass_state := _state_with_hands(["fx_ranged"], [])
	var preview: BattleStoneModel = BattleStoneModel.new()
	preview.configure("fx_ranged", StoneLoader.get_stone("fx_ranged"))
	_check(preview.attack("right") == 3 and preview.ranged_attack("right") == 1, "une lame longue compte au contact mais attaque seule à distance")
	_force_instance(pass_state, 1, 1, "fx_plain", GameState.PLAYER_HUMAN)
	_force_instance(pass_state, 1, 2, "fx_ranged_target", GameState.PLAYER_AI)
	var result := CombatResolverModel.apply_move(pass_state, 1, 0, "fx_ranged", GameState.PLAYER_HUMAN)
	_check(result["captures"].size() == 1 and result["captures"][0]["distance"] == 2, "la lame longue traverse une alliée")

	var blocked := _state_with_hands(["fx_ranged"], [])
	blocked.apply_blocked_cells([[1, 1]])
	_force_instance(blocked, 1, 2, "fx_target", GameState.PLAYER_AI)
	result = CombatResolverModel.apply_move(blocked, 1, 0, "fx_ranged", GameState.PLAYER_HUMAN)
	_check(result["captures"].is_empty(), "une case bloquée arrête une attaque longue")

	var enemy_block := _state_with_hands(["fx_ranged"], [])
	_force_instance(enemy_block, 1, 1, "fx_strong_wall", GameState.PLAYER_AI)
	_force_instance(enemy_block, 1, 2, "fx_ranged_target", GameState.PLAYER_AI)
	result = CombatResolverModel.apply_move(enemy_block, 1, 0, "fx_ranged", GameState.PLAYER_HUMAN)
	_check(enemy_block.get_cell(1, 2)["owner"] == GameState.PLAYER_AI, "un ennemi qui résiste protège la suite de la ligne")


func _test_attack_paths() -> void:
	var empty := _state_with_hands(["fx_mixed_ranged"], [])
	var result := CombatResolverModel.apply_move(empty, 1, 0, "fx_mixed_ranged", GameState.PLAYER_HUMAN)
	_check(result["attacks"].is_empty(), "une ligne vide ne déclenche aucun tir")
	var allies := _state_with_hands(["fx_ranged"], [])
	_force_instance(allies, 1, 1, "fx_plain", GameState.PLAYER_HUMAN)
	_force_instance(allies, 1, 2, "fx_plain", GameState.PLAYER_HUMAN)
	result = CombatResolverModel.apply_move(allies, 1, 0, "fx_ranged", GameState.PLAYER_HUMAN)
	_check(result["attacks"].is_empty(), "une ligne d'alliés sans ennemi ne déclenche aucun tir")
	var hidden := _state_with_hands(["fx_ranged"], [])
	hidden.apply_blocked_cells([[1, 1]])
	_force_instance(hidden, 1, 2, "fx_ranged_target", GameState.PLAYER_AI)
	result = CombatResolverModel.apply_move(hidden, 1, 0, "fx_ranged", GameState.PLAYER_HUMAN)
	_check(result["attacks"].is_empty(), "un ennemi derrière une case bloquée n'est pas une cible atteignable")

	var far := _state_with_hands(["fx_ranged"], [])
	_force_instance(far, 1, 2, "fx_ranged_target", GameState.PLAYER_AI)
	result = CombatResolverModel.apply_move(far, 1, 0, "fx_ranged", GameState.PLAYER_HUMAN)
	var ray: Dictionary = result["attacks"][0]
	_check(ray["normal_count"] == 0 and ray["long_count"] == 1 and ray["hits"][0]["attack"] == 1,
		"seules les lames bleues sont actives contre une cible distante")

	var piercing := _state_with_hands(["fx_ranged"], [])
	_force_instance(piercing, 1, 1, "fx_wall", GameState.PLAYER_AI)
	_force_instance(piercing, 1, 2, "fx_ranged_target", GameState.PLAYER_AI)
	result = CombatResolverModel.apply_move(piercing, 1, 0, "fx_ranged", GameState.PLAYER_HUMAN)
	ray = result["attacks"][0]
	_check(result["captures"].size() == 2 and ray["hits"][0]["attack"] == 3 and ray["hits"][1]["attack"] == 1,
		"l'attaque combinée capture au contact puis les bleues continuent seules")
	_check(ray["endpoint"]["type"] == "exit" and ray["endpoint"]["col"] == GameState.BOARD_SIZE,
		"le tir sort du plateau après sa dernière capture")

	var resistance := _state_with_hands(["fx_mixed_ranged"], [])
	_force_instance(resistance, 1, 1, "fx_wall", GameState.PLAYER_AI)
	_force_instance(resistance, 1, 2, "fx_target", GameState.PLAYER_AI)
	result = CombatResolverModel.apply_move(resistance, 1, 0, "fx_mixed_ranged", GameState.PLAYER_HUMAN)
	ray = result["attacks"][0]
	_check(result["captures"].size() == 1 and ray["hits"].size() == 2 and not ray["hits"][1]["success"]
		and ray["endpoint"]["type"] == "enemy", "une égalité distante arrête les bleues après une première capture")

	var wall_after := _state_with_hands(["fx_ranged"], [])
	wall_after.apply_blocked_cells([[1, 2]])
	_force_instance(wall_after, 1, 1, "fx_wall", GameState.PLAYER_AI)
	result = CombatResolverModel.apply_move(wall_after, 1, 0, "fx_ranged", GameState.PLAYER_HUMAN)
	_check(result["captures"].size() == 1 and result["attacks"][0]["endpoint"]["type"] == "blocked",
		"une case bloquée arrête le tir après la capture précédente")

	var normal := _state_with_hands(["fx_plain"], [])
	_force_instance(normal, 1, 2, "fx_plain", GameState.PLAYER_AI)
	result = CombatResolverModel.apply_move(normal, 1, 1, "fx_plain", GameState.PLAYER_HUMAN)
	_check(result["attacks"].size() == 1 and not result["attacks"][0]["hits"][0]["success"],
		"une attaque normale à égalité produit un impact raté sans capture")

	for side in ["top", "bottom", "left", "right"]:
		var state := _state_with_hands(["fx_ranged"], [])
		var delta: Vector2i = StoneSide.GRID[side]
		var origin := Vector2i(1, 1) - delta
		_force_instance(state, 1, 1, "fx_ranged_target", GameState.PLAYER_AI)
		_force_instance(state, 1 + delta.x, 1 + delta.y, "fx_ranged_target", GameState.PLAYER_AI)
		var placed := CombatResolverModel.place_stone(state, origin.x, origin.y, "fx_ranged", GameState.PLAYER_HUMAN)
		var stone: BattleStoneModel = state.get_cell(origin.x, origin.y)["stone"]
		stone.swap_faces("right", side)
		var saved_rng := state.random_state
		var plan := CombatResolverModel.resolve_attacks(state, origin.x, origin.y, GameState.PLAYER_HUMAN, stone)
		_check(placed["success"] and plan["captures"].size() == 2 and state.get_cell(1, 1)["owner"] == GameState.PLAYER_AI
			and state.random_state == saved_rng, "le plan transperçant est pur et fonctionne vers %s" % side)
