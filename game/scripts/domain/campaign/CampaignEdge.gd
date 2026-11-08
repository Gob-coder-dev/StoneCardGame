## CampaignEdge.gd
## Arête orientée entre deux nœuds. Aucun état de progression n'y vit : une
## arête est une donnée de contenu, jamais une route choisie.
class_name CampaignEdge
extends RefCounted

var id: String = ""
var from_id: String = ""
var to_id: String = ""
var controls: Array[Vector2] = []
var raw: Dictionary = {}


static func from_dict(source: Dictionary) -> CampaignEdge:
	var edge := CampaignEdge.new()
	edge.raw = source.duplicate(true)
	edge.id = str(source.get("id", ""))
	edge.from_id = str(source.get("from", ""))
	edge.to_id = str(source.get("to", ""))
	var raw_controls: Variant = source.get("controls", [])
	if raw_controls is Array:
		for point in raw_controls:
			if point is Dictionary:
				edge.controls.append(Vector2(float(point.get("x", 0.0)),
					float(point.get("y", 0.0))))
	return edge


func has_visual_controls() -> bool:
	return not controls.is_empty()
