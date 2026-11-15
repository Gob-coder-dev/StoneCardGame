@tool
## Identite canonique partagee avec les outils Python. Les champs visuels
## n'entrent pas dans le contenu de combat ; les sources sont signees a part.
extends RefCounted


static func content_checksum() -> String:
	var gods: Array[String] = []
	for god in StoneLoader.get_all_gods():
		gods.append(str(god["id"]))
	gods.sort()
	var rows: Array[String] = ["samstone-content-v2", ",".join(gods)]
	var stones: Array = StoneLoader.get_all_stones().duplicate()
	stones.sort_custom(func(a: Dictionary, b: Dictionary): return str(a["id"]) < str(b["id"]))
	for stone in stones:
		var stone_id := str(stone["id"])
		var fields: Array[String] = [stone_id, StoneLoader.stone_lineage(stone_id),
			str(StoneLoader.stone_level(stone_id)),
			str(StoneLoader.lineage_max_level(StoneLoader.stone_lineage(stone_id))),
			StoneLoader.stone_affinity(stone_id)]
		for key in ["blades", "long_blades", "shields"]:
			var values: Array[String] = []
			for side in StoneSide.ALL:
				values.append(str(int(stone.get(key, {}).get(side, 0))))
			fields.append(",".join(values))
		var effects: Array = stone.get("effects", []).duplicate()
		effects.sort()
		fields.append_array([str(int(stone.get("random_blades", 0))),
			str(stone.get("coin_flip", "")), ",".join(effects)])
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
