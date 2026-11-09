## CampaignMapView.gd
## Rendu virtualisé de la carte. Les données et les positions logiques restent
## complètes en mémoire, mais seuls les nœuds des secteurs chargés possèdent un
## Control. Les secteurs sont calculés par CampaignMapChunkManager ; cette vue
## ne fait que mettre en scène les nœuds demandés, par petits lots.
class_name CampaignMapView
extends Control

signal node_activated(node_id: String)
signal streaming_changed(pending_count: int)

const NodeScene := preload("res://scenes/campaign/CampaignNode.tscn")
const UnlockRulesModel := preload("res://scripts/domain/campaign/CampaignUnlockRules.gd")
const LayoutModel := preload("res://scripts/ui/campaign/CampaignMapLayout.gd")
const ChunkManagerModel := preload("res://scripts/ui/campaign/CampaignMapChunkManager.gd")
const SectionThemeModel := preload("res://scripts/ui/campaign/CampaignSectionTheme.gd")
const SectionArtModel := preload("res://scripts/ui/campaign/CampaignSectionArt.gd")

## Le premier lot rend la zone immédiatement lisible sans attendre la fin du
## chargement. Les lots suivants laissent respirer le thread principal.
const INITIAL_BATCH_SIZE: int = 8
const FRAME_BATCH_SIZE: int = 6
const DEFAULT_VIEWPORT_HEIGHT: float = 1600.0

var _graph: CampaignGraph = null
var _states: Dictionary = {}
var _views: Dictionary = {}
var _loaded: Dictionary = {}
var _pending: Array[String] = []
var _pending_lookup: Dictionary = {}
var _selected_id: String = ""
var _focus_id: String = ""
var _initial_focus: String = ""
var _scale: float = 1.0
var _chunk_manager = null
var _visible_rect := Rect2()
var _viewport_logical := Vector2(UITheme.CAMPAIGN_MAP_WIDTH, DEFAULT_VIEWPORT_HEIGHT)
## Les courbes ne changent qu'au redimensionnement : on ne recalcule pas toutes
## les arêtes à chaque rafraîchissement d'état.
var _edge_points_cache: Dictionary = {}
var _visible_edges: Array = []
var _visible_chapters: Dictionary = {}
var _sections: Array = []
var _setup_done := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_process(false)
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)


func setup(graph: CampaignGraph, states: Dictionary, selected_id: String = "",
		focus_id: String = "", viewport_height: float = 0.0) -> void:
	_clear_streamed_views()
	_graph = graph
	_sections = SectionThemeModel.build(_graph)
	_states = states
	_selected_id = selected_id
	_focus_id = focus_id
	if _focus_id == "" and _graph != null:
		_focus_id = _graph.start_node_id
	_initial_focus = _focus_id
	_setup_done = true
	_chunk_manager = ChunkManagerModel.new(_graph)
	_scale = LayoutModel.scale_for_width(size.x) if size.x > 0.0 else 1.0
	var viewport := viewport_height if viewport_height > 0.0 else DEFAULT_VIEWPORT_HEIGHT
	_viewport_logical = Vector2(UITheme.CAMPAIGN_MAP_WIDTH,
		maxf(1.0, viewport / maxf(0.001, _scale)))
	_visible_rect = LayoutModel.focus_rect(_graph, _focus_id, _viewport_logical.y)
	custom_minimum_size = Vector2(0.0, content_height())
	_update_streaming(_visible_rect, _viewport_logical)
	# Première image utile : quelques ronds autour du focus, pas toute la carte.
	_create_batch(INITIAL_BATCH_SIZE)
	relayout.call_deferred()


func refresh_states(states: Dictionary, selected_id: String = "") -> void:
	if _graph == null:
		return
	var previous_selected := _selected_id
	var changed: Array[String] = []
	for node_id in _loaded:
		var id := str(node_id)
		if int(_states.get(id, -1)) != int(states.get(id, -1)):
			changed.append(id)
	_states = states
	if selected_id != "":
		_selected_id = selected_id
	for node_id in changed:
		_configure_view(node_id)
	if previous_selected != _selected_id:
		if _loaded.has(previous_selected):
			_configure_view(previous_selected)
		if _loaded.has(_selected_id):
			_configure_view(_selected_id)
	if not changed.is_empty() or previous_selected != _selected_id:
		_rebuild_visible_edges()
		queue_redraw()


func set_selected(selected_id: String) -> void:
	if selected_id == _selected_id:
		return
	var previous := _selected_id
	_selected_id = selected_id
	if _loaded.has(previous):
		_configure_view(previous)
	if _loaded.has(selected_id):
		_configure_view(selected_id)


