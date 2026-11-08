## CampaignMapPositionState.gd
## Position de navigation de la carte, indépendante de la progression. L'ancre
## est un nœud existant ; l'offset est logique (pas une coordonnée d'écran).
class_name CampaignMapPositionState
extends RefCounted

const VERSION: int = 1

var version: int = VERSION
var anchor_node_id: String = ""
var offset_y: float = 0.0
var scroll_vertical: float = 0.0


static func make(anchor_id: String, offset: float = 0.0,
		scroll: float = 0.0) -> CampaignMapPositionState:
	var state := CampaignMapPositionState.new()
	state.anchor_node_id = anchor_id
	state.offset_y = _finite(offset, 0.0)
	state.scroll_vertical = maxf(0.0, _finite(scroll, 0.0))
	return state


static func from_dict(source: Variant) -> CampaignMapPositionState:
	if not source is Dictionary:
		return CampaignMapPositionState.new()
	var state := CampaignMapPositionState.new()
	var data: Dictionary = source
	state.version = maxi(1, int(data.get("version", VERSION)))
	state.anchor_node_id = str(data.get("anchor_node_id", ""))
	state.offset_y = _finite(float(data.get("offset_y", 0.0)), 0.0)
	state.scroll_vertical = maxf(0.0, _finite(float(data.get("scroll_vertical", 0.0)), 0.0))
	return state


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"anchor_node_id": anchor_node_id,
		"offset_y": offset_y,
		"scroll_vertical": scroll_vertical,
	}


func duplicate_state() -> CampaignMapPositionState:
	return CampaignMapPositionState.from_dict(to_dict())


func is_empty() -> bool:
	return anchor_node_id == ""


## Si l'ancre a disparu après une mise à jour, on retombe sur un nœud connu.
## Le scroll en pixels n'est jamais utilisé comme ancre principale.
func resolved(graph: CampaignGraph, fallback_id: String = "") -> CampaignMapPositionState:
	if graph == null:
		return CampaignMapPositionState.new()
	if graph.has_node(anchor_node_id):
		return duplicate_state()
	var anchor := fallback_id
	if not graph.has_node(anchor):
		anchor = graph.start_node_id
	if not graph.has_node(anchor):
		return CampaignMapPositionState.new()
	return CampaignMapPositionState.make(anchor, 0.0, scroll_vertical)


static func _finite(value: float, fallback: float) -> float:
	return value if is_finite(value) else fallback