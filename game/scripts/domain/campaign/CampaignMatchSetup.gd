## Fusionne le niveau et les réglages du scénario, puis vérifie que les deux
## mains permettent de remplir le plateau dans chaque ordre de jeu autorisé.
extends RefCounted

const Integer := preload("res://scripts/domain/IntegerValue.gd")


static func resolve(encounter: Dictionary, story: Dictionary = {},
		first_player: int = GameState.PLAYER_NONE) -> Dictionary:
	if first_player == GameState.PLAYER_NONE:
		first_player = Integer.read(encounter.get("forced_first_player", 0), -1, -1)
	var scripted_first := Integer.read(story.get("first_player", 0), -1, -1)
	return {
		"board_size": _number(encounter, story, "board_size", GameState.DEFAULT_BOARD_SIZE),
		"player_hand_size": _number(encounter, story, "player_hand_size", DeckRules.DECK_SIZE),
		"opponent_hand_size": _number(encounter, story, "opponent_hand_size", DeckRules.DECK_SIZE),
		"first_player": scripted_first if scripted_first != 0 else first_player,
		"blocked_cells": story.get("blocked_cells", encounter.get("blocked_cells", [])),
		"random_blocked_cells": story.is_empty() and bool(encounter.get("random_blocked_cells", not encounter.has("blocked_cells"))),
		"initial_monsters": story.get("initial_monsters", []),
	}


static func problem(setup: Dictionary, available_player: int = DeckRules.DECK_SIZE,
		available_opponent: int = DeckRules.DECK_SIZE) -> String:
	var board_size := int(setup["board_size"])
	if board_size < GameState.MIN_BOARD_SIZE or board_size > GameState.MAX_BOARD_SIZE:
		return "Taille de plateau hors bornes."
	for key in ["player_hand_size", "opponent_hand_size"]:
		if int(setup[key]) < 1 or int(setup[key]) > DeckRules.DECK_SIZE:
			return "Taille de main hors bornes."
	var excluded: Dictionary = {}
	var geometry_error := _exclude_blocked(setup["blocked_cells"], board_size, excluded)
	if geometry_error != "":
		return geometry_error
	# La génération aléatoire peut laisser le plateau entièrement libre.
	if bool(setup["random_blocked_cells"]):
		excluded.clear()
	geometry_error = _exclude_initial(setup["initial_monsters"], board_size, excluded)
	if geometry_error != "":
		return geometry_error
	var remaining := board_size * board_size - excluded.size()
	if remaining <= 0:
		return "Le plateau ne contient aucune case à jouer."
	var first_player := int(setup["first_player"])
	if first_player < GameState.PLAYER_NONE or first_player > GameState.PLAYER_TWO:
		return "Premier joueur invalide."
	var first_turns := ceili(float(remaining) / 2.0)
	var second_turns := remaining - first_turns
	var player_needed := second_turns if first_player == GameState.PLAYER_TWO else first_turns
	var opponent_needed := second_turns if first_player == GameState.PLAYER_ONE else first_turns
	if mini(int(setup["player_hand_size"]), available_player) < player_needed \
			or mini(int(setup["opponent_hand_size"]), available_opponent) < opponent_needed:
		return "Mains insuffisantes pour remplir les %d cases libres. Il faut au moins %d cartes au joueur et %d à l’adversaire." % [
			remaining, player_needed, opponent_needed]
	return ""


static func available_cards(story: Dictionary, deck_key: String, fallback: int) -> int:
	var cards: Variant = story.get(deck_key)
	return cards.size() if cards is Array else fallback


static func _number(encounter: Dictionary, story: Dictionary, key: String, fallback: int) -> int:
	return Integer.read(story.get(key, encounter.get(key, fallback)), -1, -1)


static func _exclude_blocked(blocked: Variant, board_size: int, excluded: Dictionary) -> String:
	if not blocked is Array:
		return "Liste de cases bloquées invalide."
	for cell in blocked:
		if not cell is Array or cell.size() != 2 \
				or not _reserve_cell(cell[0], cell[1], board_size, excluded):
			return "Case bloquée hors plateau, invalide ou dupliquée."
	return ""


static func _exclude_initial(initial: Variant, board_size: int, excluded: Dictionary) -> String:
	if not initial is Array:
		return "Liste de monstres initiaux invalide."
	for monster in initial:
		if not monster is Dictionary or not _reserve_cell(monster.get("row"),
				monster.get("col"), board_size, excluded):
			return "Monstre initial hors plateau ou placé sur une case déjà occupée ou bloquée."
	return ""


static func _reserve_cell(row: Variant, col: Variant, board_size: int, excluded: Dictionary) -> bool:
	if not _valid_coordinate(row, board_size) or not _valid_coordinate(col, board_size):
		return false
	var cell := Vector2i(int(row), int(col))
	if excluded.has(cell):
		return false
	excluded[cell] = true
	return true


static func _valid_coordinate(value: Variant, board_size: int) -> bool:
	return (value is int or value is float) and value >= 0 and value < board_size and value == floorf(value)
