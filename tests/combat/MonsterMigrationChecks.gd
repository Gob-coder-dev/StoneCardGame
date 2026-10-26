## Régression de la conversion du catalogue : profils réels anciens, collisions et disque.
extends "res://tests/support/CombatTestSuite.gd"
const Migration := preload("res://scripts/data/DeckCatalogueMigration.gd")
const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const Storage := preload("res://scripts/data/PlayerSaveStorage.gd")
const PlayerModel := preload("res://scripts/data/PlayerData.gd")
const PATH := "user://samstone_test_monster_migration.json"
const OLD_DECK := ["kappa", "tanuki", "ronin", "naginata_monk", "kitsune", "bakuto", "maneki_neko", "saikoro"]

func run() -> void:
	_test_aliases()
	_test_decks()
	_test_banks()
	_test_backup()


func _test_aliases() -> void:
	var valid := StoneLoader._legacy_ids.size() == 131
	for alias in StoneLoader._legacy_ids:
		var target := StoneLoader.resolve_saved_id(alias)
		valid = valid and not StoneLoader.has_stone(alias) and StoneLoader.has_stone(target)
	_check(valid, "les 131 anciens identifiants ont une correspondance mais restent absents du catalogue jouable")
	var current := ["n01_n3", "f01_n4", "f08_n2"]
	_check(Migration.convert(current, "inari") == current and not Migration.requires_conversion(current),
		"une sauvegarde déjà convertie conserve exactement ses niveaux et son ordre")
	var mixed := Migration.convert(["seed_balanced_n4", "n01_n2", "n01_n3", "kappa", "inconnu", "kappa"], "inari")
	_check(mixed.size() == 3 and mixed.has("n01_n2") and DeckRules.validate_deck(mixed, false, "inari")["valid"],
		"une conversion mixte protège une lignée actuelle et ignore doublons et identifiants inconnus")


func _test_decks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261024
	var valid := true
	for god in StoneLoader.get_all_gods():
		var god_id := str(god["id"])
		var aliases: Array = []
		for alias in StoneLoader._legacy_ids:
			if StoneLoader.is_stone_available_to_god(StoneLoader.resolve_saved_id(alias), god_id):
				aliases.append(alias)
		for sample in range(30):
			var pool := aliases.duplicate()
			var cards: Array = []
			for index in range(DeckRules.DECK_SIZE):
				cards.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
			var converted := Migration.convert(cards, god_id)
			valid = valid and DeckRules.is_deck_valid(converted, god_id)
			valid = valid and converted == Migration.convert(cards, god_id)
			valid = valid and converted == Migration.convert(converted, god_id)
	_check(valid, "180 anciens decks complets deviennent des decks valides, déterministes et stables après rechargement")
	_check(Migration.convert([], "inari").is_empty() and Migration.convert(["inconnu"], "inari").is_empty(),
		"la migration ne remplit pas les emplacements vides ni ceux sans carte reconnue")


func _test_banks() -> void:
	var raw := {"save_version": 3, "player_god_id": "inari", "player_name": "Bestiaire",
		"stats": {"wins": 12, "per_npc": {"tetsuo": {"wins": 4}}},
		"decks_by_god": {}, "selected_deck_by_god": {}}
	for god in StoneLoader.get_all_gods():
		var god_id := str(god["id"])
		var previous: Array = []
		for alias in StoneLoader._legacy_ids:
			if StoneLoader.is_stone_available_to_god(StoneLoader.resolve_saved_id(alias), god_id):
				previous.append(alias)
			if previous.size() == 8:
				break
		raw["decks_by_god"][god_id] = [previous, ["seed_balanced_n2"], []]
		raw["selected_deck_by_god"][god_id] = 1
	var profile := Codec.decode(raw)
	var valid := Codec.needs_catalogue_migration(raw) and not Codec.needs_catalogue_migration(profile)
	for god in profile["decks_by_god"]:
		var slots: Array = profile["decks_by_god"][god]
		valid = valid and DeckRules.is_deck_valid(slots[0], god) and slots[1] == ["n01_n2"] and slots[2].is_empty()
	_check(valid and profile["selected_deck_by_god"] == raw["selected_deck_by_god"]
		and profile["player_name"] == raw["player_name"] and profile["stats"]["per_npc"] == raw["stats"]["per_npc"],
		"la version trois migre les dix-huit emplacements et conserve sélections, pseudo et statistiques par adversaire")
	for version in [0, 1, 2]:
		var old := {"save_version": version, "player_deck": OLD_DECK}
		var converted := Codec.decode(old)
		_check(converted["player_god_id"] == "inari" and DeckRules.is_deck_valid(converted["decks_by_god"]["inari"][0], "inari"),
			"un ancien profil version %d retrouve son dieu et son deck complet" % version)


func _test_backup() -> void:
	_cleanup()
	var original := {"save_version": 3, "player_god_id": "inari", "player_deck": OLD_DECK, "player_name": "Original"}
	# Le parseur JSON lit les nombres en flottants : comparer deux contenus lus.
	original = JSON.parse_string(JSON.stringify(original))
	Storage.write(PATH, original)
	var player := PlayerModel.new(PATH)
	player.load_save()
	var backup_path := PATH + PlayerModel.CATALOGUE_BACKUP_SUFFIX
	_check(Storage.read(PATH) == original and not FileAccess.file_exists(backup_path),
		"charger un ancien profil ne réécrit ni le fichier ni sa copie de sécurité")
	var previous := player.get_profile()
	player._save_path = PATH + "/missing/profile.json"
	_expect_log("PlayerData: sauvegarde d'origine non conservée")
	_check(not player.set_selected_deck(1) and player.get_profile() == previous and Storage.read(PATH) == original,
		"un échec de copie de sécurité empêche la réécriture et annule la sélection")
	player._save_path = PATH
	_check(player.set_selected_deck(1) and Storage.read(backup_path) == original
		and Storage.read(PATH)["save_version"] == 4,
		"la première modification conserve le JSON d'origine puis enregistre le profil converti")
	player.set_selected_deck(2)
	player.load_save()
	_check(Storage.read(backup_path) == original and player.get_selected_deck() == 2,
		"les modifications et chargements suivants préservent la première copie d'origine")
	player.free()
	_cleanup()


func _cleanup() -> void:
	for suffix in ["", Storage.TEMP_SUFFIX, PlayerModel.CATALOGUE_BACKUP_SUFFIX, PlayerModel.CATALOGUE_BACKUP_SUFFIX + Storage.TEMP_SUFFIX]:
		var path: String = PATH + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
