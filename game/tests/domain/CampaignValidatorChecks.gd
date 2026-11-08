## Validation exhaustive du contenu : cas valides, liens cassés, cycles,
## impasses, mini-boss, decks, dieux, modes et positions.
extends "res://tests/support/CombatTestSuite.gd"

const ValidatorModel := preload("res://scripts/domain/campaign/CampaignValidator.gd")
const ContentLoader := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")
const CONTENT_PATH := "res://data/campaign/campaign_v2.json"


func run() -> void:
	_test_shipped_content()
	_test_minimal_fixture()
	_test_identifiers_and_links()
	_test_structure_rules()
	_test_mini_boss_rules()
	_test_deck_and_tier_rules()
	_test_nodes_and_positions()


func _content_dict() -> Dictionary:
	var file := FileAccess.open(CONTENT_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


func _neutral_deck() -> Array:
	var content := _content_dict()
	for raw in content.get("nodes", []):
		if raw is Dictionary and str(raw.get("id", "")) == "tuto_01":
			return (raw.get("encounter", {}).get("fixed_deck", []) as Array).duplicate()
	return []


func _node(node_id: String, x: float, y: float, node_type: String = "normal",
		deck: Array = []) -> Dictionary:
	return {
		"id": node_id,
		"name": node_id,
		"chapter": "",
		"region": "",
		"type": node_type,
		"position": {"x": x, "y": y},
		"dead_end": false,
		"mini_boss_kind": "",
		"tutorial_id": "",
		"encounter": {
			"game_mode": "classic",
			"opponent_god_policy": "fixed",
			"opponent_deck_policy": "fixed",
			"fixed_god_id": "veskar",
			"fixed_deck": deck.duplicate(),
			"max_power_tier": 4,
			"ai_profile": {"precision": 0.0, "anticipation": false},
			"series_format": "ft1",
			"seed_policy": "fixed_per_node",
			"seed": 1,
		},
	}


func _edge(edge_id: String, from_id: String, to_id: String) -> Dictionary:
	return {"id": edge_id, "from": from_id, "to": to_id}


func _minimal() -> Dictionary:
	var neutral := _neutral_deck()
	var deck: Array = ProfileFixture.DECK.duplicate()
	var start := _node("start", 540, 100, "tutorial", neutral)
	start["encounter"]["fixed_god_id"] = ""
	start["encounter"]["max_power_tier"] = 2
	var start_two := _node("start_two", 540, 300, "tutorial", neutral)
	start_two["encounter"]["fixed_god_id"] = ""
	start_two["encounter"]["max_power_tier"] = 2
	var a := _node("a", 200, 500, "normal", deck)
	var b := _node("b", 540, 500, "normal", deck)
	var optional := _node("mini_optional", 200, 700, "mini_boss", deck)
	optional["mini_boss_kind"] = "optional"
	optional["dead_end"] = true
	optional["encounter"]["series_format"] = "ft2"
	var gate := _node("gate", 540, 700, "mini_boss", deck)
	gate["mini_boss_kind"] = "mandatory"
	gate["encounter"]["series_format"] = "ft2"
	var final := _node("final", 540, 900, "boss", deck)
	final["encounter"]["series_format"] = "ft3"
	return {
		"id": "fixture_campaign",
		"title": "Fixture",
		"campaign_version": 1,
		"map": {"width": 1080, "height": 1100},
		"start_node_id": "start",
		"final_node_id": "final",
		"nodes": [start, start_two, a, b, optional, gate, final],
		"edges": [
			_edge("e0", "start", "start_two"),
			_edge("e1", "start_two", "a"),
			_edge("e2", "start_two", "b"),
			_edge("e3", "a", "mini_optional"),
			_edge("e4", "b", "gate"),
			_edge("e5", "gate", "final"),
		],
	}


func _has(problems: Array[String], fragment: String) -> bool:
	for problem in problems:
		if problem.contains(fragment):
			return true
	return false


func _test_shipped_content() -> void:
	# Seul contrôle qui prépare réellement les drafts : il reste dans la suite
	# de contenu, jamais dans le chemin d'ouverture de la carte.
	var content := ContentLoader.read(ContentLoader.DEFAULT_PATH, true)
	_check(bool(content.get("ok", false)) and (content.get("problems", []) as Array).is_empty(),
		"validateur : la campagne livrée ne produit aucune erreur")
	if not bool(content.get("ok", false)):
		for problem in content.get("problems", []):
			printerr("  ", problem)


func _test_minimal_fixture() -> void:
	var problems := ValidatorModel.problems(_minimal())
	_check(problems.is_empty(), "validateur : une fixture minimale valide est acceptée")
	if not problems.is_empty():
		for problem in problems:
			printerr("  ", problem)


func _test_identifiers_and_links() -> void:
	var definition := _minimal()
	definition["nodes"][1]["id"] = "start"
	_check(_has(ValidatorModel.problems(definition), "dupliqué"),
		"validateur : un identifiant de nœud dupliqué est refusé")

	definition = _minimal()
	definition["edges"][0]["to"] = "absent"
	_check(_has(ValidatorModel.problems(definition), "nœud absent"),
		"validateur : une arête vers un nœud absent est refusée")

	definition = _minimal()
	definition["edges"].append(_edge("e_dup", "start", "start_two"))
	_check(_has(ValidatorModel.problems(definition), "arête dupliquée"),
		"validateur : une seconde arête entre les mêmes nœuds est refusée")

	definition = _minimal()
	definition["edges"].append(_edge("e_cycle", "final", "start"))
	_check(_has(ValidatorModel.problems(definition), "cycle"),
		"validateur : une boucle est refusée")

	definition = _minimal()
	definition["nodes"].append(_node("isolated", 900, 100, "normal",
		ProfileFixture.DECK.duplicate()))
	var isolated_problems := ValidatorModel.problems(definition)
	_check(_has(isolated_problems, "inaccessible"),
		"validateur : un nœud normal sans lien est refusé")


func _test_structure_rules() -> void:
	var definition := _minimal()
	definition["start_node_id"] = "start_two"
	_check(_has(ValidatorModel.problems(definition), "prédécesseur"),
		"validateur : le départ ne peut pas avoir de prédécesseur")

	definition = _minimal()
	definition["final_node_id"] = "absent"
	_check(_has(ValidatorModel.problems(definition), "objectif final"),
		"validateur : un objectif final absent est refusé")

	definition = _minimal()
	definition["nodes"][0]["type"] = "normal"
	_check(_has(ValidatorModel.problems(definition), "tutoriel"),
		"validateur : le niveau de départ doit être un tutoriel")

	definition = _minimal()
	definition["nodes"][2]["branch_kind"] = "main"
	_check(_has(ValidatorModel.problems(definition), "champ de structure interdit"),
		"validateur : un champ de branche principale est refusé")

	definition = _minimal()
	definition["nodes"][2]["type"] = "normal"
	definition["nodes"][2]["dead_end"] = true
	_check(_has(ValidatorModel.problems(definition), "possède une sortie"),
		"validateur : une impasse déclarée avec une sortie est refusée")

	definition = _minimal()
	definition["nodes"][4]["type"] = "normal"
	definition["nodes"][4]["mini_boss_kind"] = ""
	definition["nodes"][4]["dead_end"] = false
	_check(_has(ValidatorModel.problems(definition), "impasse non déclarée"),
		"validateur : une impasse sans déclaration est refusée")


func _test_mini_boss_rules() -> void:
	var definition := _minimal()
	definition["edges"].append(_edge("e_optional_exit", "mini_optional", "final"))
	_check(_has(ValidatorModel.problems(definition), "mini-boss facultatif"),
		"validateur : un mini-boss facultatif avec une sortie est refusé")

	definition = _minimal()
	definition["edges"].append(_edge("e_bypass", "a", "final"))
	_check(_has(ValidatorModel.problems(definition), "contournable"),
		"validateur : un mini-boss obligatoire contournable est refusé")

	definition = _minimal()
	definition["nodes"][4]["encounter"]["series_format"] = "ft1"
	_check(_has(ValidatorModel.problems(definition), "FT2"),
		"validateur : un mini-boss en FT1 est refusé")

	definition = _minimal()
	definition["nodes"][5]["mini_boss_kind"] = ""
	_check(_has(ValidatorModel.problems(definition), "mini_boss_kind"),
		"validateur : un mini-boss sans type obligatoire/facultatif est refusé")

	definition = _minimal()
	definition["nodes"][2]["mini_boss_kind"] = "optional"
	_check(_has(ValidatorModel.problems(definition), "mini_boss_kind interdit"),
		"validateur : un marqueur de mini-boss sur un nœud normal est refusé")


func _test_deck_and_tier_rules() -> void:
	var definition := _minimal()
	(definition["nodes"][2]["encounter"]["fixed_deck"] as Array).pop_back()
	_check(_has(ValidatorModel.problems(definition), "deck fixe"),
		"validateur : un deck fixe de sept cartes est refusé")

	definition = _minimal()
	definition["nodes"][2]["encounter"]["max_power_tier"] = 2
	(definition["nodes"][2]["encounter"]["fixed_deck"] as Array)[0] = "avortons_des_caves_n3"
	_check(_has(ValidatorModel.problems(definition), "au-dessus du palier"),
		"validateur : une carte au-dessus du palier annoncé est refusée")

	definition = _minimal()
	var deck: Array = definition["nodes"][2]["encounter"]["fixed_deck"]
	deck[1] = deck[0]
	_check(_has(ValidatorModel.problems(definition), "lignée dupliquée"),
		"validateur : deux cartes de la même lignée sont refusées")

	definition = _minimal()
	var weak_deck: Array = definition["nodes"][2]["encounter"]["fixed_deck"]
	var neutral: Array = _neutral_deck()
	var replaced := [0, 1, 2, 5]
	for position in range(replaced.size()):
		weak_deck[int(replaced[position])] = neutral[position]
	_check(_has(ValidatorModel.problems(definition), "au moins 3 cartes du dieu"),
		"validateur : un deck fixe sans assez de cartes du dieu est refusé")

	definition = _minimal()
	definition["nodes"][0]["encounter"]["ai_profile"]["precision"] = 0.5
	_check(_has(ValidatorModel.problems(definition), "tutoriel"),
		"validateur : un tutoriel avec une IA précise est refusé")

	definition = _minimal()
	definition["nodes"][2]["encounter"]["game_mode"] = "random"
	_check(_has(ValidatorModel.problems(definition), "Aléatoire"),
		"validateur : un mode Aléatoire avec des politiques fixes est refusé")

	definition = _minimal()
	definition["nodes"][2]["encounter"]["fixed_god_id"] = "inconnu"
	_check(_has(ValidatorModel.problems(definition), "dieu inconnu"),
		"validateur : un dieu inexistant est refusé")

	definition = _minimal()
	var random_encounter: Dictionary = definition["nodes"][2]["encounter"]
	random_encounter["game_mode"] = "random"
	random_encounter["opponent_god_policy"] = "generated"
	random_encounter["opponent_deck_policy"] = "generated"
	random_encounter["fixed_god_id"] = ""
	random_encounter["fixed_deck"] = []
	random_encounter["generator_god_id"] = "inconnu"
	random_encounter["generator_min_god_cards"] = DeckRules.DECK_SIZE
	_check(_has(ValidatorModel.problems(definition), "dieu de génération inconnu"),
		"validateur : un générateur contraint refuse un dieu inexistant")

	definition = _minimal()
	var excessive_encounter: Dictionary = definition["nodes"][2]["encounter"]
	excessive_encounter["game_mode"] = "random"
	excessive_encounter["opponent_god_policy"] = "generated"
	excessive_encounter["opponent_deck_policy"] = "generated"
	excessive_encounter["fixed_god_id"] = ""
	excessive_encounter["fixed_deck"] = []
	excessive_encounter["generator_god_id"] = "ilyr"
	excessive_encounter["generator_min_god_cards"] = DeckRules.DECK_SIZE + 1
	_check(_has(ValidatorModel.problems(definition), "minimum de cartes du dieu hors bornes"),
		"validateur : une affinité minimale supérieure à la taille du deck est refusée")

	definition = _minimal()
	var mirror_encounter: Dictionary = definition["nodes"][2]["encounter"]
	mirror_encounter["game_mode"] = "mirror"
	mirror_encounter["opponent_god_policy"] = "mirrored"
	mirror_encounter["opponent_deck_policy"] = "mirrored"
	mirror_encounter["fixed_god_id"] = ""
	mirror_encounter["fixed_deck"] = []
	mirror_encounter["generator_god_id"] = "ilyr"
	mirror_encounter["generator_min_god_cards"] = 7
	mirror_encounter["mirror_fixed_deck"] = (ProfileFixture.DECK as Array).slice(0, 7)
	_check(_has(ValidatorModel.problems(definition), "deck miroir"),
		"validateur : un deck miroir fixe incomplet est refusé")


func _test_nodes_and_positions() -> void:
	var definition := _minimal()
	definition["nodes"][2]["position"]["x"] = 2000
	_check(_has(ValidatorModel.problems(definition), "hors de la carte"),
		"validateur : une position hors de la carte est refusée")

	definition = _minimal()
	definition["nodes"][3]["position"] = definition["nodes"][2]["position"].duplicate()
	_check(_has(ValidatorModel.problems(definition), "trop proches"),
		"validateur : deux nœuds trop proches sont refusés")

	definition = _minimal()
	definition["nodes"][2]["type"] = "inconnu"
	_check(_has(ValidatorModel.problems(definition), "type inconnu"),
		"validateur : un type de nœud inconnu est refusé")
