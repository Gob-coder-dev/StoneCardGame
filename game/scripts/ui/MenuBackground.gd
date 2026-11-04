@tool
class_name MenuBackground
extends Control

enum Room {
	REFUGE, BESTIARY, JOURNAL, ENCOUNTERS, COIN_RITUAL, BOARD, AFTERMATH,
	PROFILE, ENCOUNTER_PATH, PVP, AFTERMATH_DEFEAT, AFTERMATH_DRAW
}
@export var room: Room = Room.JOURNAL

const VOID := Color("#101013")
const VIOLET_NEON := Color("#c14cff")
const PINK_NEON := Color("#f0449c")
const EMBER_NEON := Color("#f0784d")
const RESULT_NEUTRAL := Color("#bcb2bd")

## Écart entre les trois néons d'un même décor : la teinte tourne d'environ 40°
## de part et d'autre du dieu, la valeur monte ou descend nettement. Un simple
## éclaircissement laissait les accents trop proches pour être distingués.
const NEON_HUE_SHIFT := 0.10
const NEON_LIGHT_STEP := 0.12
const NEON_DARK_STEP := 0.28

## Filets plus épais partout, sauf sur le profil et le bestiaire (decks), dont
## les panneaux occupent déjà la largeur et n'ont pas besoin de ce relief. Le
## rituel de la pièce et le résultat, plus dépouillés, reçoivent un trait plus
## marqué encore.
const NEON_WIDTH_SCALE := 1.5
const NEON_WIDTH_SCALE_COIN := 2.6
const NEON_WIDTH_SCALE_STRONG := 3.0

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
	neon_secondary_color = _neon_variant(neon_primary_color, 1.0)
	neon_tertiary_color = _neon_variant(neon_primary_color, -1.0)
	queue_redraw()


func set_gods(first_god: Dictionary, second_god: Dictionary) -> void:
	neon_primary_color = _god_color(first_god)
	neon_secondary_color = _god_color(second_god)
	neon_tertiary_color = _neon_variant(neon_primary_color.lerp(neon_secondary_color, 0.5), 1.0)
	queue_redraw()


func set_result_victory(god: Dictionary) -> void:
	room = Room.AFTERMATH
	_set_result_color(RESULT_NEUTRAL if god.is_empty() else _god_color(god))


func set_result_defeat(god: Dictionary) -> void:
	room = Room.AFTERMATH_DEFEAT
	_set_result_color(RESULT_NEUTRAL if god.is_empty() else _god_color(god))


func set_result_draw(first_god: Dictionary, second_god: Dictionary) -> void:
	room = Room.AFTERMATH_DRAW
	neon_primary_color = RESULT_NEUTRAL if first_god.is_empty() else _god_color(first_god)
	neon_secondary_color = RESULT_NEUTRAL if second_god.is_empty() else _god_color(second_god)
	neon_tertiary_color = _neon_variant(
		neon_primary_color.lerp(neon_secondary_color, 0.5), 1.0)
	queue_redraw()


func _set_result_color(color: Color) -> void:
	neon_primary_color = color
	neon_secondary_color = color
	neon_tertiary_color = color
	queue_redraw()


## Accent dérivé du dieu : la teinte et la valeur s'écartent assez pour que les
## trois néons d'un menu se lisent comme trois couleurs, sans quitter la gamme.
func _neon_variant(base: Color, direction: float) -> Color:
	var hue := fposmod(base.h + NEON_HUE_SHIFT * direction, 1.0)
	var saturation := base.s
	var value := base.v
	if direction > 0.0:
		saturation = clampf(saturation * 1.10, 0.45, 1.0)
		value = clampf(value + NEON_LIGHT_STEP, 0.0, 1.0)
	else:
		saturation = clampf(saturation * 0.96, 0.40, 1.0)
		value = clampf(value - NEON_DARK_STEP, 0.32, 1.0)
	return Color.from_hsv(hue, saturation, value)


func _neon_width_scale() -> float:
	match room:
		Room.PROFILE, Room.BESTIARY:
			return 1.0
		Room.COIN_RITUAL:
			return NEON_WIDTH_SCALE_COIN
		Room.AFTERMATH, Room.AFTERMATH_DEFEAT, Room.AFTERMATH_DRAW:
			return NEON_WIDTH_SCALE_STRONG
	return NEON_WIDTH_SCALE


