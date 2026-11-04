## PathTrack.gd
## Serpentin des niveaux : place les ronds en alternance, trace la courbe,
## pose les bandeaux de chapitre et le sigil du dieu. Il ne lit ni le profil
## ni le catalogue : il affiche les niveaux déjà résolus par le contrôleur.
class_name PathTrack
extends Control

signal level_selected(index: int)

const PathNodeView := preload("res://scripts/ui/encounters/PathNode.gd")
const EncounterPathModel := preload("res://scripts/domain/EncounterPath.gd")
const GodMotifModel := preload("res://scripts/ui/encounters/GodMotif.gd")

var _source: Dictionary = {}
var _path: Array = []
var _nodes: Array = []
var _chapter_labels: Array = []
var _chapter_indices: Array = []
var _selected := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func setup(path: Array, source: Dictionary) -> void:
	_source = source
	_path = path
	_rebuild()


## Met à jour les états sans reconstruire les ronds quand leur nombre ne
## change pas : une victoire débloque le niveau suivant sans clignotement.
func set_path(path: Array) -> void:
	if path.size() != _nodes.size():
		_path = path
		_rebuild()
		return
	_path = path
	for index in range(_nodes.size()):
		_nodes[index].configure(_path[index], _accent_color(), index == _selected)
	queue_redraw()


func set_selected(index: int) -> void:
	_selected = index
	for node_index in range(_nodes.size()):
		_nodes[node_index].set_chosen(node_index == index)


func node_for(index: int) -> Button:
	if index < 0 or index >= _nodes.size():
		return null
	return _nodes[index]


func node_count() -> int:
	return _nodes.size()


func _accent_color() -> Color:
	return Color(str(_source.get("color", UITheme.COL_NEON_PINK.to_html())))


func _rebuild() -> void:
	for node in _nodes:
		remove_child(node)
		node.queue_free()
	for label in _chapter_labels:
		remove_child(label)
		label.queue_free()
	_nodes.clear()
	_chapter_labels.clear()
	_chapter_indices.clear()
	if _path.is_empty():
		custom_minimum_size = Vector2.ZERO
		queue_redraw()
		return

	var height := UITheme.PATH_TOP_PAD \
		+ maxi(0, _path.size() - 1) * UITheme.PATH_STEP + UITheme.PATH_BOTTOM_PAD
	custom_minimum_size = Vector2(0, height)
	for index in range(_path.size()):
		var level: Dictionary = _path[index]
		var node: PathNodeView = PathNodeView.new()
		node.name = "Level_%02d" % index
		add_child(node)
		node.configure(level, _accent_color(), index == _selected)
		node.pressed.connect(_on_node_pressed.bind(index))
		_nodes.append(node)
		if bool(level.get("chapter_start", false)):
			_chapter_indices.append(index)
			_chapter_labels.append(_make_chapter_label(level))
	_layout.call_deferred()


func _make_chapter_label(level: Dictionary) -> Label:
	var label := Label.new()
	label.name = "Chapter_%d" % int(level.get("chapter_index", 0))
	label.text = str(level.get("bracket_label", "")).to_upper()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	add_child(label)
	return label


func _layout() -> void:
	if _nodes.is_empty():
		return
	var width := size.x if size.x > 0.0 else 1080.0
	var diameter := float(UITheme.PATH_NODE_SIZE)
	for index in range(_nodes.size()):
		var node: PathNodeView = _nodes[index]
		node.size = Vector2(diameter, diameter)
		node.position = _node_center(index, width) - Vector2(diameter, diameter) * 0.5
	for label_index in range(_chapter_labels.size()):
		var level_index: int = _chapter_indices[label_index]
		var label: Label = _chapter_labels[label_index]
		label.size = Vector2(width, UITheme.PATH_CHAPTER_LABEL_HEIGHT)
		label.position = Vector2(0.0,
			_node_center(level_index, width).y - diameter * 0.5
			- UITheme.PATH_CHAPTER_LABEL_HEIGHT - 16.0)
	queue_redraw()


func _node_center(index: int, width: float) -> Vector2:
	var swing := minf(UITheme.PATH_SWING,
		width * 0.5 - float(UITheme.PATH_NODE_SIZE) * 0.68)
	var direction := -1.0 if index % 2 == 0 else 1.0
	return Vector2(width * 0.5 + direction * swing,
		float(UITheme.PATH_TOP_PAD + index * UITheme.PATH_STEP))


func _on_node_pressed(index: int) -> void:
	level_selected.emit(index)


func _draw() -> void:
	if _path.is_empty() or size.x <= 0.0:
		return
	var accent := _accent_color()
	GodMotifModel.draw(self, str(_source.get("id", "")),
		Vector2(size.x * 0.5, size.y * 0.48), minf(size.x, size.y) * 0.55, accent, 0.05)
	for index in range(_chapter_indices.size()):
		_draw_chapter_rule(_chapter_indices[index], accent)
	for index in range(_nodes.size() - 1):
		_draw_segment(index, accent)


## Courbe douce entre deux ronds : les deux points de contrôle restent sur la
## verticale, ce qui donne le S caractéristique du serpentin.
func _draw_segment(index: int, accent: Color) -> void:
	var from := _node_center(index, size.x)
	var to := _node_center(index + 1, size.x)
	var control := Vector2(0.0, float(UITheme.PATH_STEP) * 0.52)
	var points := PackedVector2Array()
	for step in range(13):
		var weight := float(step) / 12.0
		points.append(from.cubic_interpolate(to, from + control, to - control, weight))
	var locked := int(_path[index + 1].get("state", EncounterPathModel.State.LOCKED)) \
		== EncounterPathModel.State.LOCKED
	if locked:
		var trace := UITheme.COL_PATH_TRACE
		trace.a = 0.42
		draw_polyline(points, trace, 3.0, true)
		for step in range(1, 12, 2):
			draw_circle(points[step], 3.0, trace)
		return
	var glow := accent
	glow.a = 0.10
	draw_polyline(points, glow, 18.0, true)
	glow.a = 0.22
	draw_polyline(points, glow, 9.0, true)
	var trace := accent
	trace.a = 0.85
	draw_polyline(points, trace, 4.0, true)


func _draw_chapter_rule(index: int, accent: Color) -> void:
	if index == 0:
		return
	var y := _node_center(index, size.x).y - float(UITheme.PATH_NODE_SIZE) * 0.5 \
		- UITheme.PATH_CHAPTER_LABEL_HEIGHT - 36.0
	var ink := accent
	ink.a = 0.16
	draw_line(Vector2(UITheme.MARGIN_SCREEN, y),
		Vector2(size.x - UITheme.MARGIN_SCREEN, y), ink, 2.0, true)
	draw_circle(Vector2(size.x * 0.5, y), 4.0, ink)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
