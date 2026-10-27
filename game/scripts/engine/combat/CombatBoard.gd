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


## Activation des pouvoirs continus (Essaim, Miasme) : une pierre de famille
## n'agit que dans le camp de son dieu ; les neutres agissent dans tous les camps.
## Les symboles physiques, comme les boucliers, ne passent pas par cette règle.
static func has_active_power(state: GameState, cell: Dictionary, effect: String) -> bool:
	var owner := int(cell["owner"])
	var stone := stone_at(cell)
	if owner == GameState.PLAYER_NONE or stone == null or not StoneLoader.has_effect(stone.stone_id, effect):
		return false
	var affinity := StoneLoader.stone_affinity(stone.stone_id)
	return affinity != "" and (affinity == "neutral" or affinity == state.god_of(owner))
