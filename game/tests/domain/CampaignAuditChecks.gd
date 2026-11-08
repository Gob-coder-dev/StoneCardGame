## Audit de la campagne livrée : volumétrie, équilibre, topologie, paliers,
## précisions, decks fixes et invariants de mini-boss. La suite lit le fichier
## réel et échoue si le contenu régresse.
extends "res://tests/support/CombatTestSuite.gd"

const ContentLoader := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const AuditModel := preload("res://scripts/domain/campaign/CampaignAudit.gd")


func run() -> void:
	var content := ContentLoader.read()
	_check(bool(content.get("ok", false)), "audit : la campagne livrée est valide")
	if not bool(content.get("ok", false)):
		for problem in content.get("problems", []):
			printerr("  ", problem)
		return
	var graph: CampaignGraph = GraphModel.build(content["definition"])
	var audit := AuditModel.build(graph)

	_check(int(audit["total_nodes"]) == 154,
		"audit : exactement 154 niveaux")
	_check(int(audit["total_edges"]) == 182,
		"audit : 182 arêtes relient les 154 niveaux")
	_check(int(audit["chapter_count"]) == 12,
		"audit : douze sections visuelles structurent la carte")
	_check(int(audit["tutorial_count"]) == 3,
		"audit : trois tutoriels Pr.Stone")
	var first_three: Array = graph.nodes().slice(0, 3)
	_check(first_three.all(func(node): return node.is_tutorial()),
		"audit : les trois premiers nœuds sont les tutoriels Pr.Stone")
	for node in first_three:
		_check(node.game_mode() == GameModeRules.MODE_CLASSIC
			and node.max_power_tier() <= 2
			and float(node.ai_profile().get("precision", 1.0)) == 0.0,
			"audit : le tutoriel '%s' reste simple et sans précision" % node.id)

	_check(int(audit["mode_counts"].get("classic", 0)) == 86
		and int(audit["mode_counts"].get("random", 0)) == 23
		and int(audit["mode_counts"].get("mirror", 0)) == 16
		and int(audit["mode_counts"].get("draft", 0)) == 29,
		"audit : répartition 86 Classique / 23 Aléatoire / 16 Miroir / 29 Sélection")
	_check(int(audit["tier_counts"].get("1", 0)) == 2
		and int(audit["tier_counts"].get("2", 0)) == 38
		and int(audit["tier_counts"].get("3", 0)) == 69
		and int(audit["tier_counts"].get("4", 0)) == 45,
		"audit : paliers 1/2/3/4 = 2/38/69/45")
	_check(int(audit["series_counts"].get("ft1", 0)) == 133
		and int(audit["series_counts"].get("ft2", 0)) == 20
		and int(audit["series_counts"].get("ft3", 0)) == 1,
		"audit : 133 FT1, 20 FT2 et 1 FT3")
	_check((audit["mini_not_ft2"] as Array).is_empty(),
		"audit : tous les mini-boss sont en FT2")
	_check(int(audit["optional_mini_count"]) == 10
		and int(audit["mandatory_mini_count"]) == 4,
		"audit : dix mini-boss facultatifs et quatre obligatoires")
	_check((audit["optional_with_exit"] as Array).is_empty()
		and (audit["mandatory_bypassable"] as Array).is_empty(),
		"audit : les mini-boss facultatifs sont des impasses et les obligatoires sont incontournables")
	_check(int(audit["forced_generator_count"]) >= 3
		and int(audit["generator_god_counts"].get("veskar", 0)) >= 1
		and int(audit["generator_god_counts"].get("sylkha", 0)) >= 1
		and int(audit["generator_god_counts"].get("ilyr", 0)) >= 1,
		"audit : les branches contraintes couvrent Véskar, Sylkha et Ilyr")
	_check(int(audit["mirror_fixed_deck_count"]) == 1
		and (audit["mirror_fixed_decks"] as Array).has("r09_mini1"),
		"audit : le Miroir d'Ilyr utilise un deck fixe réservé")

	var expected_themes := {
		"veskar": 25, "nerava": 25, "kharun": 25,
		"ilyr": 25, "sylkha": 25, "enigma": 26,
	}
	var expected_fixed := {
		"veskar": 18, "nerava": 21, "kharun": 21,
		"ilyr": 15, "sylkha": 16, "enigma": 20,
	}
	for god in expected_themes:
		_check(int(audit["theme_counts"].get(god, 0)) == int(expected_themes[god]),
			"audit : le thème %s garde sa part après les approches" % god)
		_check(int(audit["fixed_god_counts"].get(god, 0)) == int(expected_fixed[god]),
			"audit : les dieux réellement fixés restent équilibrés pour %s" % god)
	_check(int(audit["theme_min"]) == 25 and int(audit["theme_max"]) == 26,
		"audit : aucun dieu n'est massivement surreprésenté")

	_check(int(audit["multi_exit_count"]) >= 25,
		"audit : au moins 25 nœuds ont plusieurs sorties")
	_check(int(audit["three_way_count"]) >= 6,
		"audit : plusieurs embranchements à trois sorties")
	_check(int(audit["four_way_count"]) >= 1,
		"audit : au moins un embranchement à quatre sorties")
	_check(int(audit["merge_count"]) >= 18,
		"audit : au moins 18 regroupements à plusieurs entrées")
	_check(int(audit["dead_end_count"]) >= 10,
		"audit : au moins 10 impasses intentionnelles hors boss final")
	_check(int(audit["max_depth"]) >= 55,
		"audit : la campagne est suffisamment profonde")
	_check(int(audit["max_mode_run"]) <= 8
		and (audit["max_mode_chain"] as Array).has("mini_optional_02"),
		"audit : la seule longue série de mode est la branche finale d'Énigma")
	_check(int(audit["max_theme_run"]) == 6
		and (audit["max_theme_chain"] as Array).has("mini_optional_02"),
		"audit : les cinq approches et leur mini-boss partagent le même dieu")
	_check((audit["unreachable"] as Array).is_empty()
		and not bool(audit["has_cycle"])
		and (audit["duplicate_edges"] as Array).is_empty(),
		"audit : tous les nœuds sont accessibles, sans cycle ni arête dupliquée")

	_check(int(audit["precision_unique"]) >= 25,
		"audit : la précision utilise une large échelle")
	_check(int(audit["precision_non_quarter"]) >= 50,
		"audit : la majorité des précisions ne sont pas des multiples de 25")
	_check(is_equal_approx(float(audit["precision_min"]), 0.0)
		and is_equal_approx(float(audit["precision_max"]), 1.0),
		"audit : la précision couvre 0 à 100 %")
	for band in audit["precision_bands"].values():
		var average := float(band["average"])
		_check(average >= 0.0 and average <= 1.0,
			"audit : chaque tranche de profondeur garde une précision valide")

	_check(int(audit["fixed_deck_count"]) == 83
		and int(audit["unique_fixed_decks"]) == 83,
		"audit : les 83 decks fixes sont uniques")
	_check(int(audit["fixed_god_deck_count"]) == 80,
		"audit : 80 decks fixes identifient un dieu adverse")
	_check(int(audit["min_fixed_god_cards"]) >= 3
		and (audit["fixed_decks_below_three"] as Array).is_empty(),
		"audit : chaque deck fixe contient au moins trois cartes de son dieu")
	_check((audit["exact_duplicate_decks"] as Array).is_empty(),
		"audit : aucun deck fixe exactement dupliqué")
	_check((audit["near_duplicate_decks"] as Array).size() <= 1,
		"audit : au plus une paire de decks partage sept cartes (tutoriels)")
	_check(float(audit["min_node_distance"]) >= 170.0,
		"audit : les nœuds restent espacés sur la carte")
	_test_optional_paths(graph)


