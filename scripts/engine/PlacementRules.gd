## Validation commune aux coups réels et aux simulations.
class_name PlacementRules
extends RefCounted

static func is_valid(state: GameState, row: int, col: int, stone_id: String, player: int) -> bool:
	if player != GameState.PLAYER_HUMAN and player != GameState.PLAYER_AI:
		return false
	if row < 0 or row >= GameState.BOARD_SIZE or col < 0 or col >= GameState.BOARD_SIZE:
		return false
	var cell := state.get_cell(row, col)
	return cell["cell_type"] != GameState.CELL_BLOCKED \
		and cell["owner"] == GameState.PLAYER_NONE and cell["stone_id"] == "" \
		and state.hand_of(player).has(stone_id) and not StoneLoader.get_stone(stone_id).is_empty()
