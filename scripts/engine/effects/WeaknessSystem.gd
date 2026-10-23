## Déclin : Miasme après capture, expiration puis nouvel échec corrosif.
## PostAttackEffectResolver décide si la pierre posée possède le pouvoir.
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const SIDES = StoneSide.ALL
const Board := preload("res://scripts/engine/combat/CombatBoard.gd")

## Miasme : chaque voisine, alliée ou adverse, perd définitivement 1 force.
static func apply_miasma(state: GameState, row: int, col: int) -> Array:
	var effects: Array = []
	for adjacent in GameState.get_adjacent_positions(row, col):
		var adjacent_stone := Board.stone_at(state.get_cell(adjacent["row"], adjacent["col"]))
		if adjacent_stone != null:
			var weakness_before := adjacent_stone.weakness()
			adjacent_stone.permanent_weakness += 1
			effects.append(CombatEvents.weakness(CombatEvents.WEAKEN, adjacent["row"], adjacent["col"],
			weakness_before, adjacent_stone.weakness(), row, col, "adjacent"))
	return effects

## Échec corrosif : si la pose n'a rien capturé, chaque pierre adverse perd
## 1 force jusqu'à la fin du prochain coup du lanceur.
static func apply_failed_attack(state: GameState, row: int, col: int, player: int, captures: Array) -> Array:
	var effects: Array = []
	if not captures.is_empty():
		return effects
	var opponent := GameState.PLAYER_AI if player == GameState.PLAYER_HUMAN else GameState.PLAYER_HUMAN
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		var target := Board.stone_at(cell)
		if cell["owner"] == opponent and target != null:
			var weakness_before := target.weakness()
			target.temporary_weakness += 1
			target.temporary_weakness_owner = player
			effects.append(CombatEvents.weakness(CombatEvents.TEMPORARY_WEAKEN,
			index / GameState.BOARD_SIZE, index % GameState.BOARD_SIZE,
			weakness_before, target.weakness(), row, col, "global"))
	return effects

static func expire_for_player(state: GameState, player: int) -> Array:
	var events: Array = []
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		var stone := Board.stone_at(cell)
		if stone != null and stone.temporary_weakness_owner == player:
			var weakness_before := stone.weakness()
			stone.temporary_weakness = 0
			stone.temporary_weakness_owner = GameState.PLAYER_NONE
			events.append(CombatEvents.weakness(CombatEvents.WEAKNESS_EXPIRED,
				index / GameState.BOARD_SIZE, index % GameState.BOARD_SIZE,
				weakness_before, stone.weakness()))
	return events
