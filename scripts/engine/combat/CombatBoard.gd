## Accès commun aux instances du plateau, y compris les anciennes fixtures id-only.
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")

static func stone_at(cell: Dictionary) -> BattleStoneModel:
	var stored = cell.get("stone")
	if stored is BattleStoneModel:
		return stored
	var stone_id := str(cell.get("stone_id", ""))
	if stone_id == "":
		return null
	var fallback: BattleStoneModel = BattleStoneModel.new()
	fallback.configure(stone_id, StoneLoader.get_stone(stone_id))
	return fallback

static func is_enemy(cell: Dictionary, player: int) -> bool:
	return cell["cell_type"] != GameState.CELL_BLOCKED \
		and cell["owner"] != GameState.PLAYER_NONE \
		and cell["owner"] != player \
		and stone_at(cell) != null
