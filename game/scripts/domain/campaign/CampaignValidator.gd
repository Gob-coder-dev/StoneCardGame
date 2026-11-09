## CampaignValidator.gd
## Validation exhaustive du contenu de campagne. Le validateur ne sauvegarde
## rien et ne dessine rien : il transforme une définition en liste d'erreurs
## exploitables, utilisée au chargement et par les tests.
class_name CampaignValidator
extends RefCounted

const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const NodeModel := preload("res://scripts/domain/campaign/CampaignNode.gd")
const CardPowerTierRulesModel := preload("res://scripts/domain/CardPowerTierRules.gd")
const DeckRulesModel := preload("res://scripts/domain/DeckRules.gd")
const GameModeRulesModel := preload("res://scripts/domain/GameModeRules.gd")
const SeriesRulesModel := preload("res://scripts/domain/SeriesRules.gd")
const AIProfileModel := preload("res://scripts/ai/AIProfile.gd")

## Ces champs décriraient une route choisie ou une hiérarchie de difficulté :
## la campagne est un graphe où toutes les branches restent équivalentes.
const FORBIDDEN_STRUCTURE_KEYS: Array[String] = [
	"branch_kind", "chosen_branch", "chosen_route", "difficulty_path",
	"easy_path", "hard_path", "main_path", "path_kind", "route",
	"selected_branch", "unlock_policy",
]

const MIN_NODE_DISTANCE: float = 170.0
## Un deck à dieu identifié doit réellement porter ce dieu : les cartes
## neutres restent autorisées, mais ne comptent pas dans ce minimum.
const MIN_GOD_CARDS: int = 3


