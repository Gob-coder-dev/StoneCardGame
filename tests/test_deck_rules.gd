## Tests des règles de composition et des opérations immuables du deck.
## Deck de DeckRules.DECK_SIZE (8) pierres pour DeckRules.DECK_BUDGET (80) points.
extends "res://tests/support/CombatTestSuite.gd"

const CHEAP_SUFFIXES := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]


func before_all() -> void:
	for suffix in CHEAP_SUFFIXES:
		StoneLoader.register_stone("deck_4%s" % suffix, 1, 1, 1, 1)
	for suffix in ["a", "b", "c"]:
		StoneLoader.register_stone("deck_8%s" % suffix, 2, 2, 2, 2)
	for suffix in ["a", "b", "c", "d"]:
		StoneLoader.register_stone("deck_12%s" % suffix, 3, 3, 3, 3)
	for suffix in ["a", "b", "c", "d", "e"]:
		StoneLoader.register_stone("deck_16%s" % suffix, 4, 4, 4, 4)


## Un deck complet de pierres à 4 points (32 points pour 8 pierres).
func _small_deck() -> Array:
	var deck: Array = []
	for index in range(DeckRules.DECK_SIZE):
		deck.append("deck_4%s" % CHEAP_SUFFIXES[index])
	return deck


func test_deck_cost_sums_stone_costs() -> void:
	assert_eq(DeckRules.deck_cost(["deck_4a", "deck_8a", "deck_12a"]), 24)


func test_complete_valid_deck_is_accepted() -> void:
	assert_true(DeckRules.is_deck_valid(_small_deck()), "un deck complet dans le budget est valide")


func test_incomplete_deck_is_valid_while_editing() -> void:
	assert_true(DeckRules.validate_deck(["deck_4a"], false)["valid"])


func test_incomplete_deck_cannot_start_a_game() -> void:
	var deck := _small_deck()
	deck.pop_back()
	assert_false(DeckRules.is_deck_valid(deck), "un deck d'une pierre de moins ne permet pas de jouer")


func test_unknown_stone_is_rejected() -> void:
	assert_false(DeckRules.validate_deck(["stone_absente"], false)["valid"])


func test_duplicate_is_rejected() -> void:
	assert_false(DeckRules.validate_deck(["deck_4a", "deck_4a"], false)["valid"])


func test_sanitize_removes_unknown_duplicates_and_excess_cards() -> void:
	var dirty := ["deck_4a", "stone_absente", "deck_4a"]
	for suffix in CHEAP_SUFFIXES.slice(1):
		dirty.append("deck_4%s" % suffix)
	assert_eq(DeckRules.sanitize_deck(dirty), _small_deck())


func test_add_returns_a_new_valid_deck() -> void:
	var original := ["deck_4a"]
	var result := DeckRules.try_add(original, "deck_4b")
	assert_true(result["success"])
	assert_eq(result["deck"], ["deck_4a", "deck_4b"])
	assert_eq(original, ["deck_4a"])


func test_add_to_full_deck_requests_replacement() -> void:
	var result := DeckRules.try_add(_small_deck(), "deck_4j")
	assert_false(result["success"])
	assert_eq(result["reason"], DeckRules.REASON_FULL)


func test_add_over_budget_is_rejected() -> void:
	# 5 pierres à 16 points remplissent les 80 points : une pierre de plus dépasse.
	var expensive := ["deck_16a", "deck_16b", "deck_16c", "deck_16d", "deck_16e"]
	var result := DeckRules.try_add(expensive, "deck_4a")
	assert_false(result["success"])
	assert_eq(result["reason"], DeckRules.REASON_BUDGET)
	assert_eq(result["cost"], 84)


func test_remove_keeps_original_deck_unchanged() -> void:
	var deck := _small_deck()
	var result := DeckRules.try_remove(deck, "deck_4c")
	assert_true(result["success"])
	assert_eq(result["deck"].size(), DeckRules.DECK_SIZE - 1)
	assert_false(result["deck"].has("deck_4c"))
	assert_eq(deck.size(), DeckRules.DECK_SIZE)


## 4 pierres à 16 points et 3 à 4 points : 76 points pour 7 pierres.
const NEARLY_FULL := ["deck_16a", "deck_16b", "deck_16c", "deck_16d", "deck_4a", "deck_4b", "deck_4c"]


func test_valid_replacement_is_applied() -> void:
	var result := DeckRules.try_replace(NEARLY_FULL, "deck_4a", "deck_8a")
	assert_true(result["success"])
	assert_eq(result["cost"], 80)
	assert_eq(result["deck"][4], "deck_8a")


func test_replacement_over_budget_is_rejected() -> void:
	var result := DeckRules.try_replace(NEARLY_FULL, "deck_4a", "deck_12a")
	assert_false(result["success"])
	assert_eq(result["reason"], DeckRules.REASON_BUDGET)
	assert_eq(result["cost"], 84)


func test_replacement_cannot_create_a_duplicate() -> void:
	var result := DeckRules.try_replace(_small_deck(), "deck_4a", "deck_4b")
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
