## Isole les tests d'interface du profil réel, y compris les écritures automatiques.
extends RefCounted
const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const Storage := preload("res://scripts/data/PlayerSaveStorage.gd")
const PATH := "user://samstone_test_ui_profile.json"
const DECK := ["f03_n1", "f07_n1", "f08_n1", "n14_n1", "n12_n2", "f05_n1", "f02_n2", "f01_n2"]
var _previous_profile: Dictionary
var _previous_path: String
var _previous_backup: Dictionary
var _restored := false


func _init(raw: Dictionary = {"player_god_id": "inari", "player_deck": DECK}) -> void:
	_previous_profile = PlayerData.get_profile()
	_previous_path = PlayerData._save_path
	_previous_backup = PlayerData._pending_catalogue_backup.duplicate(true)
	PlayerData._save_path = PATH
	PlayerData._apply_profile(Codec.decode(raw))


func restore() -> void:
	if _restored:
		return
	_restored = true
	PlayerData._apply_profile(_previous_profile)
	PlayerData._save_path = _previous_path
	PlayerData._pending_catalogue_backup = _previous_backup
	for path in [PATH, PATH + Storage.TEMP_SUFFIX, PATH + Storage.UNREADABLE_SUFFIX,
		PATH + PlayerData.CATALOGUE_BACKUP_SUFFIX, PATH + PlayerData.CATALOGUE_BACKUP_SUFFIX + Storage.TEMP_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
