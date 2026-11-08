## CampaignUnlockRules.gd
## Règle pure de déblocage : un nœud est accessible si c'est le départ ou si AU
## MOINS UN prédécesseur est terminé. Un nœud déjà terminé reste rejouable.
## Aucune notion de route choisie, de branche principale ou de difficulté.
class_name CampaignUnlockRules
extends RefCounted

enum State { LOCKED, AVAILABLE, COMPLETED }


static func completed_set(completed: Variant) -> Dictionary:
	var result := {}
	if completed is Dictionary:
		for key in completed:
			if bool(completed[key]):
				result[str(key)] = true
	elif completed is Array:
		for key in completed:
			result[str(key)] = true
	return result


## États de tous les nœuds du graphe, indexés par identifiant stable.
static func states(graph: CampaignGraph, completed: Variant) -> Dictionary:
	var done := completed_set(completed)
	var result := {}
	for node_id in graph.node_ids():
		result[node_id] = state_for(graph, node_id, done)
	return result


static func state_for(graph: CampaignGraph, node_id: String, completed: Variant) -> int:
	var done := completed_set(completed)
	if done.has(node_id):
		return State.COMPLETED
	if node_id == graph.start_node_id:
		return State.AVAILABLE
	for predecessor_id in graph.predecessors(node_id):
		if done.has(predecessor_id):
			return State.AVAILABLE
	return State.LOCKED


static func is_available(graph: CampaignGraph, node_id: String, completed: Variant) -> bool:
	if not graph.has_node(node_id):
		return false
	var state := state_for(graph, node_id, completed)
	return state == State.AVAILABLE or state == State.COMPLETED


static func is_completed(graph: CampaignGraph, node_id: String, completed: Variant) -> bool:
	if not graph.has_node(node_id):
		return false
	return state_for(graph, node_id, completed) == State.COMPLETED


## Nœuds accessibles dans l'ordre du fichier de contenu.
static func available_node_ids(graph: CampaignGraph, completed: Variant) -> Array[String]:
	var result: Array[String] = []
	var states_by_id := states(graph, completed)
	for node_id in graph.node_ids():
		var state := int(states_by_id[node_id])
		if state == State.AVAILABLE or state == State.COMPLETED:
			result.append(node_id)
	return result


## Premier nœud encore à terminer, sinon le nœud final. Sert uniquement au
## centrage initial de la carte, jamais à verrouiller une branche.
static func focus_node_id(graph: CampaignGraph, completed: Variant,
		last_selected: String = "") -> String:
	if last_selected != "" and graph.has_node(last_selected):
		return last_selected
	var done := completed_set(completed)
	for node_id in graph.node_ids():
		if state_for(graph, node_id, done) == State.AVAILABLE:
			return node_id
	if graph.has_node(graph.final_node_id):
		return graph.final_node_id
	return graph.start_node_id


static func state_label(state: int) -> String:
	match state:
		State.COMPLETED:
			return "Terminé"
		State.AVAILABLE:
			return "Accessible"
	return "Verrouillé"
