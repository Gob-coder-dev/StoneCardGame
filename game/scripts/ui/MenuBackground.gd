@tool
class_name MenuBackground
extends Control

enum Room { REFUGE, BESTIARY, JOURNAL, ENCOUNTERS, COIN_RITUAL, BOARD, AFTERMATH, PROFILE, ENCOUNTER_PATH }
@export var room: Room = Room.JOURNAL

const VOID := Color("#101013")
const VIOLET_NEON := Color("#c14cff")
const PINK_NEON := Color("#f0449c")
const EMBER_NEON := Color("#f0784d")

var neon_primary_color: Color = VIOLET_NEON
var neon_secondary_color: Color = PINK_NEON
var neon_tertiary_color: Color = EMBER_NEON


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if room == Room.REFUGE and not Engine.is_editor_hint():
		var breath := create_tween().set_loops()
		breath.tween_property(self, "self_modulate", Color(1.0, 0.94, 1.0), 3.0)
		breath.tween_property(self, "self_modulate", Color.WHITE, 3.0)


func set_god(god: Dictionary) -> void:
	neon_primary_color = _god_color(god)
	neon_secondary_color = neon_primary_color.lightened(0.18)
	neon_tertiary_color = neon_primary_color.darkened(0.16)
	queue_redraw()


func set_gods(first_god: Dictionary, second_god: Dictionary) -> void:
	neon_primary_color = _god_color(first_god)
	neon_secondary_color = _god_color(second_god)
	neon_tertiary_color = neon_primary_color.lerp(neon_secondary_color, 0.5)
	queue_redraw()


func _god_color(god: Dictionary) -> Color:
	return Color(str(god.get("color", VIOLET_NEON.to_html())))


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(1080.0, 1920.0))
	_draw_base()
	match room:
		Room.REFUGE:
			_draw_main_menu()
		Room.BESTIARY:
			_draw_relic_menu()
		Room.JOURNAL:
			_draw_journal()
		Room.ENCOUNTERS:
			_draw_encounters()
		Room.ENCOUNTER_PATH:
			_draw_encounter_path()
		Room.COIN_RITUAL:
			_draw_coin_ritual()
		Room.BOARD:
			_draw_board()
		Room.AFTERMATH:
			_draw_aftermath()
		Room.PROFILE:
			_draw_profile()
	draw_set_transform(Vector2.ZERO)


func _draw_base() -> void:
	for band in range(32):
		var t := float(band) / 31.0
		draw_rect(Rect2(0.0, band * 60.0, 1080.0, 61.0),
			Color("#1c1a20").lerp(VOID, t))
	var edge := neon_primary_color
	edge.a = 0.13
	draw_line(Vector2(24.0, 0.0), Vector2(24.0, 1920.0), edge, 2.0)
	draw_line(Vector2(1056.0, 0.0), Vector2(1056.0, 1920.0), edge, 2.0)


func _draw_main_menu() -> void:
	var center := Vector2(540.0, 810.0)
	_draw_glow(center, 430.0, neon_primary_color, 0.022)
	_draw_neon_circle(center, 370.0, neon_primary_color, 3.0)
	_draw_neon_arc(center, 410.0, PI * 1.08, PI * 1.92, neon_secondary_color, 3.0)
	_draw_neon_line(Vector2(294.0, 480.0), Vector2(222.0, 374.0), neon_secondary_color)
	_draw_neon_line(Vector2(786.0, 480.0), Vector2(858.0, 374.0), neon_secondary_color)
	_draw_corner_marks(neon_primary_color, 56.0, 110.0)


func _draw_relic_menu() -> void:
	for x in [20.0, 1060.0]:
		_draw_neon_line(Vector2(x, 0.0), Vector2(x, 1920.0), neon_secondary_color, 2.0)


func _draw_journal() -> void:
	_draw_corner_marks(neon_primary_color, 42.0, 70.0)
	_draw_neon_line(Vector2(48.0, 152.0), Vector2(48.0, 1768.0), neon_primary_color, 1.5)


func _draw_encounters() -> void:
	var center := Vector2(540.0, 985.0)
	_draw_glow(center, 430.0, neon_primary_color, 0.014)
	_draw_neon_arc(center, 430.0, PI * 1.08, PI * 1.92, neon_secondary_color, 3.0)
	_draw_neon_arc(center, 397.0, PI * 1.10, PI * 1.90, neon_primary_color, 2.0)
	_draw_corner_marks(neon_secondary_color, 48.0, 88.0)


## Le serpentin reste au centre ; le décor se contente de deux rails et d'un
## halo, pour ne jamais concurrencer les ronds et leur tracé.
func _draw_encounter_path() -> void:
	var center := Vector2(540.0, 1010.0)
	_draw_glow(center, 520.0, neon_primary_color, 0.013)
	_draw_neon_line(Vector2(52.0, 150.0), Vector2(52.0, 1770.0), neon_secondary_color, 2.0)
	_draw_neon_line(Vector2(1028.0, 150.0), Vector2(1028.0, 1770.0), neon_secondary_color, 2.0)
	_draw_corner_marks(neon_primary_color, 44.0, 86.0)