static func problems(definition: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if definition.is_empty():
		result.append("définition de campagne absente.")
		return result

	var version := int(definition.get("campaign_version", 0))
	if version <= 0:
		result.append("campaign_version positive requise.")
	if str(definition.get("id", "")) == "":
		result.append("identifiant de campagne absent.")
	var map_size := Vector2(1080.0, 1920.0)
	var raw_map: Variant = definition.get("map", {})
	if not raw_map is Dictionary:
		result.append("carte de campagne absente (champ map).")
	else:
		var width := float(raw_map.get("width", 0.0))
		var height := float(raw_map.get("height", 0.0))
		if width <= 0.0 or height <= 0.0 or not is_finite(width) or not is_finite(height):
			result.append("dimensions de carte invalides.")
		else:
			map_size = Vector2(width, height)

	var raw_nodes: Variant = definition.get("nodes", [])
	if not raw_nodes is Array or (raw_nodes as Array).is_empty():
		result.append("aucun nœud de campagne.")
		return result
	var raw_edges: Variant = definition.get("edges", [])
	if not raw_edges is Array:
		result.append("liste d'arêtes invalide.")
		return result

	var seen_nodes := {}
	var seen_positions := {}
	var tutorial_count := 0
	for raw in raw_nodes:
		if not raw is Dictionary:
			result.append("nœud non-objet dans la liste.")
			continue
		var node_id := str(raw.get("id", ""))
		if node_id == "":
			result.append("nœud sans identifiant.")
			continue
		if seen_nodes.has(node_id):
			result.append("identifiant de nœud dupliqué '%s'." % node_id)
		seen_nodes[node_id] = true
		var node: CampaignNode = NodeModel.from_dict(raw)
		if str(raw.get("name", "")) == "":
			result.append("nom affiché absent sur '%s'." % node_id)
		if not NodeModel.TYPES.has(node.type):
			result.append("type inconnu '%s' sur '%s'." % [node.type, node_id])
		for forbidden in FORBIDDEN_STRUCTURE_KEYS:
			if raw.has(forbidden):
				result.append("champ de structure interdit '%s' sur '%s'." % [forbidden, node_id])
		var raw_position: Variant = raw.get("position", {})
		if not raw_position is Dictionary:
			result.append("position absente sur '%s'." % node_id)
		else:
			var x_value: Variant = raw_position.get("x")
			var y_value: Variant = raw_position.get("y")
			if not _is_number(x_value) or not _is_number(y_value):
				result.append("position non numérique sur '%s'." % node_id)
			else:
				var point := Vector2(float(x_value), float(y_value))
				if not is_finite(point.x) or not is_finite(point.y) \
						or point.x < 0.0 or point.y < 0.0 \
						or point.x > map_size.x or point.y > map_size.y:
					result.append("position hors de la carte sur '%s'." % node_id)
				else:
					for other_id in seen_positions:
						if point.distance_to(seen_positions[other_id]) < MIN_NODE_DISTANCE:
							result.append("nœuds trop proches '%s' et '%s'." % [
								node_id, other_id])
							break
					seen_positions[node_id] = point
		if node.type == NodeModel.TYPE_TUTORIAL:
			tutorial_count += 1
		if node.type == NodeModel.TYPE_MINI_BOSS \
				and not [NodeModel.MINI_BOSS_OPTIONAL, NodeModel.MINI_BOSS_MANDATORY].has(node.mini_boss_kind):
			result.append("mini-boss '%s' sans mini_boss_kind valide." % node_id)
		if node.type != NodeModel.TYPE_MINI_BOSS and node.mini_boss_kind != "":
			result.append("mini_boss_kind interdit sur '%s'." % node_id)
		if node.theme_god_id != "" and StoneLoader.get_god(node.theme_god_id).is_empty():
			result.append("dieu de thème inconnu '%s' sur '%s'." % [node.theme_god_id, node_id])
		_encounter_problems(node, result)

	if tutorial_count < 2:
		result.append("la campagne doit commencer par au moins deux tutoriels.")

	var seen_edge_ids := {}
	var seen_pairs := {}
	for raw in raw_edges:
		if not raw is Dictionary:
			result.append("arête non-objet dans la liste.")
			continue
		var edge_id := str(raw.get("id", ""))
		var from_id := str(raw.get("from", ""))
		var to_id := str(raw.get("to", ""))
		if edge_id == "":
			result.append("arête sans identifiant (%s → %s)." % [from_id, to_id])
		elif seen_edge_ids.has(edge_id):
			result.append("identifiant d'arête dupliqué '%s'." % edge_id)
		seen_edge_ids[edge_id] = true
		if from_id == "" or to_id == "":
			result.append("arête incomplète '%s'." % edge_id)
			continue
		if from_id == to_id:
			result.append("boucle immédiate sur '%s'." % from_id)
		if not seen_nodes.has(from_id):
			result.append("arête '%s' vers un nœud d'origine absent '%s'." % [edge_id, from_id])
		if not seen_nodes.has(to_id):
			result.append("arête '%s' vers un nœud absent '%s'." % [edge_id, to_id])
		var pair := "%s→%s" % [from_id, to_id]
		if seen_pairs.has(pair):
			result.append("arête dupliquée '%s'." % pair)
		seen_pairs[pair] = true
		for forbidden in FORBIDDEN_STRUCTURE_KEYS:
			if raw.has(forbidden):
				result.append("champ de progression interdit '%s' sur l'arête '%s'." % [
					forbidden, edge_id])
		var raw_controls: Variant = raw.get("controls", [])
		if not raw_controls is Array:
			result.append("points de contrôle invalides sur l'arête '%s'." % edge_id)
			continue
		for point in raw_controls:
			if not point is Dictionary or not _is_number(point.get("x")) \
					or not _is_number(point.get("y")):
				result.append("point de contrôle invalide sur l'arête '%s'." % edge_id)
				continue
			var control := Vector2(float(point["x"]), float(point["y"]))
			if control.x < 0.0 or control.y < 0.0 \
					or control.x > map_size.x or control.y > map_size.y:
				result.append("point de contrôle hors carte sur l'arête '%s'." % edge_id)

	var graph: CampaignGraph = GraphModel.build(definition)
	if graph.node_count() != seen_nodes.size():
		result.append("le graphe ne contient pas exactement les nœuds déclarés.")
	if graph.start_node_id == "" or not graph.has_node(graph.start_node_id):
		result.append("nœud de départ absent ou inconnu.")
	if graph.final_node_id == "" or not graph.has_node(graph.final_node_id):
		result.append("objectif final absent ou inconnu.")
	if not graph.has_node(graph.start_node_id):
		return result

	var start: CampaignNode = graph.start_node()
	if start != null and start.type != NodeModel.TYPE_TUTORIAL:
		result.append("le nœud de départ doit être un tutoriel avec Pr.Stone.")
	if not graph.predecessors(graph.start_node_id).is_empty():
		result.append("le nœud de départ ne doit avoir aucun prédécesseur.")

	var reachable := graph.reachable_from(graph.start_node_id)
	for node_id in graph.node_ids():
		if not reachable.has(node_id):
			result.append("nœud inaccessible depuis le départ : '%s'." % node_id)
	if graph.has_cycle():
		result.append("cycle détecté : la campagne doit être un graphe orienté sans boucle.")

	if graph.has_node(graph.final_node_id):
		var final_node: CampaignNode = graph.final_node()
		if final_node.type != NodeModel.TYPE_BOSS:
			result.append("l'objectif final '%s' doit être un boss." % graph.final_node_id)
		if not graph.is_dead_end(graph.final_node_id):
			result.append("le boss final '%s' ne doit pas avoir de sortie." % graph.final_node_id)
		if not reachable.has(graph.final_node_id):
			result.append("le boss final n'est pas atteignable depuis le départ.")

	var boss_count := 0
	for node in graph.nodes():
		if node.is_boss():
			boss_count += 1
		var has_exit := not graph.is_dead_end(node.id)
		# Le boss final est l'objectif, pas une impasse de branche : il n'a pas
		# besoin du marqueur `dead_end`, réservé aux culs-de-sac intentionnels.
		if not has_exit and not node.dead_end and node.id != graph.final_node_id:
			result.append("impasse non déclarée intentionnelle sur '%s'." % node.id)
		if has_exit and node.dead_end:
			result.append("'%s' est déclarée impasse mais possède une sortie." % node.id)
		if node.is_mini_boss():
			_mini_boss_problems(graph, node, result)
	if boss_count != 1:
		result.append("exactement un boss final est attendu (trouvé %d)." % boss_count)
	return result


static func _mini_boss_problems(graph: CampaignGraph, node: CampaignNode,
		result: Array[String]) -> void:
	if node.id == graph.start_node_id:
		result.append("un mini-boss ne peut pas être le nœud de départ.")
	if node.series_format() != SeriesRulesModel.SERIES_FT2:
		result.append("mini-boss '%s' : format FT2 requis." % node.id)
	if node.is_optional_mini_boss():
		if not graph.is_dead_end(node.id):
			result.append("mini-boss facultatif '%s' : une impasse sans sortie est requise." % node.id)
		if not node.dead_end:
			result.append("mini-boss facultatif '%s' : l'impasse doit être déclarée." % node.id)
		return
	if not node.is_mandatory_mini_boss():
		return
	if graph.is_dead_end(node.id):
		result.append("mini-boss obligatoire '%s' : il doit permettre d'atteindre la suite." % node.id)
	var without := graph.reachable_from(graph.start_node_id, node.id)
	if without.has(graph.final_node_id):
		result.append("mini-boss obligatoire '%s' contournable : le boss final reste accessible." % node.id)


static func _encounter_problems(node: CampaignNode, result: Array[String]) -> void:
	var encounter := node.encounter
	if encounter.is_empty():
		result.append("configuration de combat absente sur '%s'." % node.id)
		return
	var mode := node.game_mode()
	var god_policy := node.opponent_god_policy()
	var deck_policy := node.opponent_deck_policy()
	var tier := node.max_power_tier()
	if not GameModeRulesModel.MODES.has(mode):
		result.append("mode inconnu '%s' sur '%s'." % [mode, node.id])
	if not SeriesRulesModel.FORMATS.has(node.series_format()):
		result.append("format de série inconnu sur '%s'." % node.id)
	if tier < CardPowerTierRulesModel.MIN_TIER or tier > CardPowerTierRulesModel.MAX_TIER:
		result.append("palier '%d' hors bornes sur '%s'." % [tier, node.id])
	if not NodeModel.GOD_POLICIES.has(god_policy):
		result.append("opponent_god_policy inconnue sur '%s'." % node.id)
	if not NodeModel.DECK_POLICIES.has(deck_policy):
		result.append("opponent_deck_policy inconnue sur '%s'." % node.id)
	if not NodeModel.SEED_POLICIES.has(node.seed_policy()):
		result.append("seed_policy inconnue sur '%s'." % node.id)
	var raw_board_size := int(encounter.get("board_size", GameState.DEFAULT_BOARD_SIZE))
	if raw_board_size < GameState.MIN_BOARD_SIZE or raw_board_size > GameState.MAX_BOARD_SIZE:
		result.append("taille de plateau hors bornes sur '%s'." % node.id)
	for field in ["player_hand_size", "opponent_hand_size"]:
		var hand_size := int(encounter.get(field, DeckRulesModel.DECK_SIZE))
		if hand_size < 1 or hand_size > DeckRulesModel.DECK_SIZE:
			result.append("%s hors bornes sur '%s'." % [field, node.id])
	var blocked_seen := {}
	for raw_cell in node.fixed_blocked_cells():
		if not raw_cell is Array or raw_cell.size() != 2:
			result.append("case bloquée invalide sur '%s'." % node.id)
			continue
		var row := int(raw_cell[0])
		var col := int(raw_cell[1])
		var key := "%d:%d" % [row, col]
		if row < 0 or col < 0 or row >= raw_board_size or col >= raw_board_size \
				or blocked_seen.has(key):
			result.append("case bloquée hors plateau ou dupliquée sur '%s'." % node.id)
		blocked_seen[key] = true
	if node.allows_incomplete_player_deck() and node.id != "tuto_01":
		result.append("deck incomplet autorisé hors du premier tutoriel sur '%s'." % node.id)
	_reward_problems(node, result)

	var generator_god_id := node.generator_god_id()
	var generator_min := node.generator_min_god_cards()
	var mirror_deck := node.mirror_fixed_deck()
	if generator_min < 0 or generator_min > DeckRulesModel.DECK_SIZE:
		result.append("minimum de cartes du dieu hors bornes sur '%s'." % node.id)
	if generator_god_id != "":
		if not [GameModeRulesModel.MODE_RANDOM, GameModeRulesModel.MODE_MIRROR].has(mode):
			result.append("générateur contraint hors Aléatoire/Miroir sur '%s'." % node.id)
		elif StoneLoader.get_god(generator_god_id).is_empty():
			result.append("dieu de génération inconnu '%s' sur '%s'." % [
				generator_god_id, node.id])
	if generator_min > 0 and generator_god_id == "":
		result.append("minimum de cartes du dieu sans dieu imposé sur '%s'." % node.id)
	if not mirror_deck.is_empty():
		if mode != GameModeRulesModel.MODE_MIRROR:
			result.append("deck miroir fixe hors du mode Miroir sur '%s'." % node.id)
		if generator_god_id == "":
			result.append("deck miroir fixe sans dieu imposé sur '%s'." % node.id)

	for problem in AIProfileModel.problems(node.ai_profile()):
		result.append("IA de '%s' : %s." % [node.id, problem])

	match mode:
		GameModeRulesModel.MODE_CLASSIC:
			if not [NodeModel.GOD_FIXED, NodeModel.GOD_PROFILE].has(god_policy):
				result.append("Classique '%s' : dieu fixe ou profil requis." % node.id)
			if not [NodeModel.DECK_FIXED, NodeModel.DECK_GENERATED,
					NodeModel.DECK_MIRRORED].has(deck_policy):
				result.append("Classique '%s' : deck fixe, généré ou miroir requis." % node.id)
		GameModeRulesModel.MODE_RANDOM:
			if god_policy != NodeModel.GOD_GENERATED or deck_policy != NodeModel.DECK_GENERATED:
				result.append("Aléatoire '%s' : dieu et deck générés requis." % node.id)
		GameModeRulesModel.MODE_MIRROR:
			if god_policy != NodeModel.GOD_MIRRORED or deck_policy != NodeModel.DECK_MIRRORED:
				result.append("Miroir '%s' : dieu et deck miroirs requis." % node.id)
		GameModeRulesModel.MODE_DRAFT:
			if not [NodeModel.GOD_FIXED, NodeModel.GOD_PROFILE].has(god_policy):
				result.append("Sélection '%s' : dieu fixe ou profil requis." % node.id)
			if deck_policy != NodeModel.DECK_DRAFT:
				result.append("Sélection '%s' : deck draft requis." % node.id)
			if tier < GameModeRulesModel.minimum_power_tier(mode):
				result.append("Sélection '%s' : palier minimal %d requis." % [
					node.id, GameModeRulesModel.minimum_power_tier(mode)])

	if god_policy == NodeModel.GOD_GENERATED and deck_policy != NodeModel.DECK_GENERATED:
		result.append("dieu généré sans deck généré sur '%s'." % node.id)
	if deck_policy == NodeModel.DECK_MIRRORED \
			and not [NodeModel.GOD_MIRRORED, NodeModel.GOD_PROFILE].has(god_policy):
		result.append("deck miroir sans dieu miroir ou profil sur '%s'." % node.id)
	if deck_policy == NodeModel.DECK_DRAFT and mode != GameModeRulesModel.MODE_DRAFT:
		result.append("deck draft hors du mode Sélection sur '%s'." % node.id)
	if deck_policy == NodeModel.DECK_FIXED and god_policy != NodeModel.GOD_FIXED:
		result.append("deck fixe avec dieu non fixe sur '%s'." % node.id)
	if god_policy == NodeModel.GOD_PROFILE and node.fixed_god_id() != "":
		result.append("fixed_god_id interdit avec la politique profil sur '%s'." % node.id)

	var god_id := node.fixed_god_id()
	if god_policy == NodeModel.GOD_FIXED:
		if god_id == "":
			if deck_policy != NodeModel.DECK_FIXED:
				result.append("dieu vide sur '%s' : un deck fixe neutre est requis." % node.id)
		elif StoneLoader.get_god(god_id).is_empty():
			result.append("dieu inconnu '%s' sur '%s'." % [god_id, node.id])

	if deck_policy == NodeModel.DECK_FIXED:
		_fixed_deck_problems(node, result)
	if not mirror_deck.is_empty():
		_mirror_fixed_deck_problems(node, result)

	if node.is_tutorial():
		if god_policy != NodeModel.GOD_FIXED or god_id != "":
			result.append("tutoriel '%s' : Pr.Stone sans dieu requis." % node.id)
		if mode != GameModeRulesModel.MODE_CLASSIC:
			result.append("tutoriel '%s' : mode Classique requis." % node.id)
		if deck_policy != NodeModel.DECK_FIXED:
			result.append("tutoriel '%s' : deck fixe requis." % node.id)
		if tier > 2:
			result.append("tutoriel '%s' : palier 2 maximum." % node.id)
		if float(node.ai_profile().get("precision", 1.0)) != 0.0 \
				or bool(node.ai_profile().get("anticipation", true)):
			result.append("tutoriel '%s' : précision 0 et sans anticipation requis." % node.id)


static func _reward_problems(node: CampaignNode, result: Array[String]) -> void:
	var reward := node.reward_definition()
	if reward.is_empty():
		# Compatibilité des fixtures/outils qui construisent encore des graphes
		# sans économie. Le contenu livré déclare toutes ses récompenses.
		return
	var minimum := int(reward.get("souls_min", -1))
	var maximum := int(reward.get("souls_max", -1))
	if minimum < 0 or maximum < minimum:
		result.append("fourchette d'âmes invalide sur '%s'." % node.id)
	var cards: Variant = reward.get("card_rewards", [])
	if not cards is Array:
		result.append("récompenses de cartes invalides sur '%s'." % node.id)
		return
	if not cards.is_empty() and not (node.is_mini_boss() or node.is_boss() or node.id == "tuto_01"):
		result.append("cartes offertes hors tutoriel initial/mini-boss/boss sur '%s'." % node.id)
	for raw_stone_id in cards:
		if not StoneLoader.has_stone(str(raw_stone_id)):
			result.append("carte de récompense inconnue '%s' sur '%s'." % [raw_stone_id, node.id])

static func _fixed_deck_problems(node: CampaignNode, result: Array[String]) -> void:
	_deck_problems(node, node.fixed_deck(), node.fixed_god_id(), MIN_GOD_CARDS,
		"deck fixe", result)


static func _mirror_fixed_deck_problems(node: CampaignNode, result: Array[String]) -> void:
	_deck_problems(node, node.mirror_fixed_deck(), node.generator_god_id(),
		maxi(MIN_GOD_CARDS, node.generator_min_god_cards()), "deck miroir", result)


static func _deck_problems(node: CampaignNode, deck: Array, god_id: String,
		min_god_cards: int, label: String, result: Array[String]) -> void:
	if deck.size() != DeckRulesModel.DECK_SIZE:
		result.append("%s de '%s' : %d cartes au lieu de %d." % [
			label, node.id, deck.size(), DeckRulesModel.DECK_SIZE])
	var lineages := {}
	var same_god := 0
	for raw_id in deck:
		var stone_id := str(raw_id)
		if not StoneLoader.has_stone(stone_id):
			result.append("carte inconnue '%s' sur '%s'." % [stone_id, node.id])
			continue
		var lineage := StoneLoader.stone_lineage(stone_id)
		if lineages.has(lineage):
			result.append("lignée dupliquée '%s' sur '%s'." % [lineage, node.id])
		lineages[lineage] = true
		if god_id == "":
			if StoneLoader.stone_affinity(stone_id) != "neutral":
				result.append("carte non neutre '%s' sur le bot sans dieu '%s'." % [
					stone_id, node.id])
		elif not StoneLoader.is_stone_available_to_god(stone_id, god_id):
			result.append("carte '%s' inaccessible au dieu '%s' sur '%s'." % [
				stone_id, god_id, node.id])
		if god_id != "" and StoneLoader.stone_affinity(stone_id) == god_id:
			same_god += 1
		var card_tier := CardPowerTierRulesModel.effective_tier(StoneLoader.get_stone(stone_id))
		if card_tier > node.max_power_tier():
			result.append("carte '%s' de palier %d au-dessus du palier %d sur '%s'." % [
				stone_id, card_tier, node.max_power_tier(), node.id])
	if god_id != "" and same_god < min_god_cards:
		result.append("%s de '%s' : au moins %d cartes du dieu '%s' requises (trouvé %d)." % [
			label, node.id, min_god_cards, god_id, same_god])
	if deck.size() == DeckRulesModel.DECK_SIZE:
		var validation := DeckRulesModel.validate_deck(deck, true, god_id)
		if not bool(validation.get("valid", false)):
			result.append("%s invalide sur '%s' : %s." % [
				label, node.id, str(validation.get("reason", ""))])


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
