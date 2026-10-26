## Décor du refuge, dessiné au chargement et au redimensionnement uniquement.
@tool
class_name MenuBackground
extends Control

enum Room { REFUGE, BESTIARY, JOURNAL, ENCOUNTERS }
@export var room: Room = Room.JOURNAL


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if room == Room.REFUGE and not Engine.is_editor_hint():
		# Modulation côté rendu, sans redessiner le décor à chaque image.
		var breath := create_tween().set_loops()
		breath.tween_property(self, "self_modulate", Color(0.94, 0.96, 1.0), 4.0)
		breath.tween_property(self, "self_modulate", Color.WHITE, 4.0)


func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(1080, 1920))
	for band in range(32):
		var t := float(band) / 31.0
		draw_rect(Rect2(0, band * 60, 1080, 61), Color("#252b3a").lerp(UITheme.COL_BG.darkened(0.3), t))
	for x: float in [20.0, 1040.0]:
		draw_rect(Rect2(x, 0, 20, 1920), Color("#111722"))
		draw_line(Vector2(x + 2, 70), Vector2(x + 2, 1810), Color("#3a3a43"), 2)
	if room == Room.REFUGE or room == Room.ENCOUNTERS:
		_draw_arch()
	if room == Room.REFUGE or room == Room.BESTIARY:
		_draw_cabinets()
	_draw_lantern(Vector2(100, 330))
	_draw_lantern(Vector2(980, 330))
	# Positions fixes : aucun hasard du moteur utilisé par le décor.
	for i in range(15):
		var x := 65.0 + float((i * 137) % 950)
		var y := 260.0 + float((i * 233) % 1450)
		draw_rect(Rect2(x, y, 2 + i % 3, 2 + i % 3), Color(0.82, 0.66, 0.42, 0.12))
	if room != Room.REFUGE:
		draw_rect(Rect2(0, 0, 1080, 1920), Color(0.04, 0.06, 0.09, 0.25))
	draw_set_transform(Vector2.ZERO)


func _draw_arch() -> void:
	var outline := PackedVector2Array([Vector2(215, 1390), Vector2(215, 650),
		Vector2(245, 500), Vector2(340, 365), Vector2(540, 275),
		Vector2(740, 365), Vector2(835, 500), Vector2(865, 650), Vector2(865, 1390)])
	draw_colored_polygon(outline, Color("#0e1420"))
	draw_polyline(outline, Color("#383941"), 24, true)
	draw_polyline(outline, Color("#514b46"), 3, true)
	for x: float in [245.0, 835.0]:
		draw_line(Vector2(x, 695), Vector2(x, 1370), Color("#252c39"), 10)
	for ring in range(8, 0, -1):
		draw_circle(Vector2(540, 1040), 125 + ring * 24, Color(0.65, 0.39, 0.20, 0.009))


func _draw_cabinets() -> void:
	for x: float in [44.0, 868.0]:
		for shelf in range(3):
			var y := 690.0 + shelf * 275
			draw_rect(Rect2(x, y, 168, 230), Color("#171c27"))
			draw_rect(Rect2(x, y + 222, 168, 12), Color("#3b3635"))
			for book in range(4):
				var height := 60 + ((book + shelf) * 17) % 75
				var bx := x + 18 + book * 31
				draw_rect(Rect2(bx, y + 218 - height, 23, height),
					Color("#3a3440") if book % 2 == 0 else Color("#303c3e"))
				draw_line(Vector2(bx + 4, y + 214 - height), Vector2(bx + 4, y + 211), Color("#544844"), 2)


func _draw_lantern(at: Vector2) -> void:
	for ring in range(6, 0, -1):
		draw_circle(at + Vector2(0, 35), 30 + ring * 20, Color(0.95, 0.61, 0.27, 0.012))
	draw_line(at - Vector2(0, 130), at, Color("#534b43"), 4)
	draw_rect(Rect2(at - Vector2(22, 5), Vector2(44, 68)), Color("#554337"))
	draw_rect(Rect2(at - Vector2(13, 0), Vector2(26, 54)), Color("#c78e48"))
	draw_rect(Rect2(at - Vector2(5, -10), Vector2(10, 34)), UITheme.COL_ACCENT_LIGHT)
	draw_line(at + Vector2(-27, -6), at + Vector2(27, -6), Color("#877059"), 5)
	draw_line(at + Vector2(-27, 65), at + Vector2(27, 65), Color("#877059"), 5)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
