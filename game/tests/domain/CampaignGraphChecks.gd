## Vérifie le graphe de campagne : embranchements non exclusifs, regroupement
## ANY, rejeu, cycles et contenu réel. Aucune scène, aucune sauvegarde.
extends "res://tests/support/CombatTestSuite.gd"

const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const UnlockRules := preload("res://scripts/domain/campaign/CampaignUnlockRules.gd")
const ContentLoader := preload("res://scripts/data/campaign/CampaignContentLoader.gd")


func run() -> void:
	_test_three_way_branch()
	_test_any_convergence()
	_test_cycles_and_reachability()
	_test_shipped_content_graph()


func _node(id: String, position: Vector2, type: String = "normal") -> Dictionary:
	return {
		"id": id,
		"name": id,
		"chapter": "",
		"region": "",
		"type": type,
		"position": {"x": position.x, "y": position.y},
		"dead_end": false,
		"encounter": {},
	}


func _edge(id: String, from_id: String, to_id: String) -> Dictionary:
	return {"id": id, "from": from_id, "to": to_id}


func _definition(nodes: Array, edges: Array, start: String, final: String) -> Dictionary:
	return {
		"id": "fixture",
		"title": "Fixture",
		"campaign_version": 1,
		"map": {"width": 1080, "height": 1200},
		"start_node_id": start,
		"final_node_id": final,
		"nodes": nodes,
		"edges": edges,
	}


func _test_three_way_branch() -> void:
	var definition := _definition([
		_node("start", Vector2(540, 150), "tutorial"),
		_node("a", Vector2(180, 380)),
		_node("b", Vector2(540, 380)),
		_node("c", Vector2(900, 380)),
	], [
		_edge("e1", "start", "a"),
		_edge("e2", "start", "b"),
		_edge("e3", "start", "c"),
	], "start", "c")
	var graph: CampaignGraph = GraphModel.build(definition)
	_check(graph.successors("start").size() == 3,
		"graphe : un nœud peut avoir trois sorties")
	var states := UnlockRules.states(graph, {"start": true})
	_check(int(states["a"]) == UnlockRules.State.AVAILABLE
		and int(states["b"]) == UnlockRules.State.AVAILABLE
		and int(states["c"]) == UnlockRules.State.AVAILABLE,
		"graphe : toutes les branches d'un niveau terminé deviennent accessibles")
	states = UnlockRules.states(graph, {"start": true, "a": true})
	_check(int(states["b"]) == UnlockRules.State.AVAILABLE
		and int(states["c"]) == UnlockRules.State.AVAILABLE,
		"graphe : terminer une branche ne verrouille jamais les branches sœurs")
	_check(UnlockRules.is_available(graph, "a", {"start": true, "a": true}),
		"graphe : un nœud terminé reste rejouable")
	_check(not UnlockRules.is_available(graph, "b", {}),
		"graphe : un nœud sans prédécesseur terminé reste verrouillé")


func _test_any_convergence() -> void:
	var definition := _definition([
		_node("start", Vector2(540, 120), "tutorial"),
		_node("p1", Vector2(180, 340)),
		_node("p2", Vector2(540, 340)),
		_node("p3", Vector2(900, 340)),
		_node("conv", Vector2(540, 600)),
	], [
		_edge("e0", "start", "p1"),
		_edge("e1", "start", "p2"),
		_edge("e2", "start", "p3"),
		_edge("e3", "p1", "conv"),
		_edge("e4", "p2", "conv"),
		_edge("e5", "p3", "conv"),
	], "start", "conv")
	var graph: CampaignGraph = GraphModel.build(definition)
	var states := UnlockRules.states(graph, {"start": true, "p2": true})
	_check(graph.predecessors("conv").size() == 3,
		"graphe : un regroupement peut avoir trois prédécesseurs")
	_check(int(states["conv"]) == UnlockRules.State.AVAILABLE,
		"graphe : un regroupement s'ouvre dès qu'un seul prédécesseur est terminé")
	states = UnlockRules.states(graph, {"start": true, "p1": true})
	_check(int(states["conv"]) == UnlockRules.State.AVAILABLE
		and int(states["p2"]) == UnlockRules.State.AVAILABLE
		and int(states["p3"]) == UnlockRules.State.AVAILABLE,
		"graphe : ANY n'oblige jamais à terminer toutes les branches convergentes")


