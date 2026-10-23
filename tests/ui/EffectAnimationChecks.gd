extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_pillage_view_animation()
	await _test_weakness_view_animation()

func _test_pillage_view_animation() -> void:
	var state := _state_with_hands(["fx_thief"], [])
	_force_instance(state, 0, 1, "fx_wall", GameState.PLAYER_AI)
	_force_instance(state, 1, 0, "fx_wall", GameState.PLAYER_AI)
	_force_instance(state, 1, 2, "fx_wall", GameState.PLAYER_AI)
	var result := CombatResolverModel.apply_move(state, 1, 1, "fx_thief", GameState.PLAYER_HUMAN)
	var saved_rng := state.random_state
	var view := BoardView.new()
	view.size = Vector2(900, 900)
	add_child(view)
	view.build()
	view.refresh(state)
	view.animations.animate_effects(result["effects"], Timeline.PILLAGE)
	var card: StoneCard = view.get_node("cell_1_1").get_child(0)
	_check(_sum(card.displayed_stone().shields) == 0 and _sum(card.get_battle_stone().shields) == 4,
		"les nouveaux boucliers attendent la fin de la répartition aléatoire")
	var animation: Control = view.animations.get_node("PillageReveal")
	var robbed: StoneCard = view.get_node("cell_0_1").get_child(0)
	_check(animation._transfers.size() == 4 and animation._targets.size() == 4
		and is_zero_approx(robbed._animated_marker_growth("bottom", 0)),
		"les symboles volés se détachent et convergent vers leurs bonnes destinations")
	await get_tree().create_timer(1.85).timeout
	_check(card._combat_preview == null and state.random_state == saved_rng
		and _sum(card.displayed_stone().shields) == 4
		and is_equal_approx(robbed._animated_marker_growth("bottom", 0), 1.0),
		"le Pillage fait repousser les symboles et révèle les boucliers sans nouveau hasard")
	view.queue_free()
	await get_tree().process_frame


func _test_weakness_view_animation() -> void:
	var state := _state_with_hands(["fx_weaken_local"], [])
	_force_instance(state, 1, 0, "fx_plain", GameState.PLAYER_HUMAN)
	_force_instance(state, 1, 2, "fx_wall", GameState.PLAYER_AI)
	var result := CombatResolverModel.apply_move(state, 1, 1, "fx_weaken_local", GameState.PLAYER_HUMAN)
	var view := BoardView.new()
	view.size = Vector2(900, 900)
	add_child(view)
	view.build()
	view.refresh(state)
	view.animations.animate_effects(result["effects"], 0.55)
	var animation: Control = view.animations.get_node("WeaknessReveal")
	var target: StoneCard = view.get_node("cell_1_2").get_child(0)
	_check(animation._targets.size() == 2 and not animation._global
		and target.displayed_weakness() == 0,
		"le Miasme masque les fissures jusqu'à l'arrivée de l'aura locale")
	await get_tree().create_timer(0.34).timeout
	var every_face_broken := true
	for side in BattleStoneModel.SIDES:
		every_face_broken = every_face_broken and target.broken_blade_count(side) == 1
	_check(target.displayed_weakness() == 1 and every_face_broken
		and target.get_battle_stone().shields["left"] == 1,
		"l'impact brise une lame par face sans désactiver le bouclier")
	await get_tree().create_timer(0.30).timeout
	_check(view.animations.get_node_or_null("WeaknessReveal") == null and target._visual_weakness_override == -1,
		"l'aura locale nettoie son aperçu sans retirer le malus permanent")
	view.queue_free()
	await get_tree().process_frame

	state = _state_with_hands(["fx_weaken_miss", "fx_plain"], ["fx_plain"])
	_force_instance(state, 0, 1, "fx_plain", GameState.PLAYER_AI)
	_force_instance(state, 1, 2, "fx_plain", GameState.PLAYER_AI)
	result = CombatResolverModel.apply_move(state, 2, 2, "fx_weaken_miss", GameState.PLAYER_HUMAN)
	view = BoardView.new()
	view.size = Vector2(900, 900)
	add_child(view)
	view.build()
	view.refresh(state)
	view.animations.animate_effects(result["effects"], 0.55)
	animation = view.animations.get_node("WeaknessReveal")
	target = view.get_node("cell_0_1").get_child(0)
	_check(animation._global and animation._targets.size() == 2
		and target.displayed_weakness() == 0,
		"l'échec corrosif prépare une vague globale vers les seules cartes adverses")
	await get_tree().create_timer(0.39).timeout
	_check(target.displayed_weakness() == 1 and target.broken_blade_count("top") == 1,
		"la vague globale révèle les lames brisées à son impact")
	view.queue_free()
	await get_tree().process_frame

	CombatResolverModel.apply_move(state, 2, 0, "fx_plain", GameState.PLAYER_AI)
	var expiry := CombatResolverModel.apply_move(state, 0, 0, "fx_plain", GameState.PLAYER_HUMAN)
	view = BoardView.new()
	view.size = Vector2(900, 900)
	add_child(view)
	view.build()
	view.refresh(state)
	view.animations.animate_effects(expiry["effects"], 0.35)
	target = view.get_node("cell_0_1").get_child(0)
	_check(target.displayed_weakness() == 1 and view.animations.get_node_or_null("WeaknessRepair") != null,
		"une faiblesse expirée conserve brièvement ses fissures pour la réparation")
	await get_tree().create_timer(0.20).timeout
	_check(target.displayed_weakness() == 0 and target.broken_blade_count("top") == 0,
		"les lames temporaires se réparent à l'expiration du poison")
	view.queue_free()
	await get_tree().process_frame
