## Index spatial immuable des chemins de campagne. Les courbes et leurs bornes
## sont calculées une fois ; la vue peut ensuite demander uniquement les
## chemins proches du viewport sans reparcourir ni retesseller tout le graphe.
class_name CampaignMapRenderIndex
extends RefCounted

const BAND_HEIGHT := 720.0
const CURVE_SAMPLES := 21

var _graph: CampaignGraph = null
var _entries: Dictionary = {}
var _bands: Dictionary = {}
var _order: Dictionary = {}


func _init(graph: CampaignGraph = null) -> void:
	_graph = graph
	if _graph == null:
		return
	var edge_index := 0
	for edge_variant in _graph.edges():
		var edge := edge_variant as CampaignEdge
		if edge == null or not _graph.has_node(edge.from_id) \
				or not _graph.has_node(edge.to_id):
			continue
		var points := _build_points(edge)
		var bounds := _bounds(points)
		_entries[edge.id] = {"edge": edge, "points": points, "bounds": bounds}
		_order[edge.id] = edge_index
		edge_index += 1
		var first_band := floori(bounds.position.y / BAND_HEIGHT)
		var last_band := floori(bounds.end.y / BAND_HEIGHT)
		for band in range(first_band, last_band + 1):
			if not _bands.has(band):
				_bands[band] = []
			(_bands[band] as Array).append(edge.id)


func edges_in(rect: Rect2) -> Array:
	var result: Array = []
	if _graph == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return result
	var candidates := {}
	var first_band := floori(rect.position.y / BAND_HEIGHT)
	var last_band := floori(rect.end.y / BAND_HEIGHT)
	for band in range(first_band, last_band + 1):
		for edge_id in _bands.get(band, []):
			candidates[str(edge_id)] = true
	var ids: Array = candidates.keys()
	ids.sort_custom(func(first: Variant, second: Variant) -> bool:
		return int(_order.get(str(first), 0)) < int(_order.get(str(second), 0)))
	for edge_id in ids:
		var entry: Dictionary = _entries.get(str(edge_id), {})
		var bounds: Rect2 = entry.get("bounds", Rect2())
		if not entry.is_empty() and bounds.intersects(rect):
			result.append(entry["edge"])
	return result


func points_for(edge_id: String) -> PackedVector2Array:
	var entry: Dictionary = _entries.get(edge_id, {})
	var points: PackedVector2Array = entry.get("points", PackedVector2Array())
	return points


func bounds_for(edge_id: String) -> Rect2:
	var entry: Dictionary = _entries.get(edge_id, {})
	var bounds: Rect2 = entry.get("bounds", Rect2())
	return bounds


func _build_points(edge: CampaignEdge) -> PackedVector2Array:
	var from_node := _graph.node(edge.from_id)
	var to_node := _graph.node(edge.to_id)
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
	var points := PackedVector2Array()
	for index in range(CURVE_SAMPLES):
		var weight := float(index) / float(CURVE_SAMPLES - 1)
		points.append(from.cubic_interpolate(to, control_one, control_two, weight))
	return points


func _bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	# Une courbe parfaitement horizontale ou verticale doit tout de même pouvoir
	# croiser un rectangle lors de la requête spatiale.
	return Rect2(minimum, (maximum - minimum).max(Vector2.ONE))
