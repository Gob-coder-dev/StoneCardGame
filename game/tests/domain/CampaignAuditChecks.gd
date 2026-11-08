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

	_check(int(audit["total_nodes"]) == 120,
		"audit : exactement 120 niveaux")
	_check(int(audit["total_edges"]) == 148,
		"audit : 148 arêtes relient les 120 niveaux")
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

	_check(int(audit["mode_counts"].get("classic", 0)) == 72
		and int(audit["mode_counts"].get("random", 0)) == 18
		and int(audit["mode_counts"].get("mirror", 0)) == 12
		and int(audit["mode_counts"].get("draft", 0)) == 18,
		"audit : répartition 72 Classique / 18 Aléatoire / 12 Miroir / 18 Sélection")
	_check(int(audit["tier_counts"].get("1", 0)) == 2
		and int(audit["tier_counts"].get("2", 0)) == 32
		and int(audit["tier_counts"].get("3", 0)) == 52
		and int(audit["tier_counts"].get("4", 0)) == 34,
		"audit : paliers 1/2/3/4 = 2/32/52/34")
	_check(int(audit["series_counts"].get("ft1", 0)) == 99
		and int(audit["series_counts"].get("ft2", 0)) == 20
		and int(audit["series_counts"].get("ft3", 0)) == 1,
		"audit : 99 FT1, 20 FT2 et 1 FT3")
	_check((audit["mini_not_ft2"] as Array).is_empty(),
		"audit : tous les mini-boss sont en FT2")
	_check(int(audit["optional_mini_count"]) == 10
		and int(audit["mandatory_mini_count"]) == 4,
		"audit : dix mini-boss facultatifs et quatre obligatoires")
	_check((audit["optional_with_exit"] as Array).is_empty()
		and (audit["mandatory_bypassable"] as Array).is_empty(),
		"audit : les mini-boss facultatifs sont des impasses et les obligatoires sont incontournables")
	_check(int(audit["forced_generator_count"]) == 2
		and int(audit["generator_god_counts"].get("veskar", 0)) == 1
		and int(audit["generator_god_counts"].get("ilyr", 0)) == 1,
		"audit : Véskar et Ilyr portent les deux générateurs contraints")
	_check(int(audit["mirror_fixed_deck_count"]) == 1
		and (audit["mirror_fixed_decks"] as Array).has("r09_mini1"),
		"audit : le Miroir d'Ilyr utilise un deck fixe réservé")

	for god in ["veskar", "nerava", "kharun", "ilyr", "sylkha", "enigma"]:
		var count := int(audit["theme_counts"].get(god, 0))
		_check(count >= 18 and count <= 21,
			"audit : le thème %s garde entre 18 et 21 rencontres" % god)
		var fixed_count := int(audit["fixed_god_counts"].get(god, 0))
		_check(fixed_count >= 12 and fixed_count <= 17,
			"audit : les dieux réellement fixés restent équilibrés pour %s" % god)
	_check(int(audit["theme_min"]) >= 18 and int(audit["theme_max"]) <= 21,
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
	_check(int(audit["max_mode_run"]) <= 6,
		"audit : aucun parcours ne dépasse six modes identiques consécutifs")
	_check(int(audit["max_theme_run"]) <= 3,
		"audit : aucun parcours ne dépasse trois rencontres du même dieu")
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

	_check(int(audit["fixed_deck_count"]) == 69
		and int(audit["unique_fixed_decks"]) == 69,
		"audit : les 69 decks fixes sont uniques")
	_check(int(audit["fixed_god_deck_count"]) == 66,
		"audit : 66 decks fixes identifient un dieu adverse")
	_check(int(audit["min_fixed_god_cards"]) >= 3
		and (audit["fixed_decks_below_three"] as Array).is_empty(),
		"audit : chaque deck fixe contient au moins trois cartes de son dieu")
	_check((audit["exact_duplicate_decks"] as Array).is_empty(),
		"audit : aucun deck fixe exactement dupliqué")
	_check((audit["near_duplicate_decks"] as Array).size() <= 1,
		"audit : au plus une paire de decks partage sept cartes (tutoriels)")
	_check(float(audit["min_node_distance"]) >= 170.0,
		"audit : les nœuds restent espacés sur la carte")
