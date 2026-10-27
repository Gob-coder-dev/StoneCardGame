## RulesEngine.gd
## Lectures pures d'un GameState : score, fin de partie et coups possibles.
## Fonctions statiques, sans effet sur la partie.
##
## Les définitions restent dans StoneLoader et les modifications de combat dans
## BattleStone. CombatResolver est l'unique chemin qui applique un coup ; l'IA
## l'appelle sur des copies (voir scripts/ai/MoveEvaluator.gd).
class_name RulesEngine
extends RefCounted


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
