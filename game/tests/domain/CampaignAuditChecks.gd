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

	_check(int(audit["total_nodes"]) == 162,
		"audit : exactement 162 niveaux")
	_check(int(audit["total_edges"]) == 190,
		"audit : 190 arêtes relient les 162 niveaux")
	_check(int(audit["chapter_count"]) == 13,
		"audit : treize sections visuelles structurent la carte")
	_check(int(audit["tutorial_count"]) == 5,
		"audit : cinq tutoriels Pr.Stone")
	var first_five: Array = graph.nodes().slice(0, 5)
	_check(first_five.all(func(node): return node.is_tutorial()),
		"audit : les cinq premiers nœuds sont les tutoriels Pr.Stone")
	for node in first_five:
		_check(node.game_mode() == GameModeRules.MODE_CLASSIC
			and node.max_power_tier() == 1
			and float(node.ai_profile().get("precision", 1.0)) <= 0.04,
			"audit : le tutoriel '%s' reste très facile et au palier 1" % node.id)

	_check(int(audit["mode_counts"].get("classic", 0)) == 95
		and int(audit["mode_counts"].get("random", 0)) == 21
		and int(audit["mode_counts"].get("mirror", 0)) == 21
		and int(audit["mode_counts"].get("draft", 0)) == 25,
		"audit : les modes sont variés après l'apprentissage Classique")
	_check(int(audit["tier_counts"].get("1", 0)) == 13
		and int(audit["tier_counts"].get("2", 0)) == 42
		and int(audit["tier_counts"].get("3", 0)) == 36
		and int(audit["tier_counts"].get("4", 0)) == 71,
		"audit : les paliers suivent les quatre phases de progression")
	_check(int(audit["series_counts"].get("ft1", 0)) == 144
		and int(audit["series_counts"].get("ft2", 0)) == 17
		and int(audit["series_counts"].get("ft3", 0)) == 1,
		"audit : chaque mini-boss est en FT2 et le boss final en FT3")
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
	_check(int(audit["mirror_fixed_deck_count"]) == 7
		and (audit["mirror_fixed_decks"] as Array).has("r09_mini1")
		and (audit["mirror_fixed_decks"] as Array).has("init_veskar")
		and (audit["mirror_fixed_decks"] as Array).has("init_enigma"),
		"audit : les six initiations et le mini-boss Ilyr utilisent des decks miroirs fixes")
	var trial_gods := {
		"init_veskar": "veskar", "init_nerava": "nerava", "init_kharun": "kharun",
		"init_ilyr": "ilyr", "init_sylkha": "sylkha", "init_enigma": "enigma",
	}
	for node_id in trial_gods:
		var trial: CampaignNode = graph.node(node_id)
		var deck := trial.mirror_fixed_deck()
		var god_cards := 0
		var neutral_cards := 0
		var all_common_n1 := deck.size() == DeckRules.DECK_SIZE
		for stone_id in deck:
			var affinity := StoneLoader.stone_affinity(str(stone_id))
			god_cards += 1 if affinity == str(trial_gods[node_id]) else 0
			neutral_cards += 1 if affinity == "neutral" else 0
			all_common_n1 = all_common_n1 \
				and StoneLoader.stone_rarity(str(stone_id)) == "common" \
				and StoneLoader.stone_level(str(stone_id)) == 1 \
				and CardPowerTierRules.effective_tier(StoneLoader.get_stone(str(stone_id))) == 1
		_check(trial.max_power_tier() == 1 and god_cards == 4 and neutral_cards == 4
			and all_common_n1,
			"audit : l'initiation '%s' impose quatre communes du dieu et quatre neutres N1" % node_id)

	for node_id in ["veskar_01", "nerava_01", "kharun_01", "ilyr_01", "sylkha_01"]:
		var entry: CampaignNode = graph.node(node_id)
		var tier_one := 0
		var tier_two := 0
		for stone_id in entry.fixed_deck():
			var tier := CardPowerTierRules.effective_tier(StoneLoader.get_stone(str(stone_id)))
			tier_one += 1 if tier == 1 else 0
			tier_two += 1 if tier == 2 else 0
		_check(tier_one == 6 and tier_two == 2,
			"audit : l'entrée '%s' contient six cartes palier 1 et deux palier 2" % node_id)

	var expected_themes := {
		"veskar": 26, "nerava": 26, "kharun": 26,
		"ilyr": 26, "sylkha": 26, "enigma": 27,
	}
	var expected_fixed := {
		"veskar": 18, "nerava": 21, "kharun": 21,
		"ilyr": 16, "sylkha": 17, "enigma": 21,
	}
	for god in expected_themes:
		_check(int(audit["theme_counts"].get(god, 0)) == int(expected_themes[god]),
			"audit : le thème %s garde sa part après les approches" % god)
		_check(int(audit["fixed_god_counts"].get(god, 0)) == int(expected_fixed[god]),
			"audit : les dieux réellement fixés restent équilibrés pour %s" % god)
	_check(int(audit["theme_min"]) == 26 and int(audit["theme_max"]) == 27,
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
	_check(int(audit["max_mode_run"]) <= 24,
		"audit : l'apprentissage Classique ne monopolise pas toute la campagne")
	_check(int(audit["max_theme_run"]) == 6
		and (audit["max_theme_chain"] as Array).has("mini_optional_02"),
		"audit : les cinq approches et leur mini-boss partagent le même dieu")
	_check((audit["unreachable"] as Array).is_empty()
		and not bool(audit["has_cycle"])
		and (audit["duplicate_edges"] as Array).is_empty(),
		"audit : tous les nœuds sont accessibles, sans cycle ni arête dupliquée")
	_test_required_boss_progression(graph)

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

	_check(int(audit["fixed_deck_count"]) == 94
		and int(audit["unique_fixed_decks"]) == 94,
		"audit : les 94 decks fixes sont uniques")
	_check(int(audit["fixed_god_deck_count"]) == 89,
		"audit : 89 decks fixes identifient un dieu adverse")
	_check(int(audit["min_fixed_god_cards"]) >= 3
		and (audit["fixed_decks_below_three"] as Array).is_empty(),
		"audit : chaque deck fixe contient au moins trois cartes de son dieu")
	_check((audit["exact_duplicate_decks"] as Array).is_empty(),
		"audit : aucun deck fixe exactement dupliqué")
	var near_duplicates := audit["near_duplicate_decks"] as Array
	var only_tutorial_neighbours := near_duplicates.size() == 10
	for pair in near_duplicates:
		only_tutorial_neighbours = only_tutorial_neighbours \
			and str(pair.get("first", "")).begins_with("tuto_") \
			and str(pair.get("second", "")).begins_with("tuto_")
	_check(only_tutorial_neighbours,
		"audit : seules les dix paires des cinq tutoriels partagent sept cartes")
	_check(float(audit["min_node_distance"]) >= 170.0,
		"audit : les nœuds restent espacés sur la carte")
	_test_optional_paths(graph)


func _test_required_boss_progression(graph: CampaignGraph) -> void:
	var required_gap := float(CampaignBalanceConfig.get_config().get(
		"required_boss_precision_gap", 0.06))
	for boss_variant in graph.nodes():
		var boss := boss_variant as CampaignNode
		if boss == null or (not boss.is_mandatory_mini_boss() and not boss.is_boss()):
			continue
		for parent_id in graph.predecessors(boss.id):
			var parent := graph.node(parent_id)
			_check(parent != null
				and parent.balance_profile == "boss_approach"
				and boss.max_power_tier() >= parent.max_power_tier()
				and float(boss.ai_profile().get("precision", 0.0)) + 0.001
					>= float(parent.ai_profile().get("precision", 0.0)) + required_gap,
				"audit : le boss '%s' domine clairement son approche '%s'" % [
					boss.id, parent_id])

	var convergence := graph.node("convergence_01")
	var first_gate := graph.node("boss_required_gate")
	var tier_one := 0
	var tier_two := 0
	for stone_id in convergence.fixed_deck():
		var tier := CardPowerTierRules.effective_tier(StoneLoader.get_stone(str(stone_id)))
		tier_one += 1 if tier == 1 else 0
		tier_two += 1 if tier == 2 else 0
	_check(tier_one == 6 and tier_two == 2
		and float(convergence.ai_profile().get("precision", 1.0)) <= 0.24
		and float(first_gate.ai_profile().get("precision", 0.0)) >= 0.30,
		"audit : La Convergence prépare le premier mini-boss sans le dépasser")


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
