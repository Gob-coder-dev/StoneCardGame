## Contenu livré du scénario : dialogues Pr. Stone, parcours multi-scènes,
## plateau vide du tutoriel, chapitres 2/3 et présentations des reflets. Le
## chargeur doit aussi signaler un contenu cassé.
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
		"journey_level_intro", "journey_first_move", "journey_second_move",
		"journey_third_move", "journey_fourth_move", "journey_fifth_move",
		"journey_victory", "journey_deck_swap_intro", "journey_deck_swap_done",
		"tuto_02_intro", "tuto_03_intro",
	]:
		_check(sequences.has(sequence_id),
			"scénario : la séquence '%s' existe" % sequence_id)
	var welcome: Dictionary = sequences.get("journey_welcome", {})
	var welcome_lines: Array = welcome.get("lines", [])
	_check(welcome_lines.size() >= 3, "scénario : l'accueil installe le Refuge et le cabinet")
	_check(str(welcome_lines[0].get("text", "")).contains("{player_name}"),
		"scénario : le nom du joueur reste un modèle remplacé à la lecture")
	var all_monster := true
	for value in welcome_lines:
		all_monster = all_monster and str(value.get("speaker", "")) == "pr_stone"
	_check(all_monster, "scénario : l'accueil est réellement prononcé par Pr. Stone")
	var victory_lines: Array = sequences.get("journey_victory", {}).get("lines", [])
	var mentions_rewards := false
	for value in victory_lines:
		mentions_rewards = mentions_rewards \
			or str(value.get("text", "")).to_lower().contains("récompense")
	_check(mentions_rewards,
		"scénario : la victoire annonce explicitement les récompenses")

	## Les six premiers reflets : chaque dieu se présente lui-même, puis
	## Pr. Stone explique son fonctionnement et la manière de le battre.
	var triggers: Array = dialogues.get("triggers", [])
	var start_triggers := 0
	var trigger_by_node := {}
	for value in triggers:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		if str(entry.get("event", "")) == "level_start":
			start_triggers += 1
			trigger_by_node[str(entry.get("node_id", ""))] = entry
	## 6 présentations de reflets + 12 défis d'impasse + 11 rages de dernier
	## niveau. L'impasse Ilyr à un seul niveau utilise un `level_won`.
	_check(start_triggers == 29,
		"scénario : les reflets et les impasses ont leur présentation de niveau")
	for god_id in ["veskar", "nerava", "kharun", "ilyr", "sylkha", "enigma"]:
		var trigger: Dictionary = trigger_by_node.get("init_%s" % god_id, {})
		_check(str(trigger.get("event", "")) == "level_start"
			and str(trigger.get("sequence", "")) == "mirror_%s" % god_id
			and bool(trigger.get("once", false)),
			"scénario : le reflet '%s' se présente une seule fois au lancement" % god_id)
		var mirror: Dictionary = sequences.get("mirror_%s" % god_id, {})
		var has_god := false
		var has_monster := false
		for line_value in mirror.get("lines", []):
			if not line_value is Dictionary:
				continue
			var speaker := str(line_value.get("speaker", ""))
			has_god = has_god or speaker == "theme_god"
			has_monster = has_monster or speaker == "pr_stone"
		_check((mirror.get("lines", []) as Array).size() >= 3 and has_god and has_monster,
			"scénario : %s parle, puis Pr. Stone explique comment le battre" % god_id)

	## Chaque impasse hors boss final a un défi au premier niveau et une rage au
	## dernier. `veilleur_impasse` n'a qu'un niveau : sa rage est jouée à la
	## victoire, par un déclencheur `level_won`.
	var dead_end_intros := {
		"mini_optional_01_path_1": "nerava_cloche_intro",
		"veilleur_impasse": "ilyr_veilleur_intro",
		"r03_mini_path_1": "veskar_jeu_intro",
		"r04_mini_path_1": "sylkha_essaim_intro",
		"r05_mini_path_1": "kharun_encre_intro",
		"r06_mini_path_1": "sylkha_colporteur_intro",
		"r09_mini1_path_1": "ilyr_garde_intro",
		"r09_mini2_path_1": "ilyr_choeur_intro",
		"r10_mini_path_1": "nerava_mime_intro",
		"r11_mini_path_1": "kharun_rempart_intro",
		"mini_optional_02_path_1": "enigma_collectionneur_intro",
		"r08_power_1": "veskar_tirage_intro",
	}
	for dead_end_intro_node in dead_end_intros.keys():
		var intro_trigger: Dictionary = trigger_by_node.get(str(dead_end_intro_node), {})
		_check(str(intro_trigger.get("sequence", "")) == str(dead_end_intros[dead_end_intro_node])
			and bool(intro_trigger.get("once", false)),
			"scénario : l'impasse '%s' défie le joueur dès son premier niveau" % str(dead_end_intro_node))

	var dead_end_finales := {
		"mini_optional_01": "nerava_cloche_final",
		"r03_mini": "veskar_jeu_final",
		"r04_mini": "sylkha_essaim_final",
		"r05_mini": "kharun_encre_final",
		"r06_mini": "sylkha_colporteur_final",
		"r09_mini1": "ilyr_garde_final",
		"r09_mini2": "ilyr_choeur_final",
		"r10_mini": "nerava_mime_final",
		"r11_mini": "kharun_rempart_final",
		"mini_optional_02": "enigma_collectionneur_final",
		"r08_power_3": "veskar_tirage_final",
	}
	for dead_end_final_node in dead_end_finales.keys():
		var final_trigger: Dictionary = trigger_by_node.get(str(dead_end_final_node), {})
		_check(str(final_trigger.get("sequence", "")) == str(dead_end_finales[dead_end_final_node])
			and bool(final_trigger.get("once", false)),
			"scénario : le dieu de '%s' s'énerve au dernier niveau" % str(dead_end_final_node))

	var veilleur_rage := {}
	for value in triggers:
		if not value is Dictionary:
			continue
		var rage_entry: Dictionary = value
		if str(rage_entry.get("node_id", "")) == "veilleur_impasse" \
				and str(rage_entry.get("event", "")) == "level_won":
			veilleur_rage = rage_entry
	_check(str(veilleur_rage.get("sequence", "")) == "ilyr_veilleur_rage"
		and str(veilleur_rage.get("outcome", "")) == "win"
		and bool(veilleur_rage.get("once", false)),
		"scénario : l'impasse à un seul niveau garde sa rage pour la victoire")

	## Trois victoires ferment un chapitre : la conclusion est propre au niveau,
	## ne filtre que la victoire et ne se joue qu'une fois.
	var victory_sequences := {
		"tuto_02": "tuto_02_victory",
		"tuto_05": "tuto_05_victory",
		"init_enigma": "mirror_enigma_victory",
	}
	for victory_node in victory_sequences.keys():
		var node_id := str(victory_node)
		var sequence_id := str(victory_sequences[victory_node])
		var victory_trigger := {}
		for value in triggers:
			if not value is Dictionary:
				continue
			var victory_entry: Dictionary = value
			if str(victory_entry.get("node_id", "")) == node_id \
					and str(victory_entry.get("event", "")) == "level_won":
				victory_trigger = victory_entry
		_check(str(victory_trigger.get("sequence", "")) == sequence_id
			and str(victory_trigger.get("outcome", "")) == "win"
			and bool(victory_trigger.get("once", false))
			and sequences.has(sequence_id),
			"scénario : la victoire de '%s' conclut le niveau une seule fois" % node_id)

	var tutorials: Dictionary = content.get("tutorials", {})
	var chapters: Dictionary = tutorials.get("chapters", {})
	var chapter: Dictionary = chapters.get("first_journey", {})
	_check(str(chapter.get("entry_scene", "")) == "res://scenes/menus/MainMenu.tscn"
		and str(chapter.get("match_node_id", "")) == "tuto_01",
		"tutoriels : le parcours commence à l'accueil et scénarise tuto_01")
	var steps: Array = chapter.get("steps", [])
	_check(steps.size() >= 30, "tutoriels : le parcours couvre toutes les scènes")
	var by_id := {}
	for value in steps:
		by_id[str(value.get("id", ""))] = value
	for step_id in [
		"welcome", "open_decks", "deck_intro", "return_home", "campaign",
		"first_level", "launch_level", "prebattle_flip", "start_match",
		"first_card", "place_first", "wait_bot_1", "second_card", "place_second",
		"wait_bot_2", "third_card", "place_third", "wait_bot_3", "fourth_card",
		"place_fourth", "wait_bot_4", "fifth_card", "place_fifth", "victory_gate",
		"victory", "rewards", "leave_result", "open_decks_again", "swap_intro",
		"swap_use", "swap_target", "swap_done",
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
	var flip: Dictionary = by_id.get("prebattle_flip", {})
	_check(str(flip.get("scene", "")) == "res://scenes/menus/PreBattle.tscn"
		and str(flip.get("anchor", "")) == ""
		and not bool(flip.get("spotlight", true))
		and str(flip.get("wait_for", "")) == "prebattle_ready"
		and bool(flip.get("expect", {}).get("player_starts", false)),
		"tutoriels : le tirage reste visible avant de demander COMMENCER")
	for step_id in ["first_card", "second_card", "third_card", "fourth_card", "fifth_card"]:
		_check(str(by_id.get(step_id, {}).get("anchor", "")).begins_with("board.hand.card."),
			"tutoriels : l'étape '%s' vise une carte précise de la main" % step_id)
	for step_id in ["place_first", "place_second", "place_third", "place_fourth", "place_fifth"]:
		_check(str(by_id.get(step_id, {}).get("anchor", "")).begins_with("board.cell."),
			"tutoriels : l'étape '%s' vise une case précise" % step_id)
	_check(str(by_id.get("place_first", {}).get("anchor", "")) == "board.cell.0.0"
		and str(by_id.get("place_second", {}).get("anchor", "")) == "board.cell.2.1"
		and str(by_id.get("place_third", {}).get("anchor", "")) == "board.cell.1.1"
		and str(by_id.get("place_fourth", {}).get("anchor", "")) == "board.cell.0.1"
		and str(by_id.get("place_fifth", {}).get("anchor", "")) == "board.cell.2.0",
		"tutoriels : les cinq poses suivent un plan cohérent")
	_check(str(by_id.get("wait_bot_1", {}).get("wait_for", "")) == "turn_started"
		and not bool(by_id.get("wait_bot_1", {}).get("spotlight", true)),
		"tutoriels : le tour du bot est une porte sans faux bouton")
	_check(str(by_id.get("victory", {}).get("scene", "")) == "res://scenes/menus/Result.tscn"
		and str(by_id.get("victory", {}).get("dialogue", "")) == "journey_victory",
		"tutoriels : la victoire est racontée sur l'écran de résultat")
	_check(str(by_id.get("rewards", {}).get("anchor", "")) == "result.rewards"
		and str(by_id.get("rewards", {}).get("wait_for", "")) == "tutorial_advance",
		"tutoriels : les récompenses sont mises en surbrillance à la victoire")
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
	var plan: Array = match_setup.get("opponent_plan", [])
	_check(int(match_setup.get("board_size", 0)) == 3
		and int(match_setup.get("first_player", 0)) == 1
		and (match_setup.get("initial_monsters", []) as Array).is_empty()
		and plan.size() == 4,
		"tutoriels : le match fournit un plateau vide, le premier joueur et le plan du bot")
	_check(plan.size() == 4 and int(plan[0].get("row", -1)) == 2
		and int(plan[0].get("col", -1)) == 2
		and str(plan[0].get("monster_id", "")) == "le_drape_du_seuil_n1",
		"tutoriels : le bot répond par le Drap dans le coin opposé")
	_check(plan.size() == 4 and int(plan[1].get("row", -1)) == 1
		and int(plan[1].get("col", -1)) == 0
		and str(plan[1].get("monster_id", "")) == "mordeur_des_combles_n1",
		"tutoriels : le bot riposte ensuite avec le Mordeur qui prend la Gueule")
	for deck_key in ["player_deck", "opponent_deck"]:
		var deck: Array = match_setup.get(deck_key, [])
		for monster_id in deck:
			_check(MonsterLoader.has_monster(str(monster_id)),
				"tutoriels : la carte '%s' du setup existe" % str(monster_id))

	## Les deux leçons de terrain : taille puis cases bloquées.
	var tuto_02: Dictionary = chapters.get("tuto_02", {})
	var steps_02: Array = tuto_02.get("steps", [])
	_check(str(tuto_02.get("entry_node_id", "")) == "tuto_02"
		and steps_02.size() >= 1
		and str(steps_02[0].get("scene", "")) == "res://scenes/game/Board.tscn"
		and str(steps_02[0].get("anchor", "")) == "board.cell.3.3"
		and str(steps_02[0].get("dialogue", "")) == "tuto_02_intro",
		"tutoriels : le niveau 2 montre un plateau de quatre cases")
	var tuto_03: Dictionary = chapters.get("tuto_03", {})
	var steps_03: Array = tuto_03.get("steps", [])
	var setup_03: Dictionary = tuto_03.get("match", {})
	_check(str(tuto_03.get("entry_node_id", "")) == "tuto_03"
		and steps_03.size() >= 1
		and str(steps_03[0].get("anchor", "")) == "board.cell.1.1"
		and str(steps_03[0].get("dialogue", "")) == "tuto_03_intro"
		and int(setup_03.get("board_size", 0)) == 4
		and (setup_03.get("blocked_cells", []) as Array).size() == 2,
		"tutoriels : le niveau 3 montre deux cases bloquées et leur effet")


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
	## Un chapitre peut ne fournir que la géométrie : les decks restent ceux de
	## la campagne, et les cases bloquées sont vérifiées.
	var geometry_chapter := {
		"chapters": {
			"geometry_chapter": {
				"entry_node_id": "tuto_03",
				"match": {"board_size": 4, "blocked_cells": [[1, 1], [2, 2]]},
				"steps": [{
					"id": "intro",
					"scene": "res://scenes/game/Board.tscn",
					"dialogue": "",
					"wait_for": "tutorial_advance",
				}],
			},
		},
	}
	var geometry_problems: Array[String] = []
	LoaderModel._validate_tutorials(geometry_chapter, {"sequences": {}}, geometry_problems)
	_check(geometry_problems.is_empty(),
		"validation : un setup de match limité à la géométrie est accepté")
	var broken_block := {
		"chapters": {
			"broken_block": {
				"entry_node_id": "tuto_03",
				"match": {"board_size": 4, "blocked_cells": [[1]]},
				"steps": [{
					"id": "intro",
					"scene": "res://scenes/game/Board.tscn",
					"wait_for": "tutorial_advance",
				}],
			},
		},
	}
	var block_problems: Array[String] = []
	LoaderModel._validate_tutorials(broken_block, {"sequences": {}}, block_problems)
	_check(block_problems.size() == 1,
		"validation : une case bloquée incomplète est refusée")
	var rule_ok := TriggerRulesModel.EVENTS.has("level_start") \
		and TriggerRulesModel.WAIT_EVENTS.has("prebattle_ready")
	_check(rule_ok, "déclencheurs : le lancement et le tirage restent des événements connus")
