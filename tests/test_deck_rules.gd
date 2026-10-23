## Tests des règles de composition et des opérations immuables du deck.
extends "res://tests/support/CombatTestSuite.gd"

const SMALL_DECK := ["deck_4a", "deck_4b", "deck_4c", "deck_4d", "deck_4e"]


func before_all() -> void:
	for suffix in ["a", "b", "c", "d", "e", "f", "g"]:
		StoneLoader.register_stone("deck_4%s" % suffix, 1, 1, 1, 1)
	for suffix in ["a", "b", "c"]:
		StoneLoader.register_stone("deck_8%s" % suffix, 2, 2, 2, 2)
	for suffix in ["a", "b", "c", "d"]:
		StoneLoader.register_stone("deck_12%s" % suffix, 3, 3, 3, 3)
	StoneLoader.register_stone("deck_16", 4, 4, 4, 4)


func test_deck_cost_sums_stone_costs() -> void:
	assert_eq(DeckRules.deck_cost(["deck_4a", "deck_8a", "deck_12a"]), 24)


func test_complete_valid_deck_is_accepted() -> void:
	assert_true(DeckRules.is_deck_valid(SMALL_DECK))


func test_incomplete_deck_is_valid_while_editing() -> void:
	assert_true(DeckRules.validate_deck(["deck_4a"], false)["valid"])


func test_incomplete_deck_cannot_start_a_game() -> void:
	assert_false(DeckRules.is_deck_valid(["deck_4a"]))


func test_unknown_stone_is_rejected() -> void:
	assert_false(DeckRules.validate_deck(["stone_absente"], false)["valid"])


func test_duplicate_is_rejected() -> void:
	assert_false(DeckRules.validate_deck(["deck_4a", "deck_4a"], false)["valid"])


func test_sanitize_removes_unknown_duplicates_and_excess_cards() -> void:
	var dirty := ["deck_4a", "stone_absente", "deck_4a", "deck_4b", "deck_4c", "deck_4d", "deck_4e", "deck_4f"]
	assert_eq(DeckRules.sanitize_deck(dirty), SMALL_DECK)


func test_add_returns_a_new_valid_deck() -> void:
	var original := ["deck_4a"]
	var result := DeckRules.try_add(original, "deck_4b")
	assert_true(result["success"])
	assert_eq(result["deck"], ["deck_4a", "deck_4b"])
	assert_eq(original, ["deck_4a"])


func test_add_to_full_deck_requests_replacement() -> void:
	var result := DeckRules.try_add(SMALL_DECK, "deck_4f")
	assert_false(result["success"])
	assert_eq(result["reason"], DeckRules.REASON_FULL)


func test_add_over_budget_is_rejected() -> void:
	var expensive := ["deck_12a", "deck_12b", "deck_12c", "deck_12d"]
	var result := DeckRules.try_add(expensive, "deck_4a")
	assert_false(result["success"])
	assert_eq(result["reason"], DeckRules.REASON_BUDGET)
	assert_eq(result["cost"], 52)


func test_remove_keeps_original_deck_unchanged() -> void:
	var result := DeckRules.try_remove(SMALL_DECK, "deck_4c")
	assert_true(result["success"])
	assert_eq(result["deck"], ["deck_4a", "deck_4b", "deck_4d", "deck_4e"])
	assert_eq(SMALL_DECK.size(), 5)


func test_valid_replacement_is_applied() -> void:
	var deck := ["deck_12a", "deck_12b", "deck_12c", "deck_4a", "deck_4b"]
	var result := DeckRules.try_replace(deck, "deck_4a", "deck_8a")
	assert_true(result["success"])
	assert_eq(result["cost"], 48)
	assert_eq(result["deck"][3], "deck_8a")


func test_replacement_over_budget_is_rejected() -> void:
	var deck := ["deck_12a", "deck_12b", "deck_12c", "deck_4a", "deck_4b"]
	var result := DeckRules.try_replace(deck, "deck_4a", "deck_16")
	assert_false(result["success"])
	assert_eq(result["reason"], DeckRules.REASON_BUDGET)
	assert_eq(result["cost"], 56)


func test_replacement_cannot_create_a_duplicate() -> void:
	var result := DeckRules.try_replace(SMALL_DECK, "deck_4a", "deck_4b")
	assert_false(result["success"])
	assert_eq(result["reason"], DeckRules.REASON_DUPLICATE)

func run() -> void:
	before_all()
	test_deck_cost_sums_stone_costs()
	test_complete_valid_deck_is_accepted()
	test_incomplete_deck_is_valid_while_editing()
	test_incomplete_deck_cannot_start_a_game()
	test_unknown_stone_is_rejected()
	test_duplicate_is_rejected()
	test_sanitize_removes_unknown_duplicates_and_excess_cards()
	test_add_returns_a_new_valid_deck()
	test_add_to_full_deck_requests_replacement()
	test_add_over_budget_is_rejected()
	test_remove_keeps_original_deck_unchanged()
	test_valid_replacement_is_applied()
	test_replacement_over_budget_is_rejected()
	test_replacement_cannot_create_a_duplicate()
