## Tests unitaires du moteur de règles SamStone (modèle id-only).
## Exécutée par GodSystemChecks avec les assertions locales.
##
## Les pierres de test sont injectées dans StoneLoader via register_stone(),
## pour des lames connues et des tests indépendants de stones.json.
extends "res://tests/support/CombatTestSuite.gd"

## Enregistre les pierres de test une fois, avant tous les tests.
func before_all() -> void:
	StoneLoader.register_stone("t_1111", 1, 1, 1, 1)
	StoneLoader.register_stone("t_4444", 4, 4, 4, 4)
	StoneLoader.register_stone("t_0003", 0, 0, 0, 3)  # right=3
	StoneLoader.register_stone("t_0010", 0, 0, 1, 0)  # left=1
	StoneLoader.register_stone("t_0002", 0, 0, 0, 2)  # right=2
	StoneLoader.register_stone("t_0020", 0, 0, 2, 0)  # left=2
	StoneLoader.register_stone("t_0400", 0, 0, 4, 0)  # left=4
	StoneLoader.register_stone("t_0001", 0, 0, 0, 1)  # right=1
	StoneLoader.register_stone("t_0303", 0, 3, 0, 3)  # bottom=3, right=3
	StoneLoader.register_stone("t_1000", 1, 0, 0, 0)  # top=1
	StoneLoader.register_stone("t_3000", 3, 0, 0, 0)  # top=3
	StoneLoader.register_stone("t_0100", 0, 1, 0, 0)  # bottom=1
	StoneLoader.register_stone("t_0300", 0, 3, 0, 0)  # bottom=3
	StoneLoader.register_stone("t_0030", 0, 0, 3, 0)  # left=3


func _make_state() -> GameState:
	return GameState.new()


## Pose une pierre directement sur le plateau (bypass TurnManager, pour tests).
func _force_place(state: GameState, row: int, col: int, stone_id: String, owner: int) -> void:
	var idx := GameState.cell_index(row, col)
	state.board[idx]["stone_id"] = stone_id
	state.board[idx]["owner"] = owner
	state.empty_playable_cells -= 1


## ─── Direction opposée ───────────────────────────────────────────────────────

func test_opposite_top_is_bottom() -> void:
	assert_eq(RulesEngine.opposite_direction("top"), "bottom")

func test_opposite_bottom_is_top() -> void:
	assert_eq(RulesEngine.opposite_direction("bottom"), "top")

func test_opposite_left_is_right() -> void:
	assert_eq(RulesEngine.opposite_direction("left"), "right")

func test_opposite_right_is_left() -> void:
	assert_eq(RulesEngine.opposite_direction("right"), "left")


## ─── Validation du placement ─────────────────────────────────────────────────

func test_placement_valid_on_empty_cell() -> void:
	var state := _make_state()
	state.human_hand = ["t_1111"]
	assert_true(RulesEngine.is_placement_valid(state, 0, 0, "t_1111", GameState.PLAYER_HUMAN))

func test_placement_invalid_out_of_bounds_row() -> void:
	var state := _make_state()
	state.human_hand = ["t_1111"]
	assert_false(RulesEngine.is_placement_valid(state, 3, 0, "t_1111", GameState.PLAYER_HUMAN))

func test_placement_invalid_out_of_bounds_col() -> void:
	var state := _make_state()
	state.human_hand = ["t_1111"]
	assert_false(RulesEngine.is_placement_valid(state, 0, 3, "t_1111", GameState.PLAYER_HUMAN))

func test_placement_invalid_on_blocked_cell() -> void:
	var state := _make_state()
	state.human_hand = ["t_1111"]
	state.board[0]["cell_type"] = GameState.CELL_BLOCKED
	assert_false(RulesEngine.is_placement_valid(state, 0, 0, "t_1111", GameState.PLAYER_HUMAN))

func test_placement_invalid_on_occupied_cell() -> void:
	var state := _make_state()
	state.human_hand = ["t_1111"]
	_force_place(state, 0, 0, "t_4444", GameState.PLAYER_AI)
	assert_false(RulesEngine.is_placement_valid(state, 0, 0, "t_1111", GameState.PLAYER_HUMAN))

func test_placement_invalid_stone_not_in_hand() -> void:
	var state := _make_state()
	state.human_hand = []
	assert_false(RulesEngine.is_placement_valid(state, 0, 0, "t_1111", GameState.PLAYER_HUMAN))


## ─── Captures ────────────────────────────────────────────────────────────────

