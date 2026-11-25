@tool
## Identite canonique partagee avec les outils Python. Les champs visuels
## n'entrent pas dans le contenu de combat ; les sources sont signees a part.
extends RefCounted

const RulesIdentity := preload("res://scripts/data/RulesIdentity.gd")

static func content_checksum() -> String:
	var gods: Array[String] = []
	for god in MonsterLoader.get_all_gods():
		gods.append(str(god["id"]))
	gods.sort()
	var rows: Array[String] = ["beastpact-content-v2", ",".join(gods)]
	var monsters: Array = MonsterLoader.get_all_monsters().duplicate()
	monsters.sort_custom(func(a: Dictionary, b: Dictionary): return str(a["id"]) < str(b["id"]))
	for monster in monsters:
		var monster_id := str(monster["id"])
		var fields: Array[String] = [monster_id, MonsterLoader.monster_lineage(monster_id),
			str(MonsterLoader.monster_level(monster_id)),
			str(MonsterLoader.lineage_max_level(MonsterLoader.monster_lineage(monster_id))),
			MonsterLoader.monster_affinity(monster_id)]
		for key in ["blades", "long_blades", "shields"]:
			var values: Array[String] = []
			for side in MonsterSide.ALL:
				values.append(str(int(monster.get(key, {}).get(side, 0))))
			fields.append(",".join(values))
		var effects: Array = monster.get("effects", []).duplicate()
		effects.sort()
		fields.append_array([str(int(monster.get("random_blades", 0))),
			str(monster.get("coin_flip", "")), ",".join(effects)])
		rows.append("|".join(fields))
	return "\n".join(rows).sha256_text()


static func rules_checksum() -> String:
	return RulesIdentity.rl_checksum()
