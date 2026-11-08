## CampaignMapView.gd
## Rendu de la carte unifiée : un espace logique de 1080 unités de large, un
## facteur d'échelle unique pour le fond, les arêtes et les nœuds, et des
## courbes dessinées derrière les ronds. La vue reçoit des états déjà calculés :
## elle ne lit ni PlayerData ni la sauvegarde.
class_name CampaignMapView
extends Control

signal node_activated(node_id: String)

const NodeScene := preload("res://scenes/campaign/CampaignNode.tscn")
const UnlockRulesModel := preload("res://scripts/domain/campaign/CampaignUnlockRules.gd")

var _graph: CampaignGraph = null
var _states: Dictionary = {}
var _views: Dictionary = {}
var _selected_id: String = ""
var _scale: float = 1.0
## Les courbes ne changent qu'au redimensionnement : on ne recalcule pas 148
## chemins à chaque rafraîchissement d'état.
var _edge_points_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)


func setup(graph: CampaignGraph, states: Dictionary, selected_id: String = "") -> void:
	_graph = graph
	_states = states
	_selected_id = selected_id
	_rebuild()
	relayout.call_deferred()


func refresh_states(states: Dictionary, selected_id: String = "") -> void:
	_states = states
	if selected_id != "":
		_selected_id = selected_id
	for node_id in _views:
		_configure_view(str(node_id))
	queue_redraw()


func set_selected(selected_id: String) -> void:
	_selected_id = selected_id
	for node_id in _views:
		_configure_view(str(node_id))


func node_control(node_id: String) -> Control:
	return _views.get(node_id, null) as Control


func node_center(node_id: String) -> Vector2:
	if _graph == null:
		return Vector2.ZERO
	var node := _graph.node(node_id)
	if node == null:
		return Vector2.ZERO
	return node.position * _scale


func scale_factor() -> float:
	return _scale


func content_height() -> float:
	if _graph == null:
		return 0.0
	return (_graph.map_size.y + UITheme.CAMPAIGN_BOTTOM_PAD) * _scale


## Points de départ et d'arrivée réellement dessinés, pour vérifier que les
## chemins restent alignés avec les nœuds sur téléphone et tablette.
func edge_endpoints() -> Array:
	var result: Array = []
	if _graph == null:
		return result
	for edge in _graph.edges():
		if not _graph.has_node(edge.from_id) or not _graph.has_node(edge.to_id):
			continue
		result.append({
			"id": edge.id,
			"from_id": edge.from_id,
			"to_id": edge.to_id,
			"from": node_center(edge.from_id),
			"to": node_center(edge.to_id),
		})
	return result


func relayout() -> void:
	if _graph == null or size.x <= 0.0:
		return
	_edge_points_cache.clear()
	_scale = size.x / UITheme.CAMPAIGN_MAP_WIDTH
	custom_minimum_size = Vector2(0.0, content_height())
	var diameter := float(UITheme.CAMPAIGN_NODE_SIZE) * _scale
	for node_id in _views:
		var view: Control = _views[node_id]
		view.size = Vector2(diameter, diameter)
		view.position = node_center(str(node_id)) - Vector2(diameter, diameter) * 0.5
		view.pivot_offset = view.size * 0.5
	queue_redraw()


func _rebuild() -> void:
	_edge_points_cache.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_views.clear()
	if _graph == null:
		queue_redraw()
		return
	for node in _graph.nodes():
		var view: CampaignNodeView = NodeScene.instantiate() as CampaignNodeView
		# La scène garde une taille d'édition, mais la carte impose son échelle
		# aux nœuds : une taille minimale fixe casserait le rendu téléphone.
		view.custom_minimum_size = Vector2.ZERO
		view.name = "Node_%s" % node.id
		add_child(view)
		view.pressed.connect(_on_view_pressed.bind(node.id))
		_views[node.id] = view
		_configure_view(node.id)
	queue_redraw()


func _configure_view(node_id: String) -> void:
	var view: CampaignNodeView = _views.get(node_id, null) as CampaignNodeView
	var node := _graph.node(node_id) if _graph != null else null
	if view == null or node == null:
		return
	var state := int(_states.get(node_id, UnlockRulesModel.State.LOCKED))
	view.configure(node, state, _accent_for(node), node_id == _selected_id)


