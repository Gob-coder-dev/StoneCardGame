## Illustration vectorielle responsive des quatre sceaux. Elle évite des
## textures floues sur tablette et garde les couleurs pilotées par les données.
class_name RitualSigil
extends Control

var _definition: Dictionary = {}
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func setup(definition: Dictionary) -> void:
	_definition = definition.duplicate(true)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if _definition.is_empty():
		return
	var center := size * 0.5
	# Le cercle gagne en présence, mais conserve une couronne extérieure dédiée
	# aux bougies afin qu'elles ne masquent plus les traits du sceau.
	var radius := minf(size.x, size.y) * 0.37
	var blood := Color(str(_definition.get("blood_color", "#a62f35")))
	var glow := blood.lightened(0.24)
	var pulse := 0.84 + sin(_time * 2.2) * 0.08
	draw_circle(center, radius * 1.18, Color(blood, 0.05))
	draw_arc(center, radius, 0.0, TAU, 96, Color(glow, 0.22 * pulse), 15.0, true)
	draw_arc(center, radius, 0.0, TAU, 96, blood, 7.0, true)
	var sigil := str(_definition.get("sigil", "triangle"))
	var points := 3 if sigil == "triangle" else (5 if sigil == "pentagram" else 7)
	var step := 1 if points == 3 else (2 if points == 5 else 3)
	var vertices: Array[Vector2] = []
	for index in range(points):
		var angle := -PI * 0.5 + TAU * float(index) / float(points)
		vertices.append(center + Vector2(cos(angle), sin(angle)) * radius * 0.86)
	var path := PackedVector2Array()
	var cursor := 0
	for _index in range(points):
		path.append(vertices[cursor])
		cursor = (cursor + step) % points
	path.append(path[0])
	draw_polyline(path, Color(glow, 0.30 * pulse), 17.0, true)
	draw_polyline(path, blood, 7.0, true)
	if sigil == "demon_heptagram":
		_draw_demon(center, radius * 0.48, blood, glow)
	var candle_colors: Array = _definition.get("candle_colors", [])
	for index in range(vertices.size()):
		var color := Color(str(candle_colors[index % candle_colors.size()])) \
			if not candle_colors.is_empty() else Color("#e6b56d")
		var direction := (vertices[index] - center).normalized()
		_draw_candle(center + direction * radius * 1.12, color, pulse)


func _draw_candle(position: Vector2, color: Color, pulse: float) -> void:
	var body := Rect2(position + Vector2(-9, -2), Vector2(18, 29))
	draw_rect(body, color.darkened(0.28), true)
	draw_rect(body, color.lightened(0.18), false, 3.0)
	var flame_center := position + Vector2(0, -15)
	draw_circle(flame_center, 18.0 * pulse, Color(color, 0.12))
	var flame := PackedVector2Array([
		flame_center + Vector2(0, -15), flame_center + Vector2(9, 4),
		flame_center + Vector2(0, 12), flame_center + Vector2(-9, 4)])
	draw_colored_polygon(flame, color.lightened(0.28))


func _draw_demon(center: Vector2, radius: float, blood: Color, glow: Color) -> void:
	var head := PackedVector2Array([
		center + Vector2(-radius, -radius * 0.82),
		center + Vector2(-radius * 0.55, -radius * 0.35),
		center + Vector2(-radius * 0.62, radius * 0.25),
		center + Vector2(0, radius),
		center + Vector2(radius * 0.62, radius * 0.25),
		center + Vector2(radius * 0.55, -radius * 0.35),
		center + Vector2(radius, -radius * 0.82),
		center + Vector2(radius * 0.25, -radius * 0.55),
		center + Vector2(0, -radius * 0.35),
		center + Vector2(-radius * 0.25, -radius * 0.55),
	])
	draw_polyline(head, blood, 9.0, true)
	draw_circle(center + Vector2(-radius * 0.25, 0), 6.0, glow)
	draw_circle(center + Vector2(radius * 0.25, 0), 6.0, glow)