func _god_color(god: Dictionary) -> Color:
	return Color(str(god.get("color", VIOLET_NEON.to_html())))


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	_draw_base()
	var scale := _artwork_scale_for_size(size)
	draw_set_transform(_artwork_offset_for_size(size, scale), 0.0,
		Vector2.ONE * scale)
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
		Room.AFTERMATH_DEFEAT:
			_draw_aftermath_defeat()
		Room.AFTERMATH_DRAW:
			_draw_aftermath_draw()
		Room.PROFILE:
			_draw_profile()
		Room.PVP:
			_draw_pvp()
	draw_set_transform(Vector2.ZERO)


func _draw_base() -> void:
	for band in range(32):
		var t := float(band) / 31.0
		var band_top := size.y * float(band) / 32.0
		var band_bottom := size.y * float(band + 1) / 32.0
		draw_rect(Rect2(0.0, band_top, size.x, band_bottom - band_top),
			Color("#1c1a20").lerp(VOID, t))
	var edge := neon_primary_color
	edge.a = 0.13
	draw_line(Vector2(size.x * 0.022, 0.0),
		Vector2(size.x * 0.022, size.y), edge, 2.0)
	draw_line(Vector2(size.x * 0.978, 0.0),
		Vector2(size.x * 0.978, size.y), edge, 2.0)


func _artwork_scale_for_size(viewport_size: Vector2) -> float:
	return minf(viewport_size.x / 1080.0, viewport_size.y / 1920.0)


func _artwork_offset_for_size(viewport_size: Vector2, scale: float) -> Vector2:
	var artwork_size := Vector2(1080.0, 1920.0) * scale
	return (viewport_size - artwork_size) * 0.5


## Le cercle se cale sur le portrait du dieu ; les flicks supérieurs suivent le
## même décalage pour rester dans l'axe de l'arche.
func _draw_main_menu() -> void:
	var center := Vector2(540.0, 850.0)
	_draw_glow(center, 430.0, neon_primary_color, 0.022)
	_draw_neon_circle(center, 370.0, neon_primary_color, 3.0)
	_draw_neon_arc(center, 410.0, PI * 1.08, PI * 1.92, neon_secondary_color, 3.0)
	_draw_neon_line(Vector2(294.0, 520.0), Vector2(222.0, 414.0), neon_secondary_color)
	_draw_neon_line(Vector2(786.0, 520.0), Vector2(858.0, 414.0), neon_secondary_color)
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
	_draw_neon_circle(center, 840.0, neon_primary_color, 2.2)
	_draw_neon_circle(center, 630.0, neon_secondary_color, 2.8)
	_draw_neon_circle(center, 420.0, neon_tertiary_color, 3.4)


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
	_draw_firework(Vector2(125.0, 280.0), 76.0, 8,
		_winner_firework_color(0), 0.02, 0)
	_draw_firework(Vector2(885.0, 235.0), 118.0, 12,
		_winner_firework_color(1), 0.08, 1)
	_draw_firework(Vector2(390.0, 410.0), 54.0, 7,
		_winner_firework_color(2), 0.0, 2)
	_draw_firework(Vector2(1010.0, 710.0), 84.0, 10,
		_winner_firework_color(3), 0.04, 0)
	_draw_firework(Vector2(105.0, 940.0), 104.0, 14,
		_winner_firework_color(4), 0.02, 1)
	_draw_firework(Vector2(920.0, 1250.0), 64.0, 8,
		_winner_firework_color(0), 0.08, 2)
	_draw_firework(Vector2(245.0, 1530.0), 116.0, 11,
		_winner_firework_color(1), 0.0, 1)
	_draw_firework(Vector2(850.0, 1730.0), 82.0, 9,
		_winner_firework_color(3), 0.04, 0)


func _draw_aftermath_defeat() -> void:
	_draw_skull(Vector2(540.0, 960.0), neon_primary_color)


func _draw_aftermath_draw() -> void:
	_draw_arena_architecture(neon_primary_color)
	_draw_crossed_swords(Vector2(540.0, 1030.0),
		neon_primary_color, neon_secondary_color)


