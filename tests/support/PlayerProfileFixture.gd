## Isole les tests d'interface du profil réel, y compris les écritures automatiques.
extends RefCounted
const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const Storage := preload("res://scripts/data/PlayerSaveStorage.gd")
const PATH := "user://samstone_test_ui_profile.json"
const DECK := ["kappa", "tanuki", "ronin", "naginata_monk", "kitsune", "bakuto", "maneki_neko", "saikoro"]
var _previous_profile: Dictionary
var _previous_path: String
var _restored := false


func _init(raw: Dictionary = {"player_god_id": "inari", "player_deck": DECK}) -> void:
	_previous_profile = PlayerData.get_profile()
	_previous_path = PlayerData._save_path
	PlayerData._save_path = PATH
	PlayerData._apply_profile(Codec.decode(raw))


func restore() -> void:
	if _restored:
		return
	_restored = true
	PlayerData._apply_profile(_previous_profile)
	PlayerData._save_path = _previous_path
	for path in [PATH, PATH + Storage.TEMP_SUFFIX, PATH + Storage.UNREADABLE_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
