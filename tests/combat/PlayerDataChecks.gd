extends "res://tests/support/CombatTestSuite.gd"
const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const Storage := preload("res://scripts/data/PlayerSaveStorage.gd")
## Fichier propre à ce test : la vraie sauvegarde du joueur n'est jamais touchée.
const TEST_PATH := "user://samstone_test_profile.json"

func run() -> void:
	_test_codec()
	_test_storage()


func _test_codec() -> void:
	var legacy := {"player_deck": ["samurai_red", "samurai_blue", "susanoo", "kitsune"],
		"player_name": "  Testeur  ", "stats": {"wins": 7}}
	var profile := Codec.decode(legacy)
	_check(profile["player_god_id"] == "susanoo" and profile["player_name"] == "Testeur",
		"une ancienne sauvegarde conserve son pseudo et retrouve son dieu")
	_check(profile["stats"]["wins"] == 7 and profile["stats"]["losses"] == 0,
		"les statistiques anciennes sont conservées et complétées")
	var round_trip := Codec.decode(Codec.encode(profile["player_deck"], profile["player_god_id"],
		profile["player_name"], profile["stats"]))
	_check(round_trip == profile, "le nouveau format conserve toutes les données après chargement")
	_check(not profile.has("selected_npc_id") and not profile.has("last_winner"),
		"le contexte du combat reste absent de la sauvegarde du joueur")


func _test_storage() -> void:
	_remove_test_files()
	var first := {"player_name": "Premier"}
	var second := {"player_name": "Second"}
	var written := Storage.write(TEST_PATH, first) == OK and Storage.write(TEST_PATH, second) == OK
	_check(written and Storage.read(TEST_PATH) == second
		and not FileAccess.file_exists(TEST_PATH + Storage.TEMP_SUFFIX),
		"une sauvegarde remplace la précédente sans laisser de fichier temporaire")

	_write_text(TEST_PATH, "{ profil abîmé")
	_expect_log("Profil illisible mis de côté")
	_check(Storage.read(TEST_PATH).is_empty() and not FileAccess.file_exists(TEST_PATH)
		and FileAccess.get_file_as_string(TEST_PATH + Storage.UNREADABLE_SUFFIX) == "{ profil abîmé",
		"un profil illisible est mis de côté au lieu d'être écrasé")

	_write_text(TEST_PATH + Storage.TEMP_SUFFIX, JSON.stringify(first))
	_check(Storage.read(TEST_PATH) == first and FileAccess.file_exists(TEST_PATH)
		and not FileAccess.file_exists(TEST_PATH + Storage.TEMP_SUFFIX),
		"un remplacement interrompu récupère le nouveau profil complet")
	_remove_test_files()


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove_test_files() -> void:
	for path in [TEST_PATH, TEST_PATH + Storage.TEMP_SUFFIX, TEST_PATH + Storage.UNREADABLE_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