func _draw_coin_ritual() -> void:
	var center := Vector2(540.0, 990.0)
	_draw_glow(center, 900.0, neon_tertiary_color, 0.008)
	_draw_neon_circle(center, 840.0, neon_primary_color, 1.4)
	_draw_neon_circle(center, 630.0, neon_secondary_color, 1.8)
	_draw_neon_circle(center, 420.0, neon_tertiary_color, 2.2)


func _draw_board() -> void:
	var seam := Color(0.72, 0.62, 0.72, 0.075)
	for y in [250.0, 520.0, 790.0, 1060.0, 1330.0, 1600.0]:
		draw_line(Vector2(30.0, y), Vector2(1050.0, y), seam, 2.0)
	for x in [270.0, 540.0, 810.0]:
		draw_line(Vector2(x, 0.0), Vector2(x, 1920.0), seam, 2.0)
	_draw_neon_line(Vector2(18.0, 0.0), Vector2(18.0, 1920.0),
		neon_primary_color, 1.5)
	_draw_neon_line(Vector2(1062.0, 0.0), Vector2(1062.0, 1920.0),
		neon_primary_color, 1.5)
	_draw_corner_marks(neon_primary_color, 34.0, 104.0)
	for y in [390.0, 780.0, 1170.0, 1560.0]:
		_draw_neon_line(Vector2(18.0, y), Vector2(42.0, y - 22.0),
			neon_secondary_color, 1.0)
		_draw_neon_line(Vector2(1062.0, y), Vector2(1038.0, y - 22.0),
			neon_secondary_color, 1.0)


func _draw_aftermath() -> void:
	var center := Vector2(540.0, 850.0)
	_draw_glow(center, 370.0, neon_primary_color, 0.022)
	_draw_neon_arc(center, 330.0, PI * 0.08, PI * 0.92, neon_primary_color, 3.0)
	_draw_neon_arc(center, 330.0, PI * 1.08, PI * 1.92, neon_secondary_color, 2.0)
	_draw_neon_line(Vector2(270.0, 1210.0), Vector2(410.0, 1150.0), neon_tertiary_color, 2.0)
	_draw_neon_line(Vector2(670.0, 1150.0), Vector2(810.0, 1210.0), neon_tertiary_color, 2.0)


func _draw_profile() -> void:
	for x in [22.0, 1058.0]:
		_draw_neon_line(Vector2(x, 220.0), Vector2(x, 1710.0), neon_primary_color, 2.0)
		_draw_neon_line(Vector2(x, 220.0), Vector2(x + (52.0 if x < 540.0 else -52.0), 168.0),
			neon_tertiary_color, 2.0)
		_draw_neon_line(Vector2(x, 1710.0), Vector2(x + (52.0 if x < 540.0 else -52.0), 1762.0),
			neon_secondary_color, 2.0)
	_draw_neon_line(Vector2(74.0, 195.0), Vector2(270.0, 195.0), neon_primary_color, 1.5)
	_draw_neon_line(Vector2(810.0, 195.0), Vector2(1006.0, 195.0), neon_primary_color, 1.5)
	_draw_neon_line(Vector2(514.0, 195.0), Vector2(540.0, 164.0), neon_tertiary_color, 2.0)
	_draw_neon_line(Vector2(540.0, 164.0), Vector2(566.0, 195.0), neon_tertiary_color, 2.0)
	_draw_neon_circle(Vector2(540.0, 1760.0), 22.0, neon_secondary_color, 1.5)


func _draw_glow(center: Vector2, radius: float, color: Color, strength: float) -> void:
	for layer in range(8, 0, -1):
		var glow := color
		glow.a = strength * (1.0 - float(layer) / 10.0)
		draw_circle(center, radius * float(layer) / 8.0, glow)


func _draw_neon_circle(center: Vector2, radius: float, color: Color, width: float) -> void:
	_draw_neon_arc(center, radius, 0.0, TAU, color, width)


func _draw_neon_arc(center: Vector2, radius: float, start: float, end: float,
		color: Color, width: float) -> void:
	var glow := color
	glow.a = 0.12
	draw_arc(center, radius, start, end, 64, glow, width * 7.0, true)
	glow.a = 0.24
	draw_arc(center, radius, start, end, 64, glow, width * 3.0, true)
	color.a = 0.82
	draw_arc(center, radius, start, end, 64, color, width, true)


func _draw_neon_line(from: Vector2, to: Vector2, color: Color, width: float = 2.0) -> void:
	var glow := color
	glow.a = 0.10
	draw_line(from, to, glow, width * 7.0, true)
	glow.a = 0.25
	draw_line(from, to, glow, width * 3.0, true)
	color.a = 0.78
	draw_line(from, to, color, width, true)


func _draw_corner_marks(color: Color, margin: float, length: float) -> void:
	color.a = 0.32
	for horizontal in [-1.0, 1.0]:
		for vertical in [-1.0, 1.0]:
			var corner := Vector2(
				margin if horizontal < 0.0 else 1080.0 - margin,
				margin if vertical < 0.0 else 1920.0 - margin
			)
			var along_x := Vector2(length * horizontal, 0.0)
			var along_y := Vector2(0.0, length * vertical)
			draw_line(corner, corner + along_x, color, 2.0, true)
			draw_line(corner, corner + along_y, color, 2.0, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
