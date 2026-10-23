extends "res://tests/support/CombatTestSuite.gd"

const AIProfileModel := preload("res://scripts/ai/AIProfile.gd")
const ProfileAIModel := preload("res://scripts/ai/ProfileAI.gd")
const MoveEvaluatorModel := preload("res://scripts/ai/MoveEvaluator.gd")
const Opponent := preload("res://scripts/ai/OpponentModel.gd")

## Les trois profils des adversaires, plus une IA précise sans anticipation.
const RANDOM := {"precision": 0.0, "anticipation": false}
const HALF := {"precision": 0.5, "anticipation": false}
const GREEDY := {"precision": 1.0, "anticipation": false}
const CAREFUL := {"precision": 1.0, "anticipation": true}

func run() -> void:
	_test_clone_and_hidden_random()
	_test_profiles()
	_test_ai_moves()
	_test_evaluation()
	_test_precision()
	_test_opponent_model()
	_test_anticipation_trap()
	_test_hidden_hand()
	_test_endgame()
	await _test_turn_runner()
	_test_complete_matches()

func _test_clone_and_hidden_random() -> void:
	var state := _state_with_hands(["kappa"], ["tanuki"])
	state.set_random_seed(9988)
	var clone := state.clone()
	clone.draw_random_index(4)
	_check(clone.random_state != state.random_state, "une simulation ne consomme pas le hasard réel")
	var ai_copy := state.clone_for_ai()
	_check(ai_copy.human_hand == [""], "la main humaine reste masquée à l'IA")
	_check(ai_copy.random_state != state.random_state, "le futur tirage réel reste masqué à l'IA")


func _ai(profile_data: Dictionary, seed_value: int = 1):
	var ai = AITurnRunner.create_ai(profile_data)
	ai.rng.seed = seed_value
	return ai


func _test_profiles() -> void:
	_check(AIProfileModel.problems(HALF).is_empty() and AIProfileModel.problems({"precision": 1, "anticipation": true}).is_empty(),
		"un profil d'IA complet est accepté, y compris avec une précision entière")
	var invalid_profiles := [null, {}, {"precision": 1.5, "anticipation": false}, {"precision": -0.1, "anticipation": false},
		{"precision": "0.5", "anticipation": false}, {"precision": 0.5, "anticipation": 1},
		{"precision": 0.5, "anticipation": false, "depth": 3}]
	var all_reported := true
	for data in invalid_profiles:
		all_reported = all_reported and not AIProfileModel.problems(data).is_empty()
	_check(all_reported, "un profil d'IA absent, hors limites, mal typé ou avec un réglage inconnu est signalé")
	var fallback := AIProfileModel.new({"precision": 2.0, "anticipation": true})
	_check(fallback.precision == 0.0 and not fallback.anticipation, "un profil invalide joue au hasard")
	_check(is_equal_approx(AIProfileModel.new(RANDOM).think_delay(), 0.6)
		and is_equal_approx(AIProfileModel.new(HALF).think_delay(), 0.8)
		and is_equal_approx(AIProfileModel.new(CAREFUL).think_delay(), 1.2),
		"une IA plus réfléchie attend plus longtemps avant de jouer")
	var ai = AITurnRunner.create_ai(HALF)
	_check(ai.get_script() == ProfileAIModel and ai.profile.precision == 0.5 and not ai.profile.anticipation
		and is_equal_approx(ai.think_delay, 0.8), "create_ai règle l'IA unique avec le profil donné")
	var expected := {"easy": RANDOM, "medium": HALF, "hard": CAREFUL}
	var levels_match := true
	for npc in StoneLoader.get_npcs_ordered():
		levels_match = levels_match and npc.get("ai") == expected.get(npc.get("difficulty"))
	_check(levels_match, "Hiro et Mei jouent au hasard, Tetsuo et Yuki à mi-précision, Raiko et Kaguya anticipent")


func _test_ai_moves() -> void:
	for data in [RANDOM, HALF, GREEDY, CAREFUL]:
		var state := _state_with_hands(["kitsune"], ["kappa", "tanuki", "ronin"])
		state.human_god_id = "inari"
		_force_instance(state, 1, 1, "fx_plain", GameState.PLAYER_HUMAN)
		var view := state.clone_for_ai()
		var random_before := view.random_state
		var move: Dictionary = _ai(data).choose_move(view)
		_check(not move.is_empty() and PlacementRules.is_valid(state, move["row"], move["col"], move["stone_id"], GameState.PLAYER_AI)
			and view.random_state == random_before and view.ai_hand.size() == 3 and view.empty_playable_cells == 8
			and view.get_cell(1, 1)["owner"] == GameState.PLAYER_HUMAN,
			"précision %.1f%s : coup légal avec les pouvoirs, état reçu intact" % [data["precision"],
				", anticipation" if data["anticipation"] else ""])


