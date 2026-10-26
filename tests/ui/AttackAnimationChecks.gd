extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_attack_view_animation()

func _test_attack_view_animation() -> void:
	var state := _state_with_hands(["fx_plain"], [])
	_force_instance(state, 1, 2, "fx_plain", GameState.PLAYER_AI)
	CombatResolverModel.place_stone(state, 1, 1, "fx_plain", GameState.PLAYER_HUMAN)
	var stone: BattleStoneModel = state.get_cell(1, 1)["stone"]
	var plan := CombatResolverModel.resolve_attacks(state, 1, 1, GameState.PLAYER_HUMAN, stone)
	var view := BoardView.new()
	view.size = Vector2(900, 900)
	add_child(view)
	view.build()
	view.refresh(state)
	var card: StoneCard = view.get_node("cell_1_1").get_child(0)
	var original_size := card.size
	var original_markers := stone.base_blades.duplicate()
	var duration := Timeline.attack_duration(plan["attacks"])
	view.animations.animate_placement(1, 1)
	await get_tree().create_timer(Timeline.PLACEMENT + 0.06).timeout
	_check(card.scale.is_equal_approx(Vector2.ONE) and card.size == original_size, "le rebond de pose conserve les dimensions du plateau")
	view.animations.animate_attacks(1, 1, plan["attacks"], GameState.PLAYER_HUMAN, duration)
	var animation: Control = view.animations.get_node("AttackReveal")
	_check(animation._projectiles.size() == 1 and not card._attacking_faces.is_empty(), "seule la face dirigée vers un ennemi lance ses lames")
	var defending_card: StoneCard = view.get_node("cell_1_2").get_child(0)
	var to_board := view.get_global_transform().affine_inverse() * defending_card.get_global_transform()
	var defending_face := to_board * defending_card.face_center("left")
	var barrier_gap: float = defending_face.x - animation._impacts[0]["point"].x
	_check(barrier_gap >= card.size.x * 0.055 and barrier_gap <= card.size.x * 0.085,
		"la barrière d'échec se dresse juste devant les lames défensives")
	await get_tree().create_timer(duration + 0.12).timeout
	_check(card._attacking_faces.is_empty() and is_equal_approx(card.attack_regrowth, 1.0)
		and stone.base_blades == original_markers, "les lames repoussent sans modifier leurs valeurs de combat")
	_check(state.get_cell(1, 2)["owner"] == GameState.PLAYER_AI and view.animations.get_node_or_null("AttackReveal") == null,
		"une attaque ratée nettoie ses projectiles sans changer le propriétaire")
	view.queue_free()
	await get_tree().process_frame

	state = _state_with_hands(["fx_ranged"], [])
	_force_instance(state, 1, 1, "fx_plain", GameState.PLAYER_HUMAN)
	_force_instance(state, 1, 2, "fx_ranged_target", GameState.PLAYER_AI)
	CombatResolverModel.place_stone(state, 1, 0, "fx_ranged", GameState.PLAYER_HUMAN)
	stone = state.get_cell(1, 0)["stone"]
	plan = CombatResolverModel.resolve_attacks(state, 1, 0, GameState.PLAYER_HUMAN, stone)
	var rng_before := state.random_state
	view = BoardView.new()
	view.size = Vector2(900, 900)
	add_child(view)
	view.build()
	view.refresh(state)
	duration = Timeline.attack_duration(plan["attacks"])
	view.animations.animate_attacks(1, 0, plan["attacks"], GameState.PLAYER_HUMAN, duration)
	animation = view.animations.get_node("AttackReveal")
	_check(animation._projectiles.size() == 1 and animation._projectiles[0]["kind"] == "long",
		"une cible distante ne fait partir que les projectiles bleus")
	await get_tree().create_timer(Timeline.hit_time(2) + 0.06).timeout
	var target: StoneCard = view.get_node("cell_1_2").get_child(0)
	var captured_cell := view.slot_at(1, 2).get_theme_stylebox("panel") as StyleBoxFlat
	_check(target.get_combat_owner() == GameState.PLAYER_HUMAN
		and captured_cell.bg_color == UITheme.COL_BOARD_HUMAN_BG
		and state.get_cell(1, 2)["owner"] == GameState.PLAYER_AI,
		"la carte et sa case révèlent la capture à l'impact sans mutation du modèle")
	await get_tree().create_timer(duration).timeout
	_check(state.random_state == rng_before and view.animations.get_node_or_null("AttackReveal") == null,
		"le tir bleu termine sa trajectoire sans tirer de nouveau hasard")
	view.queue_free()
	await get_tree().process_frame
