extends "res://tests/support/CombatTestSuite.gd"
const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const Storage := preload("res://scripts/data/PlayerSaveStorage.gd")
const PlayerModel := preload("res://scripts/data/PlayerData.gd")
## Fichier propre à ce test : la vraie sauvegarde du joueur n'est jamais touchée.
const TEST_PATH := "user://samstone_test_profile.json"

func run() -> void:
	_test_codec()
	_test_banks_codec()
	_test_storage()
	_test_autosave()
	_test_failed_save()


func _test_codec() -> void:
	var legacy := {"player_deck": ["samurai_red", "samurai_blue", "susanoo", "kitsune"],
		"player_name": "  Testeur  ", "stats": {"wins": 7}}
	var profile := Codec.decode(legacy)
	_check(profile["player_god_id"] == "susanoo" and profile["player_name"] == "Testeur",
		"une ancienne sauvegarde conserve son pseudo et retrouve son dieu")
	_check(profile["stats"]["wins"] == 7 and profile["stats"]["losses"] == 0,
		"les statistiques anciennes sont conservées et complétées")
	_check(profile["decks_by_god"]["susanoo"][0] == legacy["player_deck"]
		and profile["selected_deck_by_god"]["susanoo"] == 0,
		"l'ancien deck migre dans le premier emplacement de son dieu")
	var round_trip := Codec.decode(Codec.encode(profile["decks_by_god"], profile["selected_deck_by_god"], profile["player_god_id"],
		profile["player_name"], profile["stats"]))
	_check(round_trip == profile, "le nouveau format conserve toutes les données après chargement")
	_check(not profile.has("selected_npc_id") and not profile.has("last_winner"),
		"le contexte du combat reste absent de la sauvegarde du joueur")
	var version_one := Codec.decode({"save_version": 1, "player_god_id": "inari", "player_deck": ["kitsune"]})
	_check(version_one["decks_by_god"]["inari"] == [["kitsune"], [], []]
		and version_one["save_version"] == 2, "la version 1 conserve son deck et crée deux emplacements vides")


func _test_banks_codec() -> void:
	var profile := Codec.decode({})
	var valid: bool = profile["decks_by_god"].size() == StoneLoader.get_all_gods().size()
	for slots in profile["decks_by_god"].values():
		valid = valid and slots == [[], [], []]
	_check(valid, "un nouveau profil possède trois decks vides pour chacun des six dieux")
	profile["decks_by_god"]["inari"][1].append("kitsune")
	_check(profile["decks_by_god"]["inari"][0].is_empty()
		and profile["decks_by_god"]["inari"][2].is_empty()
		and profile["decks_by_god"]["susanoo"][1].is_empty(),
		"aucun tableau de deck n'est partagé entre emplacements ou dieux")
	profile["decks_by_god"]["susanoo"][2] = ["samurai_red"]
	profile["selected_deck_by_god"]["inari"] = 1
	profile["selected_deck_by_god"]["susanoo"] = 2
	profile["player_god_id"] = "inari"
	var reloaded := Codec.decode(JSON.parse_string(JSON.stringify(profile)))
	_check(reloaded["decks_by_god"] == profile["decks_by_god"]
		and reloaded["selected_deck_by_god"] == profile["selected_deck_by_god"]
		and reloaded["player_god_id"] == profile["player_god_id"],
		"un aller-retour JSON conserve toutes les banques et les sélections par dieu")
	var damaged := Codec.decode({"player_god_id": "inari",
		"decks_by_god": {"inari": [["kitsune", "kitsune", "samurai_red", "inconnu"], null, ["kappa"], ["tanuki"]],
			"susanoo": [["samurai_red"]], "izanami": "incorrect", "inconnu": [["kappa"]]},
		"selected_deck_by_god": {"inari": 1.5, "susanoo": 2.0, "izanami": -1, "tsukuyomi": 3, "hachiman": "2"}})
	_check(damaged["decks_by_god"]["inari"] == [["kitsune"], [], ["kappa"]]
		and damaged["decks_by_god"]["susanoo"][0] == ["samurai_red"]
		and damaged["decks_by_god"]["izanami"] == [[], [], []]
		and not damaged["decks_by_god"].has("inconnu"),
		"un emplacement abîmé est nettoyé sans effacer les autres dieux ni accepter une carte incompatible")
	_check(damaged["selected_deck_by_god"]["inari"] == 0
		and damaged["selected_deck_by_god"]["susanoo"] == 2
		and damaged["selected_deck_by_god"]["izanami"] == 0
		and damaged["selected_deck_by_god"]["tsukuyomi"] == 0
		and damaged["selected_deck_by_god"]["hachiman"] == 0,
		"les numéros invalides reviennent au premier emplacement, les indices JSON valides sont conservés")
	_check(Codec.decode({"decks_by_god": [], "selected_deck_by_god": []})["decks_by_god"]["inari"] == [[], [], []],
		"des banques de type incorrect sont chargées comme des decks vides")