func _test_evaluation() -> void:
	# Seul fx_attack2 posé en (1,1) capture la pierre humaine : 2 lames contre 1.
	var state := _state_with_hands([], ["fx_plain", "fx_attack2"])
	_force_instance(state, 1, 2, "fx_plain", GameState.PLAYER_HUMAN)
	_check(_ai(GREEDY).choose_move(state.clone_for_ai()) == {"row": 1, "col": 1, "stone_id": "fx_attack2"},
		"à précision 1, l'IA joue le coup qui capture")
	var piercing := _state_with_hands([], ["fx_ranged"])
	_force_instance(piercing, 1, 1, "fx_wall", GameState.PLAYER_HUMAN)
	_force_instance(piercing, 1, 2, "fx_ranged_target", GameState.PLAYER_HUMAN)
	var outcome := MoveEvaluatorModel.new(piercing.clone_for_ai(), false).evaluate(
		{"row": 1, "col": 0, "stone_id": "fx_ranged"}, 0)
	_check(is_equal_approx(outcome["value"], 2.0) and not outcome["random"],
		"l'évaluation compte les captures transperçantes")
	var fortune := MoveEvaluatorModel.new(_state_with_hands([], ["kappa"]).clone_for_ai(), false).evaluate(
		{"row": 1, "col": 1, "stone_id": "kappa"}, 0)
	_check(fortune["random"], "un coup qui utilise le hasard est signalé pour être évalué sur plusieurs tirages")


## Un seul coup capture parmi seize : la précision règle la part des bons choix.
func _test_precision() -> void:
	var state := _state_with_hands([], ["fx_plain", "fx_attack2"])
	_force_instance(state, 1, 2, "fx_plain", GameState.PLAYER_HUMAN)
	var view := state.clone_for_ai()
	var best := {"row": 1, "col": 1, "stone_id": "fx_attack2"}
	var counts := {}
	for data in [RANDOM, HALF, GREEDY]:
		var ai = _ai(data, 2026)
		var best_count := 0
		var distinct := {}
		for draw in range(200):
			var move: Dictionary = ai.choose_move(view)
			distinct[str(move)] = true
			if move == best:
				best_count += 1
		counts[data["precision"]] = [best_count, distinct.size()]
	_check(counts[0.0][0] < 40 and counts[0.0][1] >= 12, "précision 0 : l'IA joue au hasard parmi tous les coups")
	_check(counts[0.5][0] >= 90 and counts[0.5][0] <= 150 and counts[0.5][1] > 1,
		"précision 0,5 : le bon coup environ six fois sur dix, sinon une erreur")
	_check(counts[1.0][0] == 200, "précision 1 : toujours le meilleur coup")


func _test_opponent_model() -> void:
	var state := _state_with_hands(["ashigaru"], ["fx_strong_wall"])
	state.human_god_id = "hachiman"
	CombatResolverModel.apply_move(state, 0, 0, "ashigaru", GameState.PLAYER_HUMAN)
	CombatResolverModel.apply_move(state, 0, 1, "fx_strong_wall", GameState.PLAYER_AI)
	var captured := state.get_cell(0, 0)
	_check(captured["owner"] == GameState.PLAYER_AI and captured["placed_by"] == GameState.PLAYER_HUMAN,
		"une case capturée garde l'auteur de sa pose")
	var cards := Opponent.possible_cards(state.clone_for_ai())
	_check(cards.size() == 9 and not cards.has("ashigaru") and cards.has("izanagi") and cards.has("sumo")
		and not cards.has("kappa"), "l'IA suppose les cartes du dieu adverse et les neutres, moins celles déjà posées")
	_check(Opponent.possible_cards(_state_with_hands([""], [])).size() == StoneLoader.get_all_stones().size(),
		"avec un dieu inconnu, toutes les cartes du catalogue restent possibles")
	# Main de 2 cartes parmi 4 possibles : la plus forte est en main une fois
	# sur deux ; sinon la deuxième (1/3), sinon la troisième (1/6).
	var weights := Opponent.rank_weights(4, 2)
	var captures: Array[float] = [3.0, 1.0, 1.0, 1.0]
	_check(weights.size() == 4 and is_equal_approx(weights[0], 0.5) and is_equal_approx(weights[1], 1.0 / 3.0)
		and is_equal_approx(weights[2], 1.0 / 6.0) and is_equal_approx(weights[3], 0.0)
		and is_equal_approx(Opponent.expected_best(captures, weights), 2.0)
		and Opponent.rank_weights(3, 5) == PackedFloat64Array([1.0, 0.0, 0.0]),
		"la riposte attendue pondère chaque carte par sa chance d'être la meilleure de la main")
	var card_ids: Array[String] = ["tanuki", "kitsune"]
	var variants := Opponent.attack_variants(card_ids)
	_check(variants[0].size() == 2 and variants[0][0].normal_blades("left") == 2 and variants[0][1].normal_blades("right") == 2
		and variants[0][1].normal_blades("left") == 0 and variants[1].size() == 1,
		"un pile ou face adverse est envisagé dans ses deux orientations")


