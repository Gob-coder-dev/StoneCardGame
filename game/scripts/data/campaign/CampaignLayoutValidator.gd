## CampaignLayoutValidator.gd
## Contrôle géométrique coûteux des courbes de la carte. Réservé aux outils et
## aux tests de contenu : le runtime consomme un layout déjà validé.
class_name CampaignLayoutValidator
extends RefCounted

const MIN_EDGE_NODE_CLEARANCE: float = 76.0


static func problems(graph: CampaignGraph) -> Array[String]:
	var result: Array[String] = []
	if graph == null:
		return result
	for edge in graph.edges():
		edge_problems(graph, edge, result)
	return result


static func edge_problems(graph: CampaignGraph, edge,
		result: Array[String]) -> void:
	if not graph.has_node(edge.from_id) or not graph.has_node(edge.to_id):
		return
	var from_node: CampaignNode = graph.node(edge.from_id)
	var to_node: CampaignNode = graph.node(edge.to_id)
	if from_node == null or to_node == null:
		return
	var from := from_node.position
	var to := to_node.position
	var control_one := from + Vector2(0.0, (to.y - from.y) * 0.45)
	var control_two := to - Vector2(0.0, (to.y - from.y) * 0.45)
	if edge.controls.size() >= 2:
		control_one = edge.controls[0]
		control_two = edge.controls[1]
	elif edge.controls.size() == 1:
		control_one = edge.controls[0]
		control_two = control_one + (to - from) * 0.25
	var nearest := INF
	var nearest_id := ""
	for node in graph.nodes():
		if node.id == edge.from_id or node.id == edge.to_id:
			continue
		for index in range(21):
			var weight := float(index) / 20.0
			var point := from.cubic_interpolate(to, control_one, control_two, weight)
			var distance := point.distance_to(node.position)
			if distance < nearest:
				nearest = distance
				nearest_id = node.id
	if nearest_id != "" and nearest < MIN_EDGE_NODE_CLEARANCE:
		result.append("chemin '%s' trop proche du nœud non relié '%s' (%.0f unités)." % [
			edge.id, nearest_id, nearest])
