## RulesEngine.gd
## Moteur de règles pur de SamStone.
## Fonctions statiques, sans état, sans effet de bord : elles lisent un
## GameState et retournent un résultat.
##
## Les définitions restent dans StoneLoader et les modifications de combat dans
## BattleStone. CombatResolver est l'unique chemin qui applique un coup.
class_name RulesEngine
extends RefCounted

const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const CombatResolverModel := preload("res://scripts/engine/CombatResolver.gd")

## ─── Direction opposée ────────────────────────────────────────────────────────

## Côté de la pierre voisine qui fait face au côté "direction" de la pierre posée.
static func opposite_direction(direction: String) -> String:
	return StoneSide.opposite(direction)


static func is_placement_valid(state: GameState, row: int, col: int, stone_id: String, player: int) -> bool:
	return PlacementRules.is_valid(state, row, col, stone_id, player)


static func resolve_captures(state: GameState, row: int, col: int, stone_id: String, owner: int) -> Array:
	var source: BattleStoneModel = null
	if row >= 0 and row < GameState.BOARD_SIZE and col >= 0 and col < GameState.BOARD_SIZE:
		var stored = state.get_cell(row, col).get("stone")
		if stored is BattleStoneModel and stored.stone_id == stone_id:
			source = stored
	if source == null:
		source = BattleStoneModel.new()
		source.configure(stone_id, StoneLoader.get_stone(stone_id))
	var detailed := CombatResolverModel.find_captures(state, row, col, owner, source)
	var captured: Array = []
	for result in detailed:
		captured.append({"row": result["row"], "col": result["col"]})
	return captured


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
## Un coup est { "row", "col", "stone_id" }.
## Note : on ne stocke plus "stone_data" — l'id suffit, les lames se lisent via
## StoneLoader au moment du besoin.

## Liste simple de tous les coups valides (utilisée hors chemin critique).
static func get_valid_moves(state: GameState, player: int) -> Array:
	var moves: Array = []
	var hand: Array = state.hand_of(player)
	for cell in get_free_cells(state):
		for stone_id in hand:
			moves.append({ "row": cell["row"], "col": cell["col"], "stone_id": stone_id })
	return moves


## Coups valides TRIÉS par nombre de captures décroissant (pour l'IA).
## Examiner les coups prometteurs en premier rend l'élagage alpha-bêta beaucoup
## plus efficace (levier 2). On dédoublonne les pierres identiques pour éviter
## d'évaluer plusieurs fois le même coup effectif.
static func get_valid_moves_sorted(state: GameState, player: int) -> Array:
	var hand: Array = state.hand_of(player)
	## Dédoublonnage : deux pierres de même id donnent le même coup.
	var unique_ids: Array = []
	for sid in hand:
		if not unique_ids.has(sid):
			unique_ids.append(sid)

	var moves: Array = []
	for cell in get_free_cells(state):
		for stone_id in unique_ids:
			moves.append({
				"row": cell["row"],
				"col": cell["col"],
				"stone_id": stone_id,
				"_captures": count_captures(state, cell["row"], cell["col"], stone_id, player)
			})

	## Tri décroissant par captures (les meilleurs coups d'abord).
	moves.sort_custom(func(a, b): return a["_captures"] > b["_captures"])
	return moves
