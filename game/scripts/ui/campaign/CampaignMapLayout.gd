## CampaignMapLayout.gd
## Géométrie pure de la carte : elle ne crée aucun Control et ne lit aucune
## progression. Les positions restent dans le repère logique du contenu (1080
## unités de large) puis sont projetées avec un facteur d'échelle unique.
class_name CampaignMapLayout
extends RefCounted


static func scale_for_width(view_width: float) -> float:
	return maxf(0.001, view_width / UITheme.CAMPAIGN_MAP_WIDTH)


static func node_center(graph: CampaignGraph, node_id: String, scale: float) -> Vector2:
	if graph == null:
		return Vector2.ZERO
	var node := graph.node(node_id)
	return node.position * scale if node != null else Vector2.ZERO


static func node_rect(graph: CampaignGraph, node_id: String, scale: float) -> Rect2:
	var diameter := float(UITheme.CAMPAIGN_NODE_SIZE) * scale
	return Rect2(node_center(graph, node_id, scale) - Vector2(diameter, diameter) * 0.5,
		Vector2(diameter, diameter))


static func content_height(graph: CampaignGraph, scale: float) -> float:
	if graph == null:
		return 0.0
	return (graph.map_size.y + UITheme.CAMPAIGN_BOTTOM_PAD) * scale


## Convertit le défilement en pixels et la hauteur visible en rectangle logique.
static func visible_rect(scroll_vertical: float, viewport_height: float,
		scale: float) -> Rect2:
	var safe_scale := maxf(0.001, scale)
	return Rect2(0.0, scroll_vertical / safe_scale,
		UITheme.CAMPAIGN_MAP_WIDTH, viewport_height / safe_scale)


## Rectangle logique autour d'une ancre, utilisé avant que le ScrollContainer
## n'ait une taille définitive. L'ancre est placée à 45 % de la hauteur.
static func focus_rect(graph: CampaignGraph, node_id: String,
		viewport_logical_height: float, anchor_ratio: float = 0.45) -> Rect2:
	var height := maxf(1.0, viewport_logical_height)
	var node := graph.node(node_id) if graph != null else null
	var anchor_y := node.position.y if node != null else 0.0
	var map_bottom := graph.map_size.y + UITheme.CAMPAIGN_BOTTOM_PAD \
		if graph != null else height
	var top := clampf(anchor_y - height * anchor_ratio, 0.0,
		maxf(0.0, map_bottom - height))
	return Rect2(0.0, top, UITheme.CAMPAIGN_MAP_WIDTH, height)


## Position de défilement qui replace une ancre avec son offset logique.
static func scroll_for_anchor(graph: CampaignGraph, node_id: String, offset_y: float,
		scale: float) -> float:
	var node := graph.node(node_id) if graph != null else null
	if node == null:
		return 0.0
	return maxf(0.0, (node.position.y + offset_y) * scale)


static func nearest_node_id(graph: CampaignGraph, logical_point: Vector2) -> String:
	if graph == null:
		return ""
	var nearest := ""
	var nearest_distance := INF
	for node in graph.nodes():
		var distance: float = node.position.distance_squared_to(logical_point)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = node.id
	return nearest