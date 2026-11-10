## Contenu livré du scénario : dialogues Pr. Stone, parcours multi-scènes et
## setup du match gagnant. Le chargeur doit aussi signaler un contenu cassé.
extends "res://tests/support/CombatTestSuite.gd"

const LoaderModel := preload("res://scripts/data/story/StoryContentLoader.gd")
const TriggerRulesModel := preload("res://scripts/domain/story/StoryTriggerRules.gd")


func run() -> void:
	_test_shipped_content()
	_test_broken_content_is_reported()


func _test_shipped_content() -> void:
	var content := LoaderModel.read()
	_check(bool(content.get("ok", false)), "scénario : le contenu livré est valide")
	for problem in content.get("problems", []):
		printerr("  ", problem)
	var dialogues: Dictionary = content.get("dialogues", {})
	var characters: Dictionary = dialogues.get("characters", {})
	_check(characters.has("pr_stone"), "scénario : Pr. Stone est déclaré comme personnage")
	var sequences: Dictionary = dialogues.get("sequences", {})
	for sequence_id in [
		"journey_welcome", "journey_deck_intro", "journey_campaign_intro",
		"journey_level_intro", "journey_victory", "journey_deck_swap_intro",
		"journey_deck_swap_done",
	]:
		_check(sequences.has(sequence_id),
			"scénario : la séquence '%s' de Pr. Stone existe" % sequence_id)
	var welcome: Dictionary = sequences.get("journey_welcome", {})
	var welcome_lines: Array = welcome.get("lines", [])
	_check(welcome_lines.size() >= 3, "scénario : l'accueil installe le Refuge et le cabinet")
	_check(str(welcome_lines[0].get("text", "")).contains("{player_name}"),
		"scénario : le nom du joueur reste un modèle remplacé à la lecture")
	var all_stone := true
	for value in welcome_lines:
		all_stone = all_stone and str(value.get("speaker", "")) == "pr_stone"
	_check(all_stone, "scénario : l'accueil est réellement prononcé par Pr. Stone")
	var triggers: Array = dialogues.get("triggers", [])
	_check(triggers.is_empty(),
		"scénario : l'ancienne intro générique de niveau a disparu")
	var tutorials: Dictionary = content.get("tutorials", {})
	var chapters: Dictionary = tutorials.get("chapters", {})
	var chapter: Dictionary = chapters.get("first_journey", {})
	_check(str(chapter.get("entry_scene", "")) == "res://scenes/menus/MainMenu.tscn"
		and str(chapter.get("match_node_id", "")) == "tuto_01",
		"tutoriels : le parcours commence à l'accueil et scénarise tuto_01")
	var steps: Array = chapter.get("steps", [])
	_check(steps.size() >= 25, "tutoriels : le parcours couvre toutes les scènes")
	var by_id := {}
	for value in steps:
		by_id[str(value.get("id", ""))] = value
	for step_id in [
		"welcome", "open_decks", "deck_intro", "return_home", "campaign",
		"first_level", "launch_level", "start_match", "first_card", "place_first",
		"first_card", "place_first", "second_card", "place_second", "third_card",
		"place_third", "fourth_card", "place_fourth", "victory_gate", "victory",
		"leave_result", "open_decks_again", "swap_intro", "swap_use",
		"swap_target", "swap_done",
	]:
		_check(by_id.has(step_id), "tutoriels : l'étape '%s' existe" % step_id)
	_check(str(by_id.get("welcome", {}).get("dialogue", "")) == "journey_welcome"
		and str(by_id.get("welcome", {}).get("anchor", "")) == "",
		"tutoriels : Pr. Stone ouvre le parcours sans dépendre d'une ancre")
	_check(str(by_id.get("open_decks", {}).get("anchor", "")) == "nav.deck"
		and str(by_id.get("open_decks", {}).get("wait_for", "")) == "screen_opened",
		"tutoriels : le cabinet est guidé depuis l'onglet DECKS")
	_check(str(by_id.get("deck_intro", {}).get("anchor", "")) == "collection.deck_panel"
		and str(by_id.get("deck_intro", {}).get("wait_for", "")) == "tutorial_advance",
		"tutoriels : le deck est présenté avant de revenir à l'accueil")
	_check(str(by_id.get("return_home", {}).get("anchor", "")) == "nav.home"
		and str(by_id.get("campaign", {}).get("anchor", "")) == "menu.campaign",
		"tutoriels : le retour à l'accueil puis la Campagne sont guidés")
	_check(str(by_id.get("first_level", {}).get("anchor", "")) == "map.node.tuto_01"
		and str(by_id.get("first_level", {}).get("wait_for", "")) == "campaign_node_opened",
		"tutoriels : le premier niveau est visé sur la carte")
	_check(str(by_id.get("launch_level", {}).get("anchor", "")) == "map.launch"
		and str(by_id.get("start_match", {}).get("anchor", "")) == "prebattle.start",
		"tutoriels : le lancement et l'avant-combat sont guidés")
	for step_id in ["first_card", "second_card", "third_card", "fourth_card"]:
		_check(str(by_id.get(step_id, {}).get("anchor", "")).begins_with("board.hand.card."),
			"tutoriels : l'étape '%s' vise une carte précise de la main" % step_id)
	for step_id in ["place_first", "place_second", "place_third", "place_fourth"]:
		_check(str(by_id.get(step_id, {}).get("anchor", "")).begins_with("board.cell."),
			"tutoriels : l'étape '%s' vise une case précise" % step_id)
	_check(str(by_id.get("wait_bot_1", {}).get("wait_for", "")) == "turn_started"
		and not bool(by_id.get("wait_bot_1", {}).get("spotlight", true)),
		"tutoriels : le tour du bot est une porte sans faux bouton")
	_check(str(by_id.get("victory", {}).get("scene", "")) == "res://scenes/menus/Result.tscn"
		and str(by_id.get("victory", {}).get("dialogue", "")) == "journey_victory",
		"tutoriels : la victoire est racontée sur l'écran de résultat")
	_check(str(by_id.get("leave_result", {}).get("anchor", "")) == "result.home"
		and str(by_id.get("open_decks_again", {}).get("anchor", "")) == "nav.deck",
		"tutoriels : le retour au deck est guidé depuis le résultat")
	_check(str(by_id.get("swap_intro", {}).get("anchor", ""))
			== "collection.card.le_sac_a_murmures_n1"
		and str(by_id.get("swap_intro", {}).get("wait_for", "")) == "collection_card_opened",
		"tutoriels : la nouvelle carte est mise en surbrillance")
	_check(str(by_id.get("swap_use", {}).get("anchor", "")) == "collection.action.primary"
		and str(by_id.get("swap_use", {}).get("wait_for", "")) == "replacement_opened",
		"tutoriels : l'action du tiroir est guidée")
	_check(str(by_id.get("swap_target", {}).get("anchor", "")) == "collection.replace.first"
		and str(by_id.get("swap_target", {}).get("wait_for", "")) == "deck_card_replaced",
		"tutoriels : la carte du deck à remplacer est guidée")
	_check(str(by_id.get("swap_done", {}).get("dialogue", "")) == "journey_deck_swap_done",
		"tutoriels : la dernière leçon rend la main au joueur")
	var match_setup: Dictionary = chapter.get("match", {})
	_check(int(match_setup.get("board_size", 0)) == 3
		and int(match_setup.get("first_player", 0)) == 1
		and (match_setup.get("initial_stones", []) as Array).size() == 1
		and (match_setup.get("opponent_plan", []) as Array).size() == 4,
		"tutoriels : le match fournit le plateau, le premier joueur et le plan du bot")
	var plan: Array = match_setup.get("opponent_plan", [])
	_check(not plan.is_empty() and int(plan[0].get("row", -1)) == 1
		and int(plan[0].get("col", -1)) == 2
		and str(plan[0].get("stone_id", "")) == "le_drape_du_seuil_n1",
		"tutoriels : le bot commence par le Drap de la Muraille")
	for deck_key in ["player_deck", "opponent_deck"]:
		var deck: Array = match_setup.get(deck_key, [])
		for stone_id in deck:
			_check(StoneLoader.has_stone(str(stone_id)),
				"tutoriels : la carte '%s' du setup existe" % str(stone_id))


