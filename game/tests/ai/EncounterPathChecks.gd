## Vérifie le catalogue du chemin (quinze niveaux par source) et la règle pure
## de déblocage, sans interface ni écriture de sauvegarde.
extends "res://tests/support/CombatTestSuite.gd"

const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const EncounterPathModel := preload("res://scripts/domain/EncounterPath.gd")


func run() -> void:
	_test_level_order()
	_test_unlock_rule()
	_test_next_level()
	_test_source_lookup()


func _test_level_order() -> void:
	var sources: Array = []
	for god in StoneLoader.get_all_gods():
		sources.append(str(god["id"]))
	sources.append(OpponentCatalogModel.NEUTRAL_BOT_ID)
	var unique := {}
	var total := 0
	var ordered := true
	var chapters := true
	for source_id in sources:
		var levels := OpponentCatalogModel.levels_for(source_id)
		total += levels.size()
		var chapter_bracket := ""
		for index in range(levels.size()):
			var level: Dictionary = levels[index]
			unique[str(level["opponent_id"])] = true
			ordered = ordered and int(level["index"]) == index \
				and str(level["source_id"]) == source_id
			var bracket := str(level["bracket_id"])
			if bracket != chapter_bracket:
				chapters = chapters and bool(level["chapter_start"]) \
					and int(level["chapter_index"]) \
						== int(index / float(OpponentCatalogModel.DIFFICULTIES.size()))
				chapter_bracket = bracket
			elif bool(level["chapter_start"]):
				chapters = false
	_check(sources.size() == 7 and total == 105 and unique.size() == 105 and ordered,
		"les six dieux et Pr.Stone proposent chacun quinze niveaux ordonnés, sans doublon")
	_check(chapters, "les cinq difficultés d'un palier forment un seul chapitre du chemin")


func _test_unlock_rule() -> void:
	var levels := OpponentCatalogModel.levels_for("veskar")
	var beaten := {"bot_veskar_n1_tres_facile": true}
	var path := EncounterPathModel.states(levels,
		func(opponent_id: String) -> bool: return beaten.has(opponent_id))
	_check(int(path[0]["state"]) == EncounterPathModel.State.COMPLETED
		and bool(path[0]["completed"]) and bool(path[0]["playable"]),
		"une victoire enregistrée termine le premier rond")
	_check(int(path[1]["state"]) == EncounterPathModel.State.AVAILABLE
		and bool(path[1]["playable"])
		and int(path[2]["state"]) == EncounterPathModel.State.LOCKED
		and not bool(path[2]["playable"]),
		"seul le niveau qui suit un rond terminé s'ouvre")
	_check(EncounterPathModel.completed_count(path) == 1
		and EncounterPathModel.current_index(path) == 1
		and not EncounterPathModel.is_complete(path),
		"le chemin propose le premier niveau encore à gagner")
	var last_index := levels.size() - 1
	var isolated := {str(levels[last_index]["opponent_id"]): true}
	var out_of_order := EncounterPathModel.states(levels,
		func(opponent_id: String) -> bool: return isolated.has(opponent_id))
	_check(int(out_of_order[0]["state"]) == EncounterPathModel.State.AVAILABLE
		and bool(out_of_order[last_index]["beaten"])
		and int(out_of_order[last_index]["state"]) == EncounterPathModel.State.LOCKED
		and not bool(out_of_order[last_index]["completed"])
		and EncounterPathModel.completed_count(out_of_order) == 0,
		"une victoire hors séquence n'ouvre pas le chemin et ne valide pas un rond isolé")
	var empty_path := EncounterPathModel.states(levels,
		func(_opponent_id: String) -> bool: return false)
	_check(int(empty_path[0]["state"]) == EncounterPathModel.State.AVAILABLE
		and EncounterPathModel.current_index(empty_path) == 0,
		"le premier niveau reste toujours ouvert sur un profil neuf")
	var all_beaten := {}
	for level in levels:
		all_beaten[str(level["opponent_id"])] = true
	var complete := EncounterPathModel.states(levels,
		func(opponent_id: String) -> bool: return all_beaten.has(opponent_id))
	_check(EncounterPathModel.is_complete(complete)
		and EncounterPathModel.completed_count(complete) == levels.size()
		and EncounterPathModel.current_index(complete) == levels.size() - 1,
		"un parcours entièrement gagné reste complet et garde son dernier niveau")


## Le résultat ne recopie pas l'ordre du chemin : le domaine fournit le
## successeur immédiat, y compris pour un adversaire neutre.
func _test_next_level() -> void:
	var levels := OpponentCatalogModel.levels_for("veskar")
	var second := EncounterPathModel.next_level(levels, str(levels[0]["opponent_id"]))
	_check(str(second.get("opponent_id", "")) == str(levels[1]["opponent_id"])
		and str(second.get("difficulty_id", "")) == "facile",
		"le domaine donne le niveau immédiatement suivant dans l'ordre du chemin")
	_check(EncounterPathModel.next_level(levels, str(levels[-1]["opponent_id"])).is_empty()
		and EncounterPathModel.next_level(levels, "inconnu").is_empty(),
		"le dernier niveau et un adversaire inconnu n'ont pas de suivant")


func _test_source_lookup() -> void:
	var opponent := OpponentCatalogModel.build("enigma", "n2", "difficile")
	var neutral := OpponentCatalogModel.build_neutral("n34", "moyen")
	var historical := StoneLoader.get_npc("disciple_muraille")
	_check(OpponentCatalogModel.source_id_of(opponent) == "enigma"
		and OpponentCatalogModel.source_id_of(neutral) == OpponentCatalogModel.NEUTRAL_BOT_ID
		and OpponentCatalogModel.source_id_of(historical) == "",
		"un adversaire généré retrouve la source de son chemin, un PNJ historique n'en a pas")
	_check(OpponentCatalogModel.build_for_source("enigma", "n2", "difficile")["id"]
		== opponent["id"]
		and OpponentCatalogModel.build_for_source(
			OpponentCatalogModel.NEUTRAL_BOT_ID, "n34", "moyen")["id"] == neutral["id"],
		"le chemin génère exactement les adversaires du catalogue")
	_check(OpponentCatalogModel.source_for("enigma")["id"] == "enigma"
		and OpponentCatalogModel.source_for(OpponentCatalogModel.NEUTRAL_BOT_ID)["id"]
			== OpponentCatalogModel.NEUTRAL_BOT_ID
		and OpponentCatalogModel.levels_for("inconnu").is_empty(),
		"la fiche d'une source et ses niveaux restent cohérents")
	var saved_source := BattleContext.selected_source_id
	var saved_opponent := BattleContext.selected_opponent
	BattleContext.selected_source_id = ""
	BattleContext.selected_opponent = {}
	_check(BattleContext.navigation_source_id() == PlayerData.player_god_id,
		"la navigation retombe sur le dieu du joueur sans chemin ouvert")
	BattleContext.selected_source_id = saved_source
	BattleContext.selected_opponent = saved_opponent
