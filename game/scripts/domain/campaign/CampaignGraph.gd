## CampaignGraph.gd
## Graphe orienté et immuable de la campagne : indexation, prédécesseurs,
## successeurs et requêtes de structure. Aucune sauvegarde, aucune interface.
class_name CampaignGraph
extends RefCounted

const NodeModel := preload("res://scripts/domain/campaign/CampaignNode.gd")
const EdgeModel := preload("res://scripts/domain/campaign/CampaignEdge.gd")

var campaign_version: int = 0
var campaign_id: String = ""
var title: String = ""
var start_node_id: String = ""
var final_node_id: String = ""
var map_size: Vector2 = Vector2(1080.0, 1920.0)

var _nodes: Dictionary = {}
var _node_order: Array[String] = []
var _edges: Array = []
var _outgoing: Dictionary = {}
var _incoming: Dictionary = {}


## Construit le graphe sans valider le contenu. Le validateur refuse les
## définitions incohérentes ; les lectures restent sûres même sur un graphe
## partiel afin de produire des diagnostics exploitables.
static func build(definition: Dictionary) -> CampaignGraph:
	var graph := CampaignGraph.new()
	graph.campaign_version = int(definition.get("campaign_version", 0))
	graph.campaign_id = str(definition.get("id", ""))
	graph.title = str(definition.get("title", ""))
	graph.start_node_id = str(definition.get("start_node_id", ""))
	graph.final_node_id = str(definition.get("final_node_id", ""))
	var raw_map: Variant = definition.get("map", {})
	if raw_map is Dictionary:
		graph.map_size = Vector2(float(raw_map.get("width", 1080.0)),
			float(raw_map.get("height", 1920.0)))
	var raw_nodes: Variant = definition.get("nodes", [])
	if raw_nodes is Array:
		for raw in raw_nodes:
			if not raw is Dictionary:
				continue
			var node: CampaignNode = NodeModel.from_dict(raw)
			if node.id == "":
				continue
			if not graph._nodes.has(node.id):
				graph._node_order.append(node.id)
			graph._nodes[node.id] = node
			graph._outgoing[node.id] = []
			graph._incoming[node.id] = []
	var raw_edges: Variant = definition.get("edges", [])
	if raw_edges is Array:
		for raw in raw_edges:
			if not raw is Dictionary:
				continue
			var edge: CampaignEdge = EdgeModel.from_dict(raw)
			graph._edges.append(edge)
			if not graph._outgoing.has(edge.from_id):
				graph._outgoing[edge.from_id] = []
			if not graph._incoming.has(edge.to_id):
				graph._incoming[edge.to_id] = []
			if not (graph._outgoing[edge.from_id] as Array).has(edge.to_id):
				(graph._outgoing[edge.from_id] as Array).append(edge.to_id)
			if not (graph._incoming[edge.to_id] as Array).has(edge.from_id):
				(graph._incoming[edge.to_id] as Array).append(edge.from_id)
	return graph


func has_node(node_id: String) -> bool:
	return _nodes.has(node_id)


func node(node_id: String) -> CampaignNode:
	return _nodes.get(node_id, null) as CampaignNode


func nodes() -> Array:
	var result: Array = []
	for node_id in _node_order:
		result.append(_nodes[node_id])
	return result


func node_ids() -> Array[String]:
	return _node_order.duplicate()


func edges() -> Array:
	return _edges.duplicate()


func edge_count() -> int:
	return _edges.size()


func node_count() -> int:
	return _node_order.size()


func start_node() -> CampaignNode:
	return node(start_node_id)


func final_node() -> CampaignNode:
	return node(final_node_id)


func successors(node_id: String) -> Array[String]:
	var result: Array[String] = []
	for value in _outgoing.get(node_id, []):
		result.append(str(value))
	return result


func predecessors(node_id: String) -> Array[String]:
	var result: Array[String] = []
	for value in _incoming.get(node_id, []):
		result.append(str(value))
	return result


func outgoing_edges(node_id: String) -> Array:
	var result: Array = []
	for edge in _edges:
		if edge.from_id == node_id:
			result.append(edge)
	return result


func incoming_edges(node_id: String) -> Array:
	var result: Array = []
	for edge in _edges:
		if edge.to_id == node_id:
			result.append(edge)
	return result


func is_dead_end(node_id: String) -> bool:
	return successors(node_id).is_empty()


## Ensemble des nœuds atteignables depuis `start_id`, en excluant éventuellement
## un nœud. Sert au validateur pour prouver qu'un mini-boss obligatoire ne peut
## pas être contourné.
func reachable_from(start_id: String, excluded_id: String = "") -> Dictionary:
	var seen := {}
	if not has_node(start_id) or start_id == excluded_id:
		return seen
	var stack: Array[String] = [start_id]
	while not stack.is_empty():
		var current: String = stack.pop_back()
		if seen.has(current) or current == excluded_id:
			continue
		seen[current] = true
		for next_id in successors(current):
			if not seen.has(next_id):
				stack.append(next_id)
	return seen


## Un cycle rendrait la progression ambiguë sans apporter de valeur de jeu :
## le contenu doit rester un graphe orienté sans boucle.
func has_cycle() -> bool:
	var visiting := {}
	var done := {}
	for node_id in _node_order:
		if _cycle_dfs(node_id, visiting, done):
			return true
	return false


func _cycle_dfs(node_id: String, visiting: Dictionary, done: Dictionary) -> bool:
	if done.has(node_id):
		return false
	if visiting.has(node_id):
		return true
	visiting[node_id] = true
	for next_id in successors(node_id):
		if _cycle_dfs(next_id, visiting, done):
			return true
	visiting.erase(node_id)
	done[node_id] = true
	return false


## Nœuds accessibles sans aucun prédécesseur terminé, dans l'ordre du fichier.
func entry_node_ids() -> Array[String]:
	var result: Array[String] = []
	for node_id in _node_order:
		if predecessors(node_id).is_empty():
			result.append(node_id)
	return result


func edge_between(from_id: String, to_id: String) -> CampaignEdge:
	for edge in _edges:
		if edge.from_id == from_id and edge.to_id == to_id:
			return edge
	return null
