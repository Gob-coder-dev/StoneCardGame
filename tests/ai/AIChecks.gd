extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_clone_and_hidden_random()
	await _test_ai_moves()
	await _test_complete_matches()

func _test_clone_and_hidden_random() -> void:
	var state := _state_with_hands(["kappa"], ["tanuki"])
	state.set_random_seed(9988)
	var clone := state.clone()
	clone.draw_random_index(4)
	_check(clone.random_state != state.random_state, "une simulation ne consomme pas le hasard réel")
	var ai_copy := state.clone_for_ai()
	_check(ai_copy.human_hand == [""], "la main humaine reste masquée à l'IA")
	_check(ai_copy.random_state != state.random_state, "le futur tirage réel reste masqué à l'IA")


func _test_ai_moves() -> void:
	for ai in [RandomAI.new(), GreedyAI.new(), ScoreAI.new()]:
		var state := _state_with_hands([], ["kappa", "tanuki", "ronin"])
		var move: Dictionary = ai.choose_move(state.clone_for_ai())
		_check(not move.is_empty() and RulesEngine.is_placement_valid(state, move["row"], move["col"], move["stone_id"], GameState.PLAYER_AI), "%s produit un coup légal avec les pouvoirs" % ai.get_class())


func _test_complete_matches() -> void:
	for npc in StoneLoader.get_npcs_ordered():
		var god_id := str(npc.get("god_id", ""))
		var deck: Array = npc.get("deck", [])
		var legal_family := true
		for stone_id in deck:
			legal_family = legal_family and StoneLoader.is_stone_available_to_god(stone_id, god_id)
		_check(legal_family and deck.size() == DeckRules.DECK_SIZE, "%s possède un deck cohérent avec son dieu" % npc.get("name", "NPC"))
		var all_complete := true
		for sample in range(3):
			var state := _state_with_hands(deck, deck)
			if sample == 1:
				state.apply_blocked_cells([[1, 1]])
			state.set_random_seed(hash("%s:%d" % [npc.get("id", "npc"), sample]))
			var player := GameState.PLAYER_AI if sample == 2 else GameState.PLAYER_HUMAN
			var ai := _ai_for_level(str(npc.get("ai_level", "random")))
			var safety := 0
			while not RulesEngine.is_game_over(state) and safety < 12:
				var move: Dictionary
				if player == GameState.PLAYER_AI:
					move = ai.choose_move(state.clone_for_ai())
				else:
					var moves := RulesEngine.get_valid_moves(state, player)
					move = {} if moves.is_empty() else moves[state.draw_random_index(moves.size())]
				if move.is_empty():
					break
				var result := CombatResolverModel.apply_move(state, move["row"], move["col"], move["stone_id"], player)
				if not result.get("success", false):
					break
				player = GameState.PLAYER_AI if player == GameState.PLAYER_HUMAN else GameState.PLAYER_HUMAN
				safety += 1
			var score := RulesEngine.calculate_score(state)
			var expected := 8 if sample == 1 else 9
			all_complete = all_complete and RulesEngine.is_game_over(state) and score["human"] + score["ai"] == expected
		_check(all_complete, "les parties IA de %s terminent avec un score cohérent" % npc.get("name", "NPC"))