func _test_broken_content_is_reported() -> void:
	var dialogues := {
		"characters": {
			"broken": {"name": "Cassé", "asset": "res://assets/gods/introuvable.png"},
		},
		"sequences": {
			"broken_seq": {"lines": [
				{"speaker": "fantome", "text": "Qui parle ?"},
			]},
		},
		"triggers": [],
	}
	var problems: Array[String] = []
	LoaderModel._validate_dialogues(dialogues, problems)
	_check(problems.size() >= 2,
		"validation : un portrait absent et un locuteur inconnu sont signalés")
	var tutorials := {
		"chapters": {
			"broken_chapter": {
				"steps": [{
					"id": "step",
					"anchor": "",
					"wait_for": "inconnu",
					"dialogue": "absente",
				}],
			},
		},
	}
	var tutorial_problems: Array[String] = []
	LoaderModel._validate_tutorials(tutorials, {"sequences": {}}, tutorial_problems)
	_check(tutorial_problems.size() >= 3,
		"validation : un chapitre sans entrée, action, événement ni dialogue est signalé")
	var gate_chapter := {
		"chapters": {
			"gate_chapter": {
				"entry_scene": "res://scenes/menus/MainMenu.tscn",
				"steps": [{
					"id": "gate",
					"scene": "res://scenes/game/Board.tscn",
					"wait_for": "turn_started",
					"spotlight": false,
				}],
			},
		},
	}
	var gate_problems: Array[String] = []
	LoaderModel._validate_tutorials(gate_chapter, {"sequences": {}}, gate_problems)
	_check(gate_problems.is_empty(),
		"validation : une porte sans ancre mais avec un événement est valide")