func node_control(node_id: String) -> Control:
	return _views.get(node_id, null) as Control


func node_center(node_id: String) -> Vector2:
	return LayoutModel.node_center(_graph, node_id, _scale)


func scale_factor() -> float:
	return _scale


func content_height() -> float:
	return LayoutModel.content_height(_graph, _scale)


func loaded_count() -> int:
	return _loaded.size()


func pending_count() -> int:
	return _pending.size()


func loaded_node_ids() -> Array:
	var result: Array = _loaded.keys()
	result.sort()
	return result


func is_streaming() -> bool:
	return not _pending.is_empty()


## Nombre de bandes visuelles construites depuis les chapitres du graphe.
func section_count() -> int:
	return _sections.size()


## Met à jour la zone utile depuis le ScrollContainer. Le gestionnaire choisit
## les secteurs ; la vue ne redemande jamais un identifiant déjà chargé.
func update_streaming(scroll_vertical: float, viewport_height: float) -> void:
	if _graph == null or _chunk_manager == null or viewport_height <= 0.0:
		return
	var logical_height := viewport_height / maxf(0.001, _scale)
	_viewport_logical = Vector2(UITheme.CAMPAIGN_MAP_WIDTH, maxf(1.0, logical_height))
	_visible_rect = LayoutModel.visible_rect(scroll_vertical, viewport_height, _scale)
	_update_streaming(_visible_rect, _viewport_logical)


## Utilisé par les tests et par un éventuel changement de layout : le rectangle
## est déjà exprimé dans le repère logique de la carte.
func update_streaming_rect(visible_rect: Rect2) -> void:
	if _graph == null or _chunk_manager == null:
		return
	_visible_rect = visible_rect
	_viewport_logical = visible_rect.size
	_update_streaming(_visible_rect, _viewport_logical)


func scroll_for_anchor(node_id: String, offset_y: float) -> float:
	return LayoutModel.scroll_for_anchor(_graph, node_id, offset_y, _scale)


func nearest_node_id(logical_point: Vector2) -> String:
	return LayoutModel.nearest_node_id(_graph, logical_point)


## Points de départ et d'arrivée logiques de toutes les arêtes, pour vérifier
## l'alignement sans dépendre des contrôles instanciés.
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


## Seules les arêtes dont les deux extrémités sont chargées sont dessinées :
## une frontière peut donc rester ouverte jusqu'au lot suivant, sans jamais
## nécessiter de boutons hors écran.
func drawn_edge_endpoints() -> Array:
	var result: Array = []
	for edge in _visible_edges:
		result.append({
			"id": edge.id,
			"from_id": edge.from_id,
			"to_id": edge.to_id,
			"from": node_center(edge.from_id),
			"to": node_center(edge.to_id),
		})
	return result


func drawn_edge_count() -> int:
	return _visible_edges.size()


func relayout() -> void:
	if _graph == null or size.x <= 0.0:
		return
	_scale = LayoutModel.scale_for_width(size.x)
	_edge_points_cache.clear()
	custom_minimum_size = Vector2(0.0, content_height())
	for node_id in _loaded:
		var view: Control = _views.get(node_id, null) as Control
		if view != null:
			_place_view(view, str(node_id))
	queue_redraw()


func _clear_streamed_views() -> void:
	for child in get_children():
		if child is CampaignNodeView:
			remove_child(child)
			child.queue_free()
	_views.clear()
	_loaded.clear()
	_pending.clear()
	_pending_lookup.clear()
	_visible_edges.clear()
	_visible_chapters.clear()
	_sections.clear()
	set_process(false)


func _update_streaming(visible_rect: Rect2, viewport_logical: Vector2) -> void:
	if _chunk_manager == null:
		return
	_visible_rect = visible_rect
	var delta: Dictionary = _chunk_manager.update(visible_rect, viewport_logical)
	var changed := false
	for node_id in delta.get("remove", []):
		var id := str(node_id)
		_pending_lookup.erase(id)
		_pending.erase(id)
		if _loaded.has(id):
			_remove_view(id)
			changed = true
	for node_id in delta.get("add", []):
		var id := str(node_id)
		if _loaded.has(id) or _pending_lookup.has(id):
			continue
		_pending.append(id)
		_pending_lookup[id] = true
	_pending.sort_custom(_sort_pending)
	if not _pending.is_empty():
		set_process(true)
	changed = changed or not (delta.get("add", []) as Array).is_empty()
	if changed:
		_rebuild_visible_edges()
		queue_redraw()
	_emit_streaming()


