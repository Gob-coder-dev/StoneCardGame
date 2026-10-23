## RulesEngine.gd
## Lectures pures d'un GameState : score, fin de partie, coups possibles et
## estimation des captures. Fonctions statiques, sans effet sur la partie.
##
## Les définitions restent dans StoneLoader et les modifications de combat dans
## BattleStone. CombatResolver est l'unique chemin qui applique un coup.
class_name RulesEngine
extends RefCounted

const CombatResolverModel := preload("res://scripts/engine/CombatResolver.gd")


## Estime les captures par simulation ; huit tirages pour les pouvoirs aléatoires.
static func count_captures(state: GameState, row: int, col: int, stone_id: String, owner: int) -> int:
	var definition := StoneLoader.get_stone(stone_id)
	var stochastic := int(definition.get("random_blades", 0)) > 0 or str(definition.get("coin_flip", "")) != ""
	var samples := 8 if stochastic else 1
	var total := 0.0
	for sample in range(samples):
		var simulation := state.clone()
		simulation.set_random_seed(hash("preview:%s:%d:%d:%d" % [stone_id, row, col, sample]))
		if not simulation.hand_of(owner).has(stone_id):
			simulation.hand_of(owner).append(stone_id)
		var before_score := calculate_score(simulation)
		var result := CombatResolverModel.apply_move(simulation, row, col, stone_id, owner)
		if result.get("success", false):
			var after_score := calculate_score(simulation)
			var before_owned: int = before_score["human"] if owner == GameState.PLAYER_HUMAN else before_score["ai"]
			var after_owned: int = after_score["human"] if owner == GameState.PLAYER_HUMAN else after_score["ai"]
			total += maxi(0, after_owned - before_owned - 1)
	return int(round(total / float(samples)))


## ─── Fin de partie / score / vainqueur ───────────────────────────────────────

static func is_game_over(state: GameState) -> bool:
	return state.empty_playable_cells <= 0


static func calculate_score(state: GameState) -> Dictionary:
	var score := { "human": 0, "ai": 0 }
	for cell in state.board:
		if cell["owner"] == GameState.PLAYER_HUMAN:
			score["human"] += 1
		elif cell["owner"] == GameState.PLAYER_AI:
			score["ai"] += 1
	return score


static func determine_winner(state: GameState) -> int:
	var score := calculate_score(state)
	if score["human"] > score["ai"]:
		return GameState.PLAYER_HUMAN
	elif score["ai"] > score["human"]:
		return GameState.PLAYER_AI
	return GameState.PLAYER_NONE


## ─── Cases libres ─────────────────────────────────────────────────────────────

## Positions jouables (ni bloquées ni occupées). Array de { "row", "col" }.
static func get_free_cells(state: GameState) -> Array:
	var cells: Array = []
	for row in range(GameState.BOARD_SIZE):
		for col in range(GameState.BOARD_SIZE):
			var cell: Dictionary = state.get_cell(row, col)
			if cell["cell_type"] != GameState.CELL_BLOCKED and cell["owner"] == GameState.PLAYER_NONE:
				cells.append({ "row": row, "col": col })
	return cells


## ─── Coups valides ────────────────────────────────────────────────────────────

## Tous les coups { "row", "col", "stone_id" } de la main du joueur, utilisés par les IA.
static func get_valid_moves(state: GameState, player: int) -> Array:
	var moves: Array = []
	var hand: Array = state.hand_of(player)
	for cell in get_free_cells(state):
		for stone_id in hand:
			moves.append({ "row": cell["row"], "col": cell["col"], "stone_id": stone_id })
	return moves
