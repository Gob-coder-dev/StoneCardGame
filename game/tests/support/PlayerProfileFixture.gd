## Isole les tests d'interface du profil réel, y compris les écritures automatiques.
extends RefCounted
const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const Storage := preload("res://scripts/data/PlayerSaveStorage.gd")
const PATH := "user://samstone_test_ui_profile.json"
const DECK := ["de_boiteux_n1", "jumeau_de_cuivre_n1", "valet_a_lenvers_n1", "ogre_a_deux_bouches_n1", "le_nud_hurlant_n2", "croupier_manchot_n1", "griffe_a_jetons_n2", "devoracle_n2"]
var _previous_profile: Dictionary
var _previous_path: String
var _restored := false


func _init(raw: Dictionary = {"player_god_id": "veskar", "player_deck": DECK}) -> void:
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