## L'IA a deux pierres sans défense en (0,0) et (0,2). Capturer en (1,1) laisse
## la case (0,1) à une riposte qui reprend trois pierres (valeur 1 − 3 = −2).
## Jouer en (0,1) ne capture rien mais limite la riposte à une pierre (−1).
func _trap_state(human_hand: Array) -> GameState:
	var state := _state_with_hands(human_hand, ["fx_attack2", "fx_ranged_target"])
	state.human_god_id = "hachiman"  # Izanagi 4/4/4/4 fait partie des cartes possibles.
	_force_instance(state, 0, 0, "fx_ranged_target", GameState.PLAYER_AI)
	_force_instance(state, 0, 2, "fx_ranged_target", GameState.PLAYER_AI)
	_force_instance(state, 1, 2, "fx_plain", GameState.PLAYER_HUMAN)
	return state


func _test_anticipation_trap() -> void:
	var greedy: Dictionary = _ai(GREEDY).choose_move(_trap_state(["kitsune"]).clone_for_ai())
	_check(greedy == {"row": 1, "col": 1, "stone_id": "fx_attack2"}, "sans anticipation, l'IA prend la capture immédiate")
	var all_careful := true
	for seed_value in range(6):
		var careful: Dictionary = _ai(CAREFUL, seed_value).choose_move(_trap_state(["kitsune"]).clone_for_ai())
		all_careful = all_careful and careful["row"] == 0 and careful["col"] == 1
	_check(all_careful, "avec anticipation, l'IA renonce à une capture qui offre une riposte plus forte")
	var view := _trap_state(["kitsune"]).clone_for_ai()
	var evaluator := MoveEvaluatorModel.new(view, true)
	var trap_value: float = evaluator.evaluate({"row": 1, "col": 1, "stone_id": "fx_attack2"}, 0)["value"]
	var safe_value: float = evaluator.evaluate({"row": 0, "col": 1, "stone_id": "fx_attack2"}, 0)["value"]
	_check(is_equal_approx(trap_value, -2.0) and is_equal_approx(safe_value, -1.0) and not evaluator.is_endgame(),
		"la valeur d'un coup retire la meilleure riposte adverse")


## Les mêmes tirages de l'IA donnent le même coup, quelle que soit la vraie main.
func _test_hidden_hand() -> void:
	var same := true
	for data in [HALF, CAREFUL]:
		for seed_value in range(4):
			var moves: Array = []
			for hand in [["kitsune"], ["izanagi"], ["ashigaru"]]:
				moves.append(_ai(data, seed_value).choose_move(_trap_state(hand).clone_for_ai()))
			same = same and moves[0] == moves[1] and moves[1] == moves[2]
	_check(same, "le choix de l'IA ne dépend pas des cartes réellement en main du joueur")


