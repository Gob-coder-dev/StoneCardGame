@tool
## Identite canonique partagee avec les outils Python. Les champs visuels
## n'entrent pas dans le contenu de combat ; les sources sont signees a part.
extends RefCounted


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
	if FileAccess.file_exists("res://rl_rules.sha256"):
		var baked := FileAccess.get_file_as_string("res://rl_rules.sha256").strip_edges()
		if baked.length() == 64:
			return baked
	var paths: Array[String] = []
	for folder in ["res://scripts/engine", "res://scripts/ai", "res://scripts/data", "res://scripts/domain"]:
		_collect_sources(folder, paths)
	paths.sort()
	var rows: Array[String] = []
	for path in paths:
		var source := FileAccess.get_file_as_string(path).trim_prefix("\ufeff").replace("\r\n", "\n")
		rows.append(path.trim_prefix("res://") + ":" + source.sha256_text())
	return "\n".join(rows).sha256_text()


static func _collect_sources(folder: String, paths: Array[String]) -> void:
	for name in DirAccess.get_files_at(folder):
		if name.ends_with(".gd"):
			paths.append(folder.path_join(name))
	for name in DirAccess.get_directories_at(folder):
		_collect_sources(folder.path_join(name), paths)
