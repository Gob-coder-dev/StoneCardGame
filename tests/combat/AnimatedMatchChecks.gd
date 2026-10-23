extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	for npc in StoneLoader.get_npcs_ordered():
		await _compare_animated_and_instant(npc)


## Chaque coup est joué sur deux états identiques : simulation instantanée et
## vraie séquence visuelle. Compare aussi le hasard et les états des pouvoirs.
func _compare_animated_and_instant(npc: Dictionary) -> void:
	var manager := _animated_manager()
	var deck: Array = npc["deck"]
	manager.start_game(deck, deck, [], str(npc["id"]), GameState.PLAYER_HUMAN)
	manager.get_state().set_random_seed(2026)
	var simulation := manager.get_state().clone()
	var consistent := true
	var moves := 0
	while not manager.get_state().is_game_over and moves < 9:
		var state := manager.get_state()
		var player := state.current_player
		var choices := RulesEngine.get_valid_moves(state, player)
		var move: Dictionary = choices[(moves * 7) % choices.size()]
		CombatResolverModel.apply_move(simulation, move["row"], move["col"], move["stone_id"], player)
		if player == GameState.PLAYER_HUMAN:
			manager.human_play(move["row"], move["col"], move["stone_id"])
		else:
			manager.ai_play(move["row"], move["col"], move["stone_id"])
		while manager.phase != TurnManager.Phase.WAITING_INPUT and manager.phase != TurnManager.Phase.GAME_OVER:
			await get_tree().process_frame
		consistent = consistent and _same_board(simulation, manager.get_state())
		moves += 1
	_check(consistent and moves == 9 and manager.get_state().is_game_over,
		"partie animée et simulation identiques pour la famille de %s" % npc["name"])
	manager.queue_free()
	await get_tree().process_frame


func _same_board(first: GameState, second: GameState) -> bool:
	if first.random_state != second.random_state or first.human_hand != second.human_hand or first.ai_hand != second.ai_hand:
		return false
	for index in range(first.board.size()):
		var a: Dictionary = first.board[index]
		var b: Dictionary = second.board[index]
		if a["owner"] != b["owner"] or a["stone_id"] != b["stone_id"]:
			return false
		if a["stone"] == null:
			continue
		for field in ["base_blades", "random_blades", "long_blades", "shields", "swarm_blades",
			"permanent_weakness", "temporary_weakness", "temporary_weakness_owner", "coin_flipped"]:
			if a["stone"].get(field) != b["stone"].get(field):
				return false
	return true