func test_no_capture_on_empty_board() -> void:
	var state := _make_state()
	assert_eq(RulesEngine.resolve_captures(state, 1, 1, "t_4444", GameState.PLAYER_HUMAN).size(), 0)

func test_capture_right_neighbor_weaker() -> void:
	## Ma pierre right=3 vs voisine à droite left=1 → capture
	var state := _make_state()
	_force_place(state, 0, 1, "t_0010", GameState.PLAYER_AI)
	var captures := RulesEngine.resolve_captures(state, 0, 0, "t_0003", GameState.PLAYER_HUMAN)
	assert_eq(captures.size(), 1)
	assert_eq(captures[0]["row"], 0)
	assert_eq(captures[0]["col"], 1)

func test_no_capture_equal_blades() -> void:
	## right=2 vs left=2 → égalité, pas de capture
	var state := _make_state()
	_force_place(state, 0, 1, "t_0020", GameState.PLAYER_AI)
	assert_eq(RulesEngine.resolve_captures(state, 0, 0, "t_0002", GameState.PLAYER_HUMAN).size(), 0)

func test_no_capture_own_stone() -> void:
	## Pierre alliée non capturable
	var state := _make_state()
	_force_place(state, 0, 1, "t_1111", GameState.PLAYER_HUMAN)
	assert_eq(RulesEngine.resolve_captures(state, 0, 0, "t_4444", GameState.PLAYER_HUMAN).size(), 0)

func test_capture_two_neighbors_simultaneously() -> void:
	## Pierre centrale bottom=3 & right=3 capture voisines à droite et en bas
	var state := _make_state()
	_force_place(state, 1, 2, "t_0010", GameState.PLAYER_AI)  # left=1 (à droite)
	_force_place(state, 2, 1, "t_1000", GameState.PLAYER_AI)  # top=1 (en bas)
	var captures := RulesEngine.resolve_captures(state, 1, 1, "t_0303", GameState.PLAYER_HUMAN)
	assert_eq(captures.size(), 2)

func test_no_capture_when_placed_stone_is_weaker() -> void:
	## right=1 vs left=4 → pas de capture
	var state := _make_state()
	_force_place(state, 0, 1, "t_0400", GameState.PLAYER_AI)
	assert_eq(RulesEngine.resolve_captures(state, 0, 0, "t_0001", GameState.PLAYER_HUMAN).size(), 0)

func test_capture_top_neighbor() -> void:
	## Pierre posée en bas (top=3) capture voisine en haut (bottom=1)
	var state := _make_state()
	_force_place(state, 0, 0, "t_0100", GameState.PLAYER_AI)
	var captures := RulesEngine.resolve_captures(state, 1, 0, "t_3000", GameState.PLAYER_HUMAN)
	assert_eq(captures.size(), 1)
	assert_eq(captures[0]["row"], 0)
	assert_eq(captures[0]["col"], 0)

func test_capture_bottom_neighbor() -> void:
	## Pierre posée en haut (bottom=3) capture voisine en bas (top=1)
	var state := _make_state()
	_force_place(state, 2, 0, "t_1000", GameState.PLAYER_AI)
	var captures := RulesEngine.resolve_captures(state, 1, 0, "t_0300", GameState.PLAYER_HUMAN)
	assert_eq(captures.size(), 1)
	assert_eq(captures[0]["row"], 2)
	assert_eq(captures[0]["col"], 0)

func test_capture_left_neighbor() -> void:
	## Pierre posée à droite (left=3) capture voisine à gauche (right=1)
	var state := _make_state()
	_force_place(state, 0, 0, "t_0001", GameState.PLAYER_AI)
	var captures := RulesEngine.resolve_captures(state, 0, 1, "t_0030", GameState.PLAYER_HUMAN)
	assert_eq(captures.size(), 1)
	assert_eq(captures[0]["row"], 0)
	assert_eq(captures[0]["col"], 0)


## ─── count_captures (variante légère pour l'IA) ──────────────────────────────

func test_count_captures_matches_resolve() -> void:
	var state := _make_state()
	_force_place(state, 1, 2, "t_0010", GameState.PLAYER_AI)
	_force_place(state, 2, 1, "t_1000", GameState.PLAYER_AI)
	var n := RulesEngine.count_captures(state, 1, 1, "t_0303", GameState.PLAYER_HUMAN)
	assert_eq(n, 2)


## ─── Fin de partie ───────────────────────────────────────────────────────────

func test_game_not_over_on_empty_board() -> void:
	assert_false(RulesEngine.is_game_over(_make_state()))