func _sort_pending(first: String, second: String) -> bool:
	if _initial_focus != "":
		if first == _initial_focus:
			return true
		if second == _initial_focus:
			return false
	var center := _visible_rect.get_center()
	var first_node := _graph.node(first) if _graph != null else null
	var second_node := _graph.node(second) if _graph != null else null
	if first_node == null:
		return false
	if second_node == null:
		return true
	var first_distance := first_node.position.distance_squared_to(center)
	var second_distance := second_node.position.distance_squared_to(center)
	if is_equal_approx(first_distance, second_distance):
		return first < second
	return first_distance < second_distance


func _process(_delta: float) -> void:
	if _pending.is_empty():
		set_process(false)
		return
	_create_batch(FRAME_BATCH_SIZE)


func _create_batch(limit: int) -> void:
	if _graph == null:
		return
	var created := 0
	while created < limit and not _pending.is_empty():
		var node_id: String = _pending.pop_front()
		_pending_lookup.erase(node_id)
		if _loaded.has(node_id):
			continue
		_create_view(node_id)
		created += 1
	if created == 0:
		if _pending.is_empty():
			set_process(false)
		_emit_streaming()
		return
	if _initial_focus != "" and _loaded.has(_focus_id):
		_initial_focus = ""
	_rebuild_visible_edges()
	queue_redraw()
	_emit_streaming()
	if _pending.is_empty():
		set_process(false)


func _create_view(node_id: String) -> void:
	var node := _graph.node(node_id)
	if node == null:
		return
	var view: CampaignNodeView = NodeScene.instantiate() as CampaignNodeView
	# La scène garde une taille d'édition, mais la carte impose son échelle aux
	# nœuds : une taille minimale fixe casserait le rendu téléphone.
	view.custom_minimum_size = Vector2.ZERO
	view.name = "Node_%s" % node_id
	_place_view(view, node_id)
	add_child(view)
	view.pressed.connect(_on_view_pressed.bind(node_id))
	_views[node_id] = view
	_loaded[node_id] = true
	_configure_view(node_id)


func _place_view(view: Control, node_id: String) -> void:
	var diameter := float(UITheme.CAMPAIGN_NODE_SIZE) * _scale
	view.size = Vector2(diameter, diameter)
	view.position = node_center(node_id) - Vector2(diameter, diameter) * 0.5
	view.pivot_offset = view.size * 0.5


func _remove_view(node_id: String) -> void:
	var view: Control = _views.get(node_id, null) as Control
	_views.erase(node_id)
	_loaded.erase(node_id)
	if view == null:
		return
	remove_child(view)
	view.queue_free()


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


func _rebuild_visible_edges() -> void:
	_visible_edges.clear()
	_visible_chapters.clear()
	if _graph == null:
		return
	for edge in _graph.edges():
		if _loaded.has(edge.from_id) and _loaded.has(edge.to_id):
			_visible_edges.append(edge)
	for node_id in _loaded:
		var node := _graph.node(str(node_id))
		if node != null and node.chapter != "" and not _visible_chapters.has(node.chapter):
			_visible_chapters[node.chapter] = node.position.y


func _emit_streaming() -> void:
	streaming_changed.emit(_pending.size())


func _draw() -> void:
	if _graph == null:
		return
	_draw_section_backdrop()
	_draw_edges()
	_draw_map_marks()


## Le fond est tracé avant les arêtes et les repères ; les nœuds étant des
## enfants, ils passent naturellement au-dessus. La transformation logique est
## remise à l'identité par CampaignSectionArt avant le reste du dessin.
func _draw_section_backdrop() -> void:
	if _sections.is_empty():
		return
	SectionArtModel.draw_backdrop(self, _sections, _scale, _visible_rect)


func _draw_edges() -> void:
	for edge in _visible_edges:
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


## Quelques repères de chapitre, limités aux chapitres dont un nœud est chargé.
func _draw_map_marks() -> void:
	if _visible_chapters.is_empty():
		return
	var font := get_theme_default_font()
	for chapter in _visible_chapters:
		var y: float = float(_visible_chapters[chapter]) * _scale - float(
			UITheme.CAMPAIGN_NODE_SIZE) * _scale
		var ink := UITheme.COL_TEXT_DIM
		ink.a = 0.14
		draw_line(Vector2(60.0 * _scale, y), Vector2(1020.0 * _scale, y), ink, 2.0, true)
		if font != null:
			var label_ink := UITheme.COL_TEXT_DIM
			label_ink.a = 0.42
			draw_string(font, Vector2(64.0 * _scale, y - 8.0 * _scale),
				str(chapter).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 520.0 * _scale,
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