func _winner_firework_color(index: int) -> Color:
	var hue_shifts: Array[float] = [-0.075, -0.04, 0.0, 0.04, 0.075]
	var hue_shift: float = hue_shifts[posmod(index, hue_shifts.size())]
	var hue: float = fposmod(neon_primary_color.h + hue_shift, 1.0)
	var saturation := clampf(neon_primary_color.s * 0.88, 0.55, 1.0)
	var brightness := clampf(neon_primary_color.v + 0.28, 0.0, 1.0)
	return Color.from_hsv(hue, saturation, brightness)


func _draw_firework(center: Vector2, radius: float, ray_count: int,
	color: Color, phase: float, ring_style: int) -> void:
	for ray in range(ray_count):
		var angle := phase + TAU * float(ray) / float(ray_count)
		var direction := Vector2(cos(angle), sin(angle))
		var length := radius * (1.0 if ray % 2 == 0 else 0.68)
		var start := center + direction * radius * 0.16
		var finish := center + direction * length
		_draw_neon_line(start, finish, color, 1.0 if ray % 3 == 0 else 0.7)
	if ring_style > 0:
		_draw_neon_circle(center, radius * 0.34, color, 0.8)
	if ring_style > 1:
		_draw_neon_circle(center, radius * 0.16, color, 0.7)
	_draw_neon_circle(center, maxf(3.0, radius * 0.035), color, 1.0)


func _draw_skull(center: Vector2, color: Color) -> void:
	var outline := PackedVector2Array()
	for index in range(25):
		var angle := PI + PI * float(index) / 24.0
		outline.append(Vector2(center.x + cos(angle) * 230.0,
			center.y - 125.0 + sin(angle) * 250.0))
	for point in [
		Vector2(center.x + 212.0, center.y + 42.0),
		Vector2(center.x + 174.0, center.y + 145.0),
		Vector2(center.x + 105.0, center.y + 204.0),
		Vector2(center.x + 80.0, center.y + 260.0),
		Vector2(center.x - 80.0, center.y + 260.0),
		Vector2(center.x - 105.0, center.y + 204.0),
		Vector2(center.x - 174.0, center.y + 145.0),
		Vector2(center.x - 212.0, center.y + 42.0),
	]:
		outline.append(point)
	outline.append(outline[0])
	draw_polyline(outline, color, 4.0, true)

	for eye_x in [center.x - 105.0, center.x + 105.0]:
		draw_circle(Vector2(eye_x, center.y - 35.0), 68.0, Color("#101013"))
		_draw_neon_circle(Vector2(eye_x, center.y - 35.0), 68.0,
			color, 2.2)
	_draw_neon_line(Vector2(center.x - 48.0, center.y - 138.0),
		Vector2(center.x + 48.0, center.y - 138.0), color, 2.0)

	var nose := PackedVector2Array([
		Vector2(center.x, center.y + 45.0),
		Vector2(center.x - 35.0, center.y + 112.0),
		Vector2(center.x + 35.0, center.y + 112.0),
	])
	draw_colored_polygon(nose, Color("#101013"))
	_draw_neon_line(nose[0], nose[1], color, 1.8)
	_draw_neon_line(nose[1], nose[2], color, 1.8)
	_draw_neon_line(nose[2], nose[0], color, 1.8)
	_draw_neon_line(Vector2(center.x - 142.0, center.y + 142.0),
		Vector2(center.x + 142.0, center.y + 142.0), color, 2.0)
	for tooth in range(7):
		var x := center.x - 105.0 + float(tooth) * 35.0
		_draw_neon_line(Vector2(x, center.y + 142.0),
			Vector2(x, center.y + (190.0 if tooth % 2 == 0 else 176.0)),
			color, 1.2)


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


## Le choix, la recherche et la salle partagent le même décor d'arène.
func _draw_pvp() -> void:
	_draw_arena_architecture(neon_primary_color)
	_draw_crossed_swords(Vector2(540.0, 1030.0),
		neon_primary_color, neon_secondary_color)


func _draw_arena_architecture(accent: Color) -> void:
	var center := Vector2(540.0, 820.0)
	_draw_arena_arch(center, 510.0, 1790.0, Color("#1a171d"))
	_draw_arena_arch(center, 405.0, 1790.0, Color("#111014"))
	_draw_arch_outline(center, 510.0, accent, 2.2)
	_draw_arch_outline(center, 405.0, accent, 1.2)
	_draw_arch_keystone(center, accent)
	_draw_arena_floor(accent)