func _test_optional_paths(graph: CampaignGraph) -> void:
	var expected := {
		"mini_optional_01": 2, "r03_mini": 2, "r04_mini": 3,
		"r05_mini": 3, "r06_mini": 3, "r09_mini1": 4,
		"r09_mini2": 4, "r10_mini": 4, "r11_mini": 4,
		"mini_optional_02": 5,
	}
	var total := 0
	for boss_id in expected:
		var boss: CampaignNode = graph.node(boss_id)
		_check(boss != null and boss.is_optional_mini_boss()
			and graph.is_dead_end(boss_id) and boss.dead_end,
			"audit : le mini-boss facultatif '%s' reste une impasse" % boss_id)
		var path_ids: Array[String] = []
		var prefix: String = str(boss_id) + "_path_"
		for node in graph.nodes():
			if node.id.begins_with(prefix):
				path_ids.append(node.id)
		_check(path_ids.size() == int(expected[boss_id]),
			"audit : '%s' reçoit %d niveaux d'approche" % [boss_id, int(expected[boss_id])])
		total += path_ids.size()
		var previous_id := ""
		var previous_precision := -1.0
		var previous_tier := 0
		for index in range(path_ids.size()):
			var path: CampaignNode = graph.node(path_ids[index])
			var precision := float(path.ai_profile().get("precision", 0.0))
			_check(path != null and not path.dead_end
				and path.theme_god_id == boss.theme_god_id
				and path.game_mode() == boss.game_mode()
				and path.fixed_god_id() == boss.fixed_god_id()
				and path.generator_god_id() == boss.generator_god_id(),
				"audit : '%s' conserve le dieu et le mode de son mini-boss" % path_ids[index])
			_check(path.max_power_tier() >= previous_tier
				and path.max_power_tier() <= boss.max_power_tier()
				and precision > previous_precision
				and precision < float(boss.ai_profile().get("precision", 0.0)),
				"audit : '%s' monte en difficulté sans dépasser son mini-boss" % path_ids[index])
			if index == 0:
				_check(graph.predecessors(path.id).size() == 1,
					"audit : '%s' n'a qu'une entrée" % path.id)
			else:
				_check(graph.predecessors(path.id) == [previous_id],
					"audit : les approches de '%s' forment une chaîne" % boss_id)
			previous_id = path.id
			previous_precision = precision
			previous_tier = path.max_power_tier()
		_check(not path_ids.is_empty()
			and graph.predecessors(boss_id) == [path_ids[path_ids.size() - 1]],
			"audit : le mini-boss '%s' ferme sa chaîne d'approche" % boss_id)
	_check(total == 34, "audit : les dix impasses ajoutent 34 niveaux")
