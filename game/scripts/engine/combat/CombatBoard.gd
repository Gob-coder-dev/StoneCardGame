## Accès commun aux instances de combat posées sur le plateau.
## Une case occupée porte toujours sa BattleMonster : il n'existe plus de case
## reconstruite à partir du seul identifiant de catalogue.
extends RefCounted
const BattleMonsterModel := preload("res://scripts/engine/BattleMonster.gd")

static func monster_at(cell: Dictionary) -> BattleMonsterModel:
	var stored = cell.get("monster")
	return stored if stored is BattleMonsterModel else null

static func is_enemy(cell: Dictionary, player: int) -> bool:
	return cell["cell_type"] != GameState.CELL_BLOCKED \
		and cell["owner"] != GameState.PLAYER_NONE \
		and cell["owner"] != player \
		and monster_at(cell) != null


## Activation des pouvoirs continus (Essaim, Miasme) : un monstre de famille
## n'agit que dans le camp de son dieu ; les neutres agissent dans tous les camps.
## Les symboles physiques, comme les boucliers, ne passent pas par cette règle.
static func has_active_power(state: GameState, cell: Dictionary, effect: String) -> bool:
	var owner := int(cell["owner"])
	var monster := monster_at(cell)
	if owner == GameState.PLAYER_NONE or monster == null or not MonsterLoader.has_effect(monster.monster_id, effect):
		return false
	var affinity := MonsterLoader.monster_affinity(monster.monster_id)
	return affinity != "" and (affinity == "neutral" or affinity == state.god_of(owner))