func _test_cycles_and_reachability() -> void:
	var cycle := _definition([
		_node("a", Vector2(200, 200)),
		_node("b", Vector2(500, 200)),
	], [
		_edge("ab", "a", "b"),
		_edge("ba", "b", "a"),
	], "a", "b")
	var cycle_graph: CampaignGraph = GraphModel.build(cycle)
	_check(cycle_graph.has_cycle(), "graphe : une boucle involontaire est détectée")
	var reachable := cycle_graph.reachable_from("a")
	_check(reachable.has("a") and reachable.has("b"),
		"graphe : la reachability traverse les arêtes orientées")
	var without_b := cycle_graph.reachable_from("a", "b")
	_check(without_b.has("a") and not without_b.has("b"),
		"graphe : un nœud exclu n'est jamais traversé")
	var branch := _definition([
		_node("start", Vector2(200, 100)),
		_node("dead", Vector2(200, 350)),
		_node("isolated", Vector2(800, 350)),
	], [
		_edge("e", "start", "dead"),
	], "start", "dead")
	var branch_graph: CampaignGraph = GraphModel.build(branch)
	var reached := branch_graph.reachable_from("start")
	_check(reached.has("dead") and not reached.has("isolated"),
		"graphe : un nœud sans lien reste inaccessible")
	_check(not branch_graph.has_cycle(), "graphe : une branche simple n'a pas de cycle")


func _test_shipped_content_graph() -> void:
	var content := ContentLoader.read()
	_check(bool(content.get("ok", false)),
		"contenu : campaign_v2.json est lisible et validé")
	if not bool(content.get("ok", false)):
		return
	var graph: CampaignGraph = GraphModel.build(content["definition"])
	_check(graph.node_count() == 120 and graph.edge_count() >= 145,
		"contenu : la campagne fournit exactement 120 nœuds et un graphe dense")
	_check(not graph.has_cycle(), "contenu : le graphe livré est acyclique")
	_check(graph.successors("tuto_03").size() == 3,
		"contenu : les tutoriels ouvrent au moins trois branches")
	_check(graph.successors("veskar_01").size() >= 2
		and graph.successors("choice_01").size() >= 2,
		"contenu : une branche se divise une seconde fois")
	_check(graph.predecessors("convergence_01").size() >= 2
		and graph.predecessors("r03_m").size() >= 2
		and graph.predecessors("r12_m").size() >= 2,
		"contenu : plusieurs branches se regroupent à des profondeurs différentes")
	var tutorial_count := 0
	var modes := {}
	var policies := {}
	var optional_mini := 0
	var mandatory_mini := 0
	for node in graph.nodes():
		if node.is_tutorial():
			tutorial_count += 1
			_check(node.game_mode() == GameModeRules.MODE_CLASSIC
				and node.max_power_tier() <= 2
				and float(node.ai_profile().get("precision", 1.0)) == 0.0,
				"contenu : le tutoriel '%s' est Classique, palier ≤ 2, précision 0" % node.id)
		else:
			_check(node.theme_god_id != "",
				"contenu : chaque rencontre non-tutorielle porte un thème de dieu")
		if node.is_mini_boss():
			_check(node.series_format() == SeriesRules.SERIES_FT2,
				"contenu : le mini-boss '%s' est en FT2" % node.id)
		modes[node.game_mode()] = true
		policies[node.opponent_god_policy()] = true
		policies[node.opponent_deck_policy()] = true
		if node.is_optional_mini_boss():
			optional_mini += 1
			_check(graph.is_dead_end(node.id) and node.dead_end,
				"contenu : le mini-boss facultatif '%s' est au bout d'une impasse" % node.id)
		if node.is_mandatory_mini_boss():
			mandatory_mini += 1
	_check(tutorial_count == 3, "contenu : les trois premiers niveaux sont des tutoriels Pr.Stone")
	_check(modes.has(GameModeRules.MODE_CLASSIC) and modes.has(GameModeRules.MODE_RANDOM)
		and modes.has(GameModeRules.MODE_MIRROR) and modes.has(GameModeRules.MODE_DRAFT),
		"contenu : les quatre modes sont réellement représentés")
	_check(policies.has(CampaignNode.GOD_FIXED) and policies.has(CampaignNode.GOD_PROFILE)
		and policies.has(CampaignNode.GOD_MIRRORED)
		and policies.has(CampaignNode.DECK_FIXED) and policies.has(CampaignNode.DECK_GENERATED)
		and policies.has(CampaignNode.DECK_MIRRORED) and policies.has(CampaignNode.DECK_DRAFT),
		"contenu : dieux et decks couvrent toutes les politiques")
	_check(optional_mini == 10 and mandatory_mini == 4,
		"contenu : dix mini-boss facultatifs et quatre obligatoires sont présents")
	var without_gate := graph.reachable_from(graph.start_node_id, "boss_required_gate")
	_check(not without_gate.has("final_01"),
		"contenu : le mini-boss obligatoire ne peut pas être contourné")
	_check(graph.is_dead_end("final_01") and graph.final_node().is_boss(),
		"contenu : le boss final termine la campagne")
