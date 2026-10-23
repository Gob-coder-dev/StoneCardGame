extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_fortune_view_animation()
	await _test_coin_view_animation()

func _test_fortune_view_animation() -> void:
	var view := BoardView.new()
	view.size = Vector2(900, 900)
	add_child(view)
	view.build()
	var state := _state_with_hands(["kappa"], [])
	state.set_random_seed(2026)
	var placement := CombatResolverModel.place_stone(state, 1, 1, "kappa", GameState.PLAYER_HUMAN)
	view.refresh(state)
	var slot: Panel = view.get_node("cell_1_1")
	var card: StoneCard = slot.get_child(0)
	view.animations.animate_placement(1, 1)
	_check(_sum(card.displayed_stone().random_blades) == 0, "Fortune ne dévoile aucune lame pendant le rebond initial")
	await get_tree().create_timer(Timeline.PLACEMENT + 0.04).timeout
	view.animations.animate_preparation(1, 1, placement["placement_effects"], Timeline.PREPARATION)
	_check(_sum(card.displayed_stone().random_blades) == 0 and _sum(card.get_battle_stone().random_blades) == 2,
		"la spirale Fortune masque les lames jusqu'à leur révélation sans changer le moteur")
	await get_tree().create_timer(1.3).timeout
	_check(card._combat_preview == null and is_zero_approx(card.rotation) and view.animations.get_node_or_null("RandomReveal") == null,
		"la spirale révèle les valeurs réelles puis nettoie sa couche d'animation")
	view.queue_free()
	await get_tree().process_frame


func _test_coin_view_animation() -> void:
	for flipped in [false, true]:
		var state: GameState
		var placement: Dictionary
		for seed in range(1, 80):
			state = _state_with_hands(["tanuki"], [])
			state.set_random_seed(seed)
			placement = CombatResolverModel.place_stone(state, 1, 1, "tanuki", GameState.PLAYER_HUMAN)
			if state.get_cell(1, 1)["stone"].coin_flipped == flipped:
				break
		var view := BoardView.new()
		view.size = Vector2(900, 900)
		add_child(view)
		view.build()
		view.refresh(state)
		view.animations.animate_preparation(1, 1, placement["placement_effects"], Timeline.PREPARATION)
		var card: StoneCard = view.get_node("cell_1_1").get_child(0)
		var original: Dictionary = StoneLoader.get_stone("tanuki")["blades"]
		var unchanged := true
		for side in BattleStoneModel.SIDES:
			unchanged = unchanged and int(card.displayed_stone().base_blades[side]) == int(original[side])
		_check(unchanged,
			"le pile ou face conserve les valeurs d'origine avant son résultat (%s)" % flipped)
		await get_tree().create_timer(0.4).timeout
		var animation: Control = view.animations.get_node("CoinReveal")
		_check(is_zero_approx(card.rotation),
			"une pièce est superposée à la carte qui reste immobile (%s)" % flipped)
		await get_tree().create_timer(0.85).timeout
		_check(card._combat_preview == null and card.displayed_stone().coin_flipped == flipped,
			"la pièce révèle fidèlement l'issue du moteur (%s)" % flipped)
		view.queue_free()
		await get_tree().process_frame