func _draw_crossed_swords(center: Vector2, first_color: Color,
		second_color: Color) -> void:
	_draw_sword(center + Vector2(-190.0, 205.0),
		center + Vector2(210.0, -235.0), first_color)
	_draw_sword(center + Vector2(190.0, 205.0),
		center + Vector2(-210.0, -235.0), second_color)


func _draw_sword(hilt: Vector2, tip: Vector2, color: Color) -> void:
	var direction := (tip - hilt).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var guard_center := hilt + direction * 92.0
	var blade_base := guard_center + direction * 18.0
	var blade := PackedVector2Array([
		guard_center + perpendicular * 29.0,
		blade_base + perpendicular * 14.0,
		tip,
		blade_base - perpendicular * 14.0,
		guard_center - perpendicular * 29.0,
	])
	var shadow := Color("#111014")
	draw_colored_polygon(blade, shadow)
	blade.append(blade[0])
	draw_polyline(blade, color, 2.6, true)
	_draw_neon_line(blade_base, tip, color, 1.0)
	_draw_neon_line(hilt - direction * 42.0, guard_center, color, 3.0)
	_draw_neon_line(guard_center - perpendicular * 48.0,
		guard_center + perpendicular * 48.0, color, 3.0)
	_draw_neon_circle(hilt - direction * 45.0, 8.0, color, 2.0)


func _draw_arena_arch(center: Vector2, radius: float, bottom: float, color: Color) -> void:
	var points := PackedVector2Array()
	var segments := 32
	for index in range(segments + 1):
		var angle := PI + PI * float(index) / float(segments)
		points.append(Vector2(center.x + cos(angle) * radius,
			center.y + sin(angle) * radius))
	points.append(Vector2(center.x + radius, bottom))
	points.append(Vector2(center.x - radius, bottom))
	draw_colored_polygon(points, color)


func _draw_arch_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	_draw_neon_arc(center, radius, PI, TAU, color, width)
	_draw_neon_line(Vector2(center.x - radius, center.y),
		Vector2(center.x - radius, 1780.0), color, width)
	_draw_neon_line(Vector2(center.x + radius, center.y),
		Vector2(center.x + radius, 1780.0), color, width)


func _draw_arch_keystone(center: Vector2, color: Color) -> void:
	var stone := PackedVector2Array([
		Vector2(center.x - 26.0, center.y - 494.0),
		Vector2(center.x, center.y - 526.0),
		Vector2(center.x + 26.0, center.y - 494.0),
	])
	draw_colored_polygon(stone, Color("#322b34"))
	_draw_neon_line(stone[0], stone[1], color, 1.4)
	_draw_neon_line(stone[1], stone[2], color, 1.4)


func _draw_arena_floor(accent: Color) -> void:
	var seam := Color("#a49aa5")
	seam.a = 0.11
	for y in [1530.0, 1640.0, 1740.0]:
		draw_line(Vector2(80.0, y), Vector2(1000.0, y), seam, 2.0)
	for x in [220.0, 390.0, 690.0, 860.0]:
		draw_line(Vector2(540.0, 1410.0), Vector2(x, 1790.0), seam, 2.0)
	_draw_neon_line(Vector2(80.0, 1530.0), Vector2(260.0, 1530.0), accent, 1.0)
	_draw_neon_line(Vector2(1000.0, 1530.0), Vector2(820.0, 1530.0), accent, 1.0)


func _draw_glow(center: Vector2, radius: float, color: Color, strength: float) -> void:
	for layer in range(8, 0, -1):
		var glow := color
		glow.a = strength * (1.0 - float(layer) / 10.0)
		draw_circle(center, radius * float(layer) / 8.0, glow)


func _draw_neon_circle(center: Vector2, radius: float, color: Color, width: float) -> void:
	_draw_neon_arc(center, radius, 0.0, TAU, color, width)


func _draw_neon_arc(center: Vector2, radius: float, start: float, end: float,
		color: Color, width: float) -> void:
	width *= _neon_width_scale()
	var glow := color
	glow.a = 0.12
	draw_arc(center, radius, start, end, 64, glow, width * 7.0, true)
	glow.a = 0.24
	draw_arc(center, radius, start, end, 64, glow, width * 3.0, true)
	color.a = 0.82
	draw_arc(center, radius, start, end, 64, color, width, true)


func _draw_neon_line(from: Vector2, to: Vector2, color: Color, width: float = 2.0) -> void:
	width *= _neon_width_scale()
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
