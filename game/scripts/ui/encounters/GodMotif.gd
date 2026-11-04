## GodMotif.gd
## Motifs de fond propres à chaque dieu, dessinés à la manière du décor
## procédural de MenuBackground. Ils restent provisoires : le jour où un PNG
## par dieu est livré, seul ce fichier change, sans toucher aux écrans.
class_name GodMotif
extends RefCounted


static func draw(canvas: CanvasItem, god_id: String, center: Vector2, radius: float,
		color: Color, alpha: float = 0.12) -> void:
	if canvas == null or radius <= 1.0 or alpha <= 0.0:
		return
	var ink := color
	ink.a = alpha
	match god_id:
		"veskar":
			_dice(canvas, center, radius, ink)
		"nerava":
			_spores(canvas, center, radius, ink)
		"kharun":
			_rampart(canvas, center, radius, ink)
		"ilyr":
			_gaze(canvas, center, radius, ink)
		"sylkha":
			_hive(canvas, center, radius, ink)
		"enigma":
			_machinery(canvas, center, radius, ink)
		_:
			_fracture(canvas, center, radius, ink)


## Deux dés penchés : le hasard de Véskar.
static func _dice(canvas: CanvasItem, center: Vector2, radius: float, ink: Color) -> void:
	for side in [-1.0, 1.0]:
		var base := center + Vector2(radius * 0.36 * side, -radius * 0.08 * side)
		var half := radius * 0.29
		var angle: float = 0.32 * float(side)
		var square := PackedVector2Array()
		for corner in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
			square.append(base + corner.rotated(angle) * half)
		var fill := ink
		fill.a = ink.a * 0.35
		canvas.draw_colored_polygon(square, fill)
		var outline := square.duplicate()
		outline.append(square[0])
		canvas.draw_polyline(outline, ink, 3.0, true)
		for pip in [Vector2(-1.0, -1.0), Vector2(1.0, 1.0), Vector2(0.0, 0.0)]:
			canvas.draw_circle(base + pip.rotated(angle) * half * 0.38, radius * 0.042, ink)


## Anneaux et spores : les fièvres de Nérava.
static func _spores(canvas: CanvasItem, center: Vector2, radius: float, ink: Color) -> void:
	for ring in range(3):
		canvas.draw_arc(center, radius * (0.20 + 0.15 * ring), 0.0, TAU, 44, ink, 2.5, true)
	for index in range(9):
		var angle := TAU * float(index) / 9.0 + 0.4
		var distance := radius * (0.44 + 0.09 * float(index % 3))
		canvas.draw_circle(center + Vector2(cos(angle), sin(angle)) * distance,
			radius * 0.05, ink)


## Assises de pierre : la Muraille de Kharûn.
static func _rampart(canvas: CanvasItem, center: Vector2, radius: float, ink: Color) -> void:
	var brick := radius * 0.21
	for row in range(4):
		var offset := 0.0 if row % 2 == 0 else brick * 0.6
		for column in range(4):
			var position := center + Vector2(
				(float(column) - 1.5) * brick * 1.28 + offset,
				(float(row) - 1.5) * brick * 0.92)
			canvas.draw_rect(Rect2(position, Vector2(brick * 1.04, brick * 0.64)), ink, false, 2.5)


## Œil et rayons : le Guetteur Éternel.
static func _gaze(canvas: CanvasItem, center: Vector2, radius: float, ink: Color) -> void:
	canvas.draw_arc(center, radius * 0.30, 0.0, TAU, 48, ink, 3.0, true)
	canvas.draw_circle(center, radius * 0.07, ink)
	for index in range(8):
		var angle := TAU * float(index) / 8.0 + PI / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		canvas.draw_line(center + direction * radius * 0.44,
			center + direction * radius * 0.62, ink, 3.0, true)


## Alvéoles : la Mère-Ruche.
static func _hive(canvas: CanvasItem, center: Vector2, radius: float, ink: Color) -> void:
	var cells := [
		Vector2(0.0, 0.0), Vector2(1.05, 0.0), Vector2(-1.05, 0.0),
		Vector2(0.52, 0.90), Vector2(-0.52, 0.90),
		Vector2(0.52, -0.90), Vector2(-0.52, -0.90),
	]
	for cell in cells:
		canvas.draw_polyline(_hexagon(center + cell * radius * 0.21, radius * 0.19),
			ink, 2.5, true)


static func _hexagon(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(7):
		var angle := TAU * float(index) / 6.0 + PI / 6.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## Engrenages et circuits : la Machine Première.
static func _machinery(canvas: CanvasItem, center: Vector2, radius: float, ink: Color) -> void:
	canvas.draw_arc(center, radius * 0.32, 0.0, TAU, 48, ink, 3.0, true)
	canvas.draw_arc(center, radius * 0.14, 0.0, TAU, 36, ink, 2.5, true)
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var direction := Vector2(cos(angle), sin(angle))
		canvas.draw_line(center + direction * radius * 0.33,
			center + direction * radius * 0.44, ink, 2.5, true)
	canvas.draw_polyline(PackedVector2Array([
		center + Vector2(-radius * 0.66, radius * 0.48),
		center + Vector2(-radius * 0.28, radius * 0.48),
		center + Vector2(-radius * 0.10, radius * 0.26),
	]), ink, 2.5, true)


## Anneau brisé et trait franc : la source sans dieu.
static func _fracture(canvas: CanvasItem, center: Vector2, radius: float, ink: Color) -> void:
	canvas.draw_arc(center, radius * 0.34, 0.45, 2.15, 28, ink, 3.0, true)
	canvas.draw_arc(center, radius * 0.34, 3.55, 5.35, 28, ink, 3.0, true)
	canvas.draw_line(center + Vector2(-radius * 0.42, -radius * 0.42),
		center + Vector2(radius * 0.42, radius * 0.42), ink, 2.5, true)
