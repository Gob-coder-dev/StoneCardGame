extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_swarm_view_animation()

func _test_swarm_view_animation() -> void:
	var state := _state_with_hands(["fx_swarm_a", "fx_swarm_b"], [])
	CombatResolverModel.apply_move(state, 1, 0, "fx_swarm_a", GameState.PLAYER_HUMAN)
	var result := CombatResolverModel.apply_move(
		state, 1, 1, "fx_swarm_b", GameState.PLAYER_HUMAN)
	var view := BoardView.new()
	view.size = Vector2(900, 900)
	add_child(view)
	view.build()
	view.refresh(state)
	view.animations.animate_swarm(result["placement"]["swarm_events"], 0.55)
	var animation: Control = view.animations.get_node("SwarmReveal")
	var first: StoneCard = view.get_node("cell_1_0").get_child(0)
	var second: StoneCard = view.get_node("cell_1_1").get_child(0)
	_check(animation._links_after.size() == 1
		and _sum(first.displayed_stone().swarm_blades) == 0
		and _sum(second.displayed_stone().swarm_blades) == 0,
		"les filaments masquent les nouvelles lames jusqu'à l'arrivée de l'impulsion")
	await get_tree().create_timer(0.37).timeout
	# Une paire reliée : chaque carte reçoit 2 lames de son seul allié.
	_check(_sum(first.displayed_stone().swarm_blades) == 2
		and _sum(second.displayed_stone().swarm_blades) == 2,
		"l'impulsion fait pousser les bonus exacts sur les deux cartes")
	await get_tree().create_timer(0.28).timeout
	_check(view.animations.get_node_or_null("SwarmReveal") == null
		and first._combat_preview == null and second._combat_preview == null
		and view.swarm_link_count() == 1,
		"le renfort nettoie son animation mais conserve sa liane visible")
	view.queue_free()
	await get_tree().process_frame

	state = _state_with_hands(
		["fx_swarm_a", "fx_swarm_b", "fx_swarm_c"], ["fx_strong_wall"])
	CombatResolverModel.apply_move(state, 1, 0, "fx_swarm_a", GameState.PLAYER_HUMAN)
	CombatResolverModel.apply_move(state, 1, 1, "fx_swarm_b", GameState.PLAYER_HUMAN)
	CombatResolverModel.apply_move(state, 1, 2, "fx_swarm_c", GameState.PLAYER_HUMAN)
	result = CombatResolverModel.apply_move(state, 0, 1, "fx_strong_wall", GameState.PLAYER_AI)
	view = BoardView.new()
	view.size = Vector2(900, 900)
	add_child(view)
	view.build()
	view.refresh(state)
	view.animations.set_swarm_links(result["swarm_events"][0]["links_before"])
	_check(view.swarm_link_count() == 2,
		"les lianes de l'ancien groupe restent présentes avant leur rupture")
	view.animations.animate_swarm(result["swarm_events"], 0.55)
	animation = view.animations.get_node("SwarmReveal")
	first = view.get_node("cell_1_0").get_child(0)
	# Groupe de trois : chaque carte portait le plafond de 4 lames avant la rupture.
	_check(animation._links_before.size() == 2 and animation._links_after.is_empty()
		and _sum(first.displayed_stone().swarm_blades) == 4,
		"la rupture conserve brièvement l'ancien réseau et ses lames visibles")
	await get_tree().create_timer(0.20).timeout
	var retracted := true
	for side in BattleStoneModel.SIDES:
		var count := int(first.displayed_stone().swarm_blades.get(side, 0))
		for swarm_index in range(count):
			var start := first.displayed_stone().marker_offset("swarm", side)
			retracted = retracted and first._animated_marker_growth(side, start + swarm_index) <= 0.05
	_check(retracted, "les lames perdues se rétractent lorsque les filaments cassent")
	await get_tree().create_timer(0.45).timeout
	_check(_sum(first.displayed_stone().swarm_blades) == 0
		and view.animations.get_node_or_null("SwarmReveal") == null
		and view.swarm_link_count() == 0,
		"la rupture retire les anciennes lianes sans conserver de bonus fantôme")
	view.queue_free()
	await get_tree().process_frame