func test_game_over_when_no_empty_cells() -> void:
	var state := _make_state()
	state.empty_playable_cells = 0
	assert_true(RulesEngine.is_game_over(state))


## ─── Score / vainqueur ───────────────────────────────────────────────────────

func test_score_empty_board() -> void:
	var score := RulesEngine.calculate_score(_make_state())
	assert_eq(score["human"], 0)
	assert_eq(score["ai"], 0)

func test_score_human_wins() -> void:
	var state := _make_state()
	_force_place(state, 0, 0, "t_1111", GameState.PLAYER_HUMAN)
	_force_place(state, 0, 1, "t_1111", GameState.PLAYER_HUMAN)
	_force_place(state, 0, 2, "t_1111", GameState.PLAYER_AI)
	var score := RulesEngine.calculate_score(state)
	assert_eq(score["human"], 2)
	assert_eq(score["ai"], 1)

func test_winner_human() -> void:
	var state := _make_state()
	for i in range(5):
		state.board[i]["owner"] = GameState.PLAYER_HUMAN
	for i in range(5, 9):
		state.board[i]["owner"] = GameState.PLAYER_AI
	assert_eq(RulesEngine.determine_winner(state), GameState.PLAYER_HUMAN)

func test_winner_ai() -> void:
	var state := _make_state()
	for i in range(4):
		state.board[i]["owner"] = GameState.PLAYER_HUMAN
	for i in range(4, 9):
		state.board[i]["owner"] = GameState.PLAYER_AI
	assert_eq(RulesEngine.determine_winner(state), GameState.PLAYER_AI)

func test_winner_tie() -> void:
	var state := _make_state()
	state.board[8]["cell_type"] = GameState.CELL_BLOCKED
	for i in range(4):
		state.board[i]["owner"] = GameState.PLAYER_HUMAN
	for i in range(4, 8):
		state.board[i]["owner"] = GameState.PLAYER_AI
	assert_eq(RulesEngine.determine_winner(state), GameState.PLAYER_NONE)


## ─── Positions adjacentes ────────────────────────────────────────────────────

func test_adjacent_center_has_4_neighbors() -> void:
	assert_eq(GameState.get_adjacent_positions(1, 1).size(), 4)

func test_adjacent_corner_has_2_neighbors() -> void:
	assert_eq(GameState.get_adjacent_positions(0, 0).size(), 2)

func test_adjacent_edge_has_3_neighbors() -> void:
	assert_eq(GameState.get_adjacent_positions(0, 1).size(), 3)


## ─── Coups valides ───────────────────────────────────────────────────────────

func test_valid_moves_count() -> void:
	## 9 cases libres × 2 pierres = 18 coups
	var state := _make_state()
	state.ai_hand = ["t_1111", "t_4444"]
	assert_eq(RulesEngine.get_valid_moves(state, GameState.PLAYER_AI).size(), 18)

func test_valid_moves_sorted_dedup() -> void:
	## 2 pierres identiques dédoublonnées → 9 cases × 1 = 9 coups
	var state := _make_state()
	state.ai_hand = ["t_1111", "t_1111"]
	assert_eq(RulesEngine.get_valid_moves_sorted(state, GameState.PLAYER_AI).size(), 9)

func run() -> void:
	before_all()
	test_opposite_top_is_bottom()
	test_opposite_bottom_is_top()
	test_opposite_left_is_right()
	test_opposite_right_is_left()
	test_placement_valid_on_empty_cell()
	test_placement_invalid_out_of_bounds_row()
	test_placement_invalid_out_of_bounds_col()
	test_placement_invalid_on_blocked_cell()
	test_placement_invalid_on_occupied_cell()
	test_placement_invalid_stone_not_in_hand()
	test_no_capture_on_empty_board()
	test_capture_right_neighbor_weaker()
	test_no_capture_equal_blades()
	test_no_capture_own_stone()
	test_capture_two_neighbors_simultaneously()
	test_no_capture_when_placed_stone_is_weaker()
	test_capture_top_neighbor()
	test_capture_bottom_neighbor()
	test_capture_left_neighbor()
	test_count_captures_matches_resolve()
	test_game_not_over_on_empty_board()
	test_game_over_when_no_empty_cells()
	test_score_empty_board()
	test_score_human_wins()
	test_winner_human()
	test_winner_ai()
	test_winner_tie()
	test_adjacent_center_has_4_neighbors()
	test_adjacent_corner_has_2_neighbors()
	test_adjacent_edge_has_3_neighbors()
	test_valid_moves_count()
	test_valid_moves_sorted_dedup()
