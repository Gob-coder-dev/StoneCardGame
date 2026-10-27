## Vérifie la fabrique d'adversaires : profils fixes, decks complets et
## déterminisme entre deux ouvertures de l'écran des Rencontres.
extends "res://tests/support/CombatTestSuite.gd"

const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")

## Difficulté → précision fixe, anticipation et étoiles affichées.
const EXPECTED_TIERS: Array = [
	["tres_facile", 0.0, false, 1],
	["facile", 0.25, false, 2],
	["moyen", 0.5, false, 3],
	["difficile", 0.75, false, 4],
	["tres_difficile", 1.0, true, 5],
]


func run() -> void:
	_test_difficulty_profiles()
	_test_generated_decks()
	_test_deck_stability()
	_test_progression_rows()
	_test_battle_context()


func _test_difficulty_profiles() -> void:
	var profiles_match := true
	for row in EXPECTED_TIERS:
		var level := OpponentCatalogModel.difficulty(str(row[0]))
		profiles_match = profiles_match \
			and not level.is_empty() \
			and is_equal_approx(float(level["precision"]), float(row[1])) \
			and bool(level["anticipation"]) == bool(row[2]) \
			and int(level["stars"]) == int(row[3])
	_check(profiles_match, "les cinq difficultés suivent les précisions fixes et l'anticipation prévue")
	_check(OpponentCatalogModel.problems().is_empty(),
		"chaque dieu et chaque palier produisent un deck et un profil d'IA valides")


func _test_generated_decks() -> void:
	var complete := true
	var in_bracket := true
	var built_opponents := 0
	for god in StoneLoader.get_all_gods():
		var god_id := str(god["id"])
		for tier in OpponentCatalogModel.BRACKETS:
			var bracket_id := str(tier["id"])
			var deck := OpponentCatalogModel.deck_for(god_id, bracket_id)
			if deck.size() != DeckRules.DECK_SIZE:
				complete = false
				continue
			var seen := {}
			for raw_id in deck:
				var stone_id := str(raw_id)
				var lineage := StoneLoader.stone_lineage(stone_id)
				complete = complete \
					and StoneLoader.has_stone(stone_id) \
					and not seen.has(lineage) \
					and StoneLoader.is_stone_available_to_god(stone_id, god_id)
				seen[lineage] = true
				var level := StoneLoader.stone_level(stone_id)
				in_bracket = in_bracket \
					and level >= int(tier["min_level"]) \
					and level <= int(tier["max_level"])
			for level in OpponentCatalogModel.DIFFICULTIES:
				var opponent := OpponentCatalogModel.build(
					god_id, bracket_id, str(level["id"]))
				if not opponent.is_empty() and opponent["deck"] == deck:
					built_opponents += 1
	_check(complete, "les decks générés contiennent huit lignées distinctes du dieu")
	_check(in_bracket, "chaque carte générée appartient au palier choisi")
	_check(built_opponents == StoneLoader.get_all_gods().size()
		* OpponentCatalogModel.BRACKETS.size() * OpponentCatalogModel.DIFFICULTIES.size(),
		"les six dieux sont disponibles aux trois paliers et aux cinq difficultés")


func _test_deck_stability() -> void:
	var first := OpponentCatalogModel.build("inari", "n34", "moyen")
	var same := OpponentCatalogModel.build("inari", "n34", "moyen")
	var harder := OpponentCatalogModel.build("inari", "n34", "tres_difficile")
	var other_bracket := OpponentCatalogModel.build("inari", "n2", "moyen")
	_check(first["deck"] == same["deck"] and first["deck"] == harder["deck"],
		"une rencontre garde son deck d'une difficulté à l'autre et d'une session à l'autre")
	_check(first["deck"] != other_bracket["deck"],
		"les paliers Niveau 2 et Niveau 3 préparent des decks différents")
	_check(first["ai"] == {"precision": 0.5, "anticipation": false}
		and harder["ai"] == {"precision": 1.0, "anticipation": true},
		"le profil d'IA suit la difficulté choisie")


func _test_progression_rows() -> void:
	var rows := OpponentCatalogModel.progression_rows()
	var ids := {}
	for row in rows:
		for raw_id in row["difficulty_ids"]:
			ids[str(raw_id)] = true
	_check(rows.size() == 18 and ids.size() == 90,
		"le profil regroupe dix-huit dieu × palier et suit les quatre-vingt-dix rencontres")


func _test_battle_context() -> void:
	var saved_id := BattleContext.selected_npc_id
	var saved_opponent := BattleContext.selected_opponent
	var opponent := OpponentCatalogModel.build("inari", "n34", "difficile")
	BattleContext.select_opponent(opponent)
	var current := BattleContext.current_opponent()
	_check(BattleContext.selected_npc_id == opponent["id"]
		and current.get("id", "") == opponent["id"] and current["deck"] == opponent["deck"],
		"le contexte mémorise l'adversaire généré et son identifiant de statistiques")
	BattleContext.selected_opponent = {}
	BattleContext.selected_npc_id = "hiro"
	_check(BattleContext.current_opponent().get("id", "") == "hiro",
		"un adversaire historique reste accessible quand aucun adversaire généré ne correspond")
	BattleContext.selected_npc_id = saved_id
	BattleContext.selected_opponent = saved_opponent