func _test_endgame() -> void:
	# Dernière case libre (2,2) sous une pierre humaine : seul le mur la capture.
	var last := _state_with_hands(["kitsune"], ["fx_ranged_target", "fx_strong_wall"])
	last.human_god_id = "hachiman"
	for index in [0, 1, 2, 3, 5, 6, 7]:
		var owner := GameState.PLAYER_HUMAN if index == 5 else GameState.PLAYER_AI
		_force_instance(last, index / 3, index % 3, "fx_plain", owner)
	last.apply_blocked_cells([[1, 1]])
	var view := last.clone_for_ai()
	_check(MoveEvaluatorModel.new(view, true).is_endgame() and not MoveEvaluatorModel.new(view, false).is_endgame(),
		"le calcul exact de fin de partie est réservé aux IA qui anticipent")
	_check(_ai(CAREFUL).choose_move(view) == {"row": 2, "col": 2, "stone_id": "fx_strong_wall"},
		"en fin de partie, l'IA joue le coup qui finit avec le meilleur score")

	# Trois cases libres, (0,2), (1,1) et (2,2). Le mur posé en (1,1) capture
	# (2,1), mais la riposte en (0,2) reprend deux pierres : écart final −1.
	# Poser d'abord la pierre sans lames et garder le mur pour la dernière case,
	# où rien ne le menace, reprend ce que la riposte aura pris : écart final +1.
	# La seule riposte immédiate préférerait le mur : il faut voir le dernier coup.
	var tempo := _state_with_hands(["kitsune", "sumo"], ["fx_strong_wall", "fx_ranged_target"])
	tempo.human_god_id = "hachiman"
	_force_instance(tempo, 0, 0, "fx_ranged_target", GameState.PLAYER_AI)
	_force_instance(tempo, 0, 1, "fx_left2", GameState.PLAYER_AI)
	_force_instance(tempo, 1, 0, "fx_strong_wall", GameState.PLAYER_HUMAN)
	_force_instance(tempo, 1, 2, "fx_left2", GameState.PLAYER_AI)
	_force_instance(tempo, 2, 0, "fx_plain", GameState.PLAYER_HUMAN)
	_force_instance(tempo, 2, 1, "fx_attack2", GameState.PLAYER_HUMAN)
	var exact := MoveEvaluatorModel.new(tempo.clone_for_ai(), true)
	var wall_now: float = exact.evaluate({"row": 1, "col": 1, "stone_id": "fx_strong_wall"}, 0)["value"]
	var wall_last: float = exact.evaluate({"row": 1, "col": 1, "stone_id": "fx_ranged_target"}, 0)["value"]
	_check(exact.is_endgame() and is_equal_approx(wall_now, -0.5) and is_equal_approx(wall_last, 0.5),
		"le calcul exact compte le dernier coup de l'IA (écart final divisé par deux)")
	var keeps_wall := true
	for seed_value in range(6):
		keeps_wall = keeps_wall and _ai(CAREFUL, seed_value).choose_move(tempo.clone_for_ai())["stone_id"] == "fx_ranged_target"
	_check(keeps_wall, "en fin de partie, l'IA garde sa pierre la plus solide pour la dernière case")


## Le tour réel : réflexion par tranches, délai minimal, puis abandon propre.
func _test_turn_runner() -> void:
	var manager := TurnManager.new()
	add_child(manager)
	var runner := AITurnRunner.new()
	add_child(runner)
	runner.setup(AITurnRunner.create_ai(CAREFUL), manager)
	manager.turn_started.connect(func(player: int):
		if player == GameState.PLAYER_AI:
			runner.run_turn())
	var deck: Array = StoneLoader.get_npc("kaguya")["deck"]
	manager.start_game(deck, deck, [], "kaguya", GameState.PLAYER_AI, "susanoo", "susanoo")
	var frames := 0
	while manager.get_state().ai_hand.size() == DeckRules.DECK_SIZE and frames < 300:
		await get_tree().process_frame
		frames += 1
	var state := manager.get_state()
	var placed := 0
	for cell in state.board:
		if cell["placed_by"] == GameState.PLAYER_AI:
			placed += 1
	# Délai de 1,2 s : 72 images à 60 images par seconde.
	_check(placed == 1 and state.ai_hand.size() == DeckRules.DECK_SIZE - 1 and frames >= 70 and frames < 300,
		"le tour de l'IA joue un seul coup légal, après son délai de réflexion")

	manager.start_game(deck, deck, [], "kaguya", GameState.PLAYER_AI, "susanoo", "susanoo")
	await get_tree().process_frame
	var thinking := runner.is_thinking()
	manager.start_game(deck, deck, [], "kaguya", GameState.PLAYER_HUMAN, "susanoo", "susanoo")
	for frame in range(100):
		await get_tree().process_frame
	_check(thinking and not runner.is_thinking() and manager.get_state().ai_hand.size() == DeckRules.DECK_SIZE,
		"relancer la partie pendant la réflexion abandonne le coup prévu")

	manager.start_game(deck, deck, [], "kaguya", GameState.PLAYER_AI, "susanoo", "susanoo")
	await get_tree().process_frame
	remove_child(runner)
	for frame in range(100):
		await get_tree().process_frame
	_check(not runner.is_thinking() and manager.get_state().ai_hand.size() == DeckRules.DECK_SIZE,
		"quitter l'écran pendant la réflexion n'envoie aucun coup")
	runner.free()
	manager.queue_free()
	await get_tree().process_frame


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
			state.human_god_id = god_id
			state.ai_god_id = god_id
			if sample == 1:
				state.apply_blocked_cells([[1, 1]])
			state.set_random_seed(hash("%s:%d" % [npc.get("id", "npc"), sample]))
			var player := GameState.PLAYER_AI if sample == 2 else GameState.PLAYER_HUMAN
			var ai := AITurnRunner.create_ai(npc.get("ai", {}))
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
