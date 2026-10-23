extends "res://tests/support/CombatTestSuite.gd"
const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")

func run() -> void:
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
