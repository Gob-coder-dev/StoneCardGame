## StateFingerprint.gd
## Empreinte canonique d'un GameState. Deux moteurs qui ont reçu la même graine
## et les mêmes coups doivent produire exactement la même empreinte.
##
## Le calcul ne lit que l'état du moteur (plateau, monstres, mains, hasard) et ne
## dépend d'aucune ressource graphique ni d'un ordre de dictionnaire implicite.
class_name StateFingerprint
extends RefCounted

const SCHEMA_VERSION: int = 1


static func of(state: GameState) -> String:
	if state == null:
		return "".sha256_text()
	var lines := PackedStringArray()
	lines.append("v%d" % SCHEMA_VERSION)
	lines.append("players:%d,%d,%d" % [state.current_player, state.empty_playable_cells,
		state.next_instance_id])
	lines.append("score:%d,%d,%d,%d" % [state.score_human, state.score_ai,
		1 if state.is_game_over else 0, state.winner])
	lines.append("gods:%s|%s" % [state.human_god_id, state.ai_god_id])
	lines.append("hands:%s|%s" % [_join(state.human_hand), _join(state.ai_hand)])
	lines.append("random:%d,%d" % [state.random_seed, state.random_state])
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		var monster = cell.get("monster")
		if monster is BattleMonster:
			lines.append("cell:%d:%d,%d,%d,%s,%s" % [index, int(cell.get("cell_type", 0)),
				int(cell.get("owner", 0)), int(cell.get("placed_by", 0)),
				str(cell.get("monster_id", "")), _monster(monster)])
		else:
			lines.append("cell:%d:%d,%d,%d,%s,-" % [index, int(cell.get("cell_type", 0)),
				int(cell.get("owner", 0)), int(cell.get("placed_by", 0)),
				str(cell.get("monster_id", ""))])
	return "\n".join(lines).sha256_text()


static func _join(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(value))
	return ",".join(parts)


static func _monster(monster: BattleMonster) -> String:
	return "%d:%s:%s:%s:%s:%s:%s:%d,%d,%d,%d" % [
		monster.instance_id, str(monster.monster_id), _sides(monster.base_blades),
		_sides(monster.random_blades), _sides(monster.long_blades), _sides(monster.shields),
		_sides(monster.swarm_blades), monster.miasma_weakness, monster.temporary_weakness,
		monster.temporary_weakness_owner, 1 if monster.coin_flipped else 0,
	]


static func _sides(values: Dictionary) -> String:
	var parts := PackedStringArray()
	for side in MonsterSide.ALL:
		parts.append("%s=%d" % [side, int(values.get(side, 0))])
	return ".".join(parts)
