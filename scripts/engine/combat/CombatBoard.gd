## Accès commun aux instances de combat posées sur le plateau.
## Une case occupée porte toujours sa BattleStone : il n'existe plus de case
## reconstruite à partir du seul identifiant de catalogue.
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")

static func stone_at(cell: Dictionary) -> BattleStoneModel:
	var stored = cell.get("stone")
	return stored if stored is BattleStoneModel else null

static func is_enemy(cell: Dictionary, player: int) -> bool:
	return cell["cell_type"] != GameState.CELL_BLOCKED \
		and cell["owner"] != GameState.PLAYER_NONE \
		and cell["owner"] != player \
		and stone_at(cell) != null