func _test_autosave() -> void:
	_remove_test_files()
	Storage.write(TEST_PATH, {"player_god_id": "inari", "player_deck": ["kitsune"], "player_name": "Testeur", "stats": {"wins": 7}})
	var player := PlayerModel.new(TEST_PATH)
	player.load_save()
	_check(player.get_active_deck() == ["kitsune"], "PlayerData charge l'ancien deck avant toute écriture")
	_check(player.set_selected_deck(1) and player.get_active_deck().is_empty(), "choisir le deuxième emplacement ouvre son propre deck")
	var add := DeckRules.try_add(player.get_active_deck(), "kappa", "inari")
	_check(player.set_player_deck(add["deck"])
		and Codec.decode(Storage.read(TEST_PATH))["decks_by_god"]["inari"][1] == ["kappa"],
		"ajouter une carte dans un deck incomplet l'enregistre immédiatement en JSON")
	var replace := DeckRules.try_replace(player.get_active_deck(), "kappa", "tanuki", "inari")
	_check(player.set_player_deck(replace["deck"])
		and Codec.decode(Storage.read(TEST_PATH))["decks_by_god"]["inari"][1] == ["tanuki"],
		"remplacer une carte enregistre immédiatement le même emplacement")
	var remove := DeckRules.try_remove(player.get_active_deck(), "tanuki")
	_check(player.set_player_deck(remove["deck"])
		and Codec.decode(Storage.read(TEST_PATH))["decks_by_god"]["inari"][1].is_empty(),
		"retirer la dernière carte enregistre aussi un deck vide")
	_check(player.set_player_deck(["kitsune"]) and player.get_deck("inari", 0) == ["kitsune"],
		"une même carte peut appartenir à plusieurs decks indépendants")
	var untouched := player.get_profile()
	var copy := player.get_active_deck()
	copy.clear()
	var snapshot := player.get_profile()
	snapshot["decks_by_god"]["inari"][1].clear()
	_check(player.get_profile() == untouched, "les lectures du profil et du deck ne permettent pas de modifier les données persistantes")
	_check(not player.set_player_deck(["kitsune", "kitsune"])
		and not player.set_player_deck(["samurai_red"]) and not player.set_player_deck(["inconnu"])
		and not player.set_selected_deck(-1) and not player.set_selected_deck(3)
		and not player.set_player_god("inconnu") and player.get_profile() == untouched,
		"une modification invalide ne change ni les cartes, ni le dieu, ni le numéro actif")
	_check(player.set_player_god("susanoo") and player.get_active_deck().is_empty(),
		"un autre dieu ouvre sa banque au lieu de filtrer le deck précédent")
	player.set_selected_deck(2)
	player.set_player_deck(["samurai_red"])
	player.set_player_god("inari")
	_check(player.get_selected_deck() == 1 and player.get_active_deck() == ["kitsune"]
		and player.get_deck("susanoo", 2) == ["samurai_red"], "chaque dieu retrouve son dernier numéro et conserve tous ses decks")
	var reloaded := PlayerModel.new(TEST_PATH)
	reloaded.load_save()
	_check(reloaded.get_profile()["decks_by_god"] == player.get_profile()["decks_by_god"]
		and reloaded.get_profile()["selected_deck_by_god"] == player.get_profile()["selected_deck_by_god"]
		and reloaded.player_god_id == player.player_god_id
		and reloaded.player_name == "Testeur" and reloaded.stats["wins"] == 7,
		"un redémarrage restaure banques, dieu actif, numéros, pseudo et statistiques")
	_check(not DeckRules.is_deck_valid(reloaded.get_active_deck(), reloaded.player_god_id),
		"la sauvegarde d'un deck incomplet ne le rend pas jouable")
	player.free()
	reloaded.free()
	_remove_test_files()


func _test_failed_save() -> void:
	_remove_test_files()
	Storage.write(TEST_PATH, {"player_god_id": "inari", "player_deck": ["kitsune"]})
	var player := PlayerModel.new(TEST_PATH)
	player.load_save()
	var previous := player.get_profile()
	var disk := Storage.read(TEST_PATH)
	# TEST_PATH est un fichier, donc aucun enfant ne peut y être créé.
	player._save_path = TEST_PATH + "/missing/profile.json"
	_expect_log("PlayerData: profil non enregistré")
	_check(not player.set_player_deck(["kappa"]) and player.get_profile() == previous,
		"un échec d'enregistrement annule la modification du deck")
	_expect_log("PlayerData: profil non enregistré")
	_check(not player.set_selected_deck(2) and player.get_profile() == previous,
		"un échec d'enregistrement garde le numéro précédent actif")
	_expect_log("PlayerData: profil non enregistré")
	_check(not player.set_player_god("susanoo") and player.get_profile() == previous and Storage.read(TEST_PATH) == disk,
		"un échec d'enregistrement garde le dieu et le fichier précédents intacts")
	player.free()
	_remove_test_files()


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
