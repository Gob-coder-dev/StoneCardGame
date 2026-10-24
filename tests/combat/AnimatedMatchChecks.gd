extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	for npc in StoneLoader.get_npcs_ordered():
		await _compare_animated_and_instant(npc)


## Chaque coup est joué sur deux états identiques : simulation instantanée et
## vraie séquence visuelle. Compare aussi le hasard et les états des pouvoirs.
func _compare_animated_and_instant(npc: Dictionary) -> void:
	var manager := _animated_manager()
	var deck: Array = npc["deck"]
	var god_id := str(npc["god_id"])
	manager.start_game(deck, deck, [], str(npc["id"]), GameState.PLAYER_HUMAN, god_id, god_id)
	manager.get_state().set_random_seed(2026)
	var simulation := manager.get_state().clone()
	var consistent := true
	var moves := 0
	var saw_swarm := false
	var saw_miasma := false
	while not manager.get_state().is_game_over and moves < GameState.total_cells():
		var state := manager.get_state()
		var player := state.current_player
		var choices := RulesEngine.get_valid_moves(state, player)
		var move: Dictionary = choices[(moves * 7) % choices.size()]
		# Ces ouvertures garantissent que la comparaison couvre réellement les
		# pouvoirs continus, au lieu de simplement parcourir les cartes de famille.
		if god_id == "okuninushi" and moves < 3:
			move = [
				{"row": 1, "col": 1, "stone_id": "oni_minor"},
				{"row": 3, "col": 3, "stone_id": "oni_minor"},
				{"row": 1, "col": 2, "stone_id": "kodama"}][moves]
		elif god_id == "izanami" and moves < 2:
			move = [{"row": 1, "col": 1, "stone_id": "kunoichi"},
				{"row": 1, "col": 2, "stone_id": "yasha"}][moves]
		CombatResolverModel.apply_move(simulation, move["row"], move["col"], move["stone_id"], player)
		if player == GameState.PLAYER_HUMAN:
			manager.human_play(move["row"], move["col"], move["stone_id"])
		else:
			manager.ai_play(move["row"], move["col"], move["stone_id"])
		while manager.phase != TurnManager.Phase.WAITING_INPUT and manager.phase != TurnManager.Phase.GAME_OVER:
			await get_tree().process_frame
		consistent = consistent and _same_board(simulation, manager.get_state())
		for cell in simulation.board:
			var stone = cell["stone"]
			if stone != null:
				saw_swarm = saw_swarm or _sum(stone.swarm_blades) > 0
				saw_miasma = saw_miasma or stone.miasma_weakness > 0
		moves += 1
	_check(consistent and moves == GameState.total_cells() and manager.get_state().is_game_over,
		"partie animée et simulation identiques pour la famille de %s" % npc["name"])
	if god_id == "okuninushi":
		_check(saw_swarm, "la partie comparée déclenche réellement une aura d'Essaim")
	elif god_id == "izanami":
		_check(saw_miasma, "la partie comparée déclenche réellement une aura de Miasme")
	manager.queue_free()
	await get_tree().process_frame


func _same_board(first: GameState, second: GameState) -> bool:
	if first.random_state != second.random_state or first.human_hand != second.human_hand or first.ai_hand != second.ai_hand \
		or first.empty_playable_cells != second.empty_playable_cells or first.next_instance_id != second.next_instance_id:
		return false
	for index in range(first.board.size()):
		var a: Dictionary = first.board[index]
		var b: Dictionary = second.board[index]
		if a["owner"] != b["owner"] or a["stone_id"] != b["stone_id"] or a["placed_by"] != b["placed_by"]:
			return false
		if a["stone"] == null:
			continue
		for field in ["instance_id", "base_blades", "random_blades", "long_blades", "shields", "swarm_blades",
			"miasma_weakness", "temporary_weakness", "temporary_weakness_owner", "coin_flipped"]:
			if a["stone"].get(field) != b["stone"].get(field):
				return false
	return true