func _accent_for(node: CampaignNode) -> Color:
	if node.accent != "":
		return Color(node.accent)
	if node.fixed_god_id() != "":
		return Color(str(StoneLoader.get_god(node.fixed_god_id()).get("color",
			UITheme.COL_NEON_PINK.to_html())))
	return UITheme.COL_NEON_PINK


func _on_view_pressed(node_id: String) -> void:
	node_activated.emit(node_id)


func _draw() -> void:
	if _graph == null:
		return
	_draw_edges()
	_draw_map_marks()


func _draw_edges() -> void:
	for edge in _graph.edges():
		if not _graph.has_node(edge.from_id) or not _graph.has_node(edge.to_id):
			continue
		var points := _edge_points(edge)
		var from_state := int(_states.get(edge.from_id, UnlockRulesModel.State.LOCKED))
		var to_state := int(_states.get(edge.to_id, UnlockRulesModel.State.LOCKED))
		var active := from_state == UnlockRulesModel.State.COMPLETED
		var visible := to_state != UnlockRulesModel.State.LOCKED
		if active:
			var accent := _edge_color(_graph.node(edge.to_id))
			var glow := accent
			glow.a = 0.10
			draw_polyline(points, glow, 18.0, true)
			glow.a = 0.24
			draw_polyline(points, glow, 8.0, true)
			accent.a = 0.88
			draw_polyline(points, accent, 4.0, true)
		elif visible:
			var trace := UITheme.COL_CAMPAIGN_EDGE
			trace.a = 0.62
			draw_polyline(points, trace, 3.0, true)
		else:
			var trace := UITheme.COL_PATH_TRACE
			trace.a = 0.42
			draw_polyline(points, trace, 3.0, true)
			for step in range(1, points.size() - 1, 2):
				draw_circle(points[step], 2.4, trace)


func _edge_color(node: CampaignNode) -> Color:
	if node != null and node.fixed_god_id() != "":
		return Color(str(StoneLoader.get_god(node.fixed_god_id()).get("color",
			UITheme.COL_CAMPAIGN_EDGE_LIT.to_html())))
	return UITheme.COL_CAMPAIGN_EDGE_LIT


## Quelques repères de chapitre, dessinés dans le même repère que les nœuds.
func _draw_map_marks() -> void:
	var seen := {}
	var font := get_theme_default_font()
	for node in _graph.nodes():
		var chapter: String = node.chapter
		if chapter == "" or seen.has(chapter):
			continue
		seen[chapter] = true
		var y: float = node.position.y * _scale - float(UITheme.CAMPAIGN_NODE_SIZE) * _scale
		var ink := UITheme.COL_TEXT_DIM
		ink.a = 0.14
		draw_line(Vector2(60.0 * _scale, y), Vector2(1020.0 * _scale, y), ink, 2.0, true)
		if font != null:
			var label_ink := UITheme.COL_TEXT_DIM
			label_ink.a = 0.42
			draw_string(font, Vector2(64.0 * _scale, y - 8.0 * _scale),
				chapter.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 520.0 * _scale,
				maxi(12, int(16.0 * _scale)), label_ink)


func _edge_points(edge: CampaignEdge) -> PackedVector2Array:
	if _edge_points_cache.has(edge.id):
		return _edge_points_cache[edge.id]
	var from := node_center(edge.from_id)
	var to := node_center(edge.to_id)
	var control_one := from + Vector2(0.0, (to.y - from.y) * 0.45)
	var control_two := to - Vector2(0.0, (to.y - from.y) * 0.45)
	if edge.controls.size() >= 2:
		control_one = edge.controls[0] * _scale
		control_two = edge.controls[1] * _scale
	elif edge.controls.size() == 1:
		control_one = edge.controls[0] * _scale
		control_two = control_one + (to - from) * 0.25
	var points := PackedVector2Array()
	for index in range(21):
		var weight := float(index) / 20.0
		points.append(from.cubic_interpolate(to, control_one, control_two, weight))
	_edge_points_cache[edge.id] = points
	return points


func _on_resized() -> void:
	relayout()
