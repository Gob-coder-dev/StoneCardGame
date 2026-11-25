@tool
## Empreintes reproductibles des sources de jeu, calculées avant l’export.
extends RefCounted

const LAN_RULES_PATH := "res://lan_rules.sha256"
const RL_RULES_PATH := "res://rl_rules.sha256"


static func rl_checksum() -> String:
	var baked := _baked_checksum(RL_RULES_PATH)
	if not baked.is_empty():
		return baked
	var paths: Array[String] = []
	for folder in ["res://scripts/engine", "res://scripts/ai", "res://scripts/data", "res://scripts/domain"]:
		_collect_sources(folder, paths)
	return _checksum_sources(paths)


static func lan_checksum() -> String:
	var baked := _baked_checksum(LAN_RULES_PATH)
	if not baked.is_empty():
		return baked
	if not FileAccess.file_exists("res://scripts/engine/GameState.gd"):
		return ""
	# Le PVP utilise le moteur, les règles partagées et la préparation des decks.
	# Les sous-domaines de campagne, de quêtes et d’économie sont indépendants.
	var paths: Array[String] = ["res://scripts/data/MonsterLoader.gd",
		"res://scripts/application/pvp/PvpLoadoutFactory.gd"]
	_collect_sources("res://scripts/engine", paths)
	_collect_sources("res://scripts/domain", paths, false)
	return _checksum_sources(paths)


static func _baked_checksum(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var baked := FileAccess.get_file_as_string(path).strip_edges()
	return baked if baked.length() == 64 and baked.is_valid_hex_number(false) else ""


static func _checksum_sources(paths: Array[String]) -> String:
	paths.sort()
	var rows: Array[String] = []
	for path in paths:
		var source := FileAccess.get_file_as_string(path).trim_prefix("\ufeff").replace("\r\n", "\n")
		rows.append(path.trim_prefix("res://") + ":" + source.sha256_text())
	return "\n".join(rows).sha256_text()


static func _collect_sources(folder: String, paths: Array[String], recursive: bool = true) -> void:
	for filename in DirAccess.get_files_at(folder):
		if filename.ends_with(".gd"):
			paths.append(folder.path_join(filename))
	if recursive:
		for subfolder in DirAccess.get_directories_at(folder):
			_collect_sources(folder.path_join(subfolder), paths)
