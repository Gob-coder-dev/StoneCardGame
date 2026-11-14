## Décors procéduraux partagés par les menus. Le composant ne décide jamais
## de la navigation ; il adapte seulement une salle et ses couleurs au viewport.
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
const PVP_ARCH_BOTTOM := 1920.0
const SKULL_SCALE := 2.15
const SKULL_CENTER := Vector2(540.0, 1035.0)

## Écart entre les trois néons d'un même décor : la teinte tourne d'environ 40°
## de part et d'autre du dieu, la valeur monte ou descend nettement. Un simple
## éclaircissement laissait les accents trop proches pour être distingués.
const NEON_HUE_SHIFT := 0.10
const NEON_LIGHT_STEP := 0.12
const NEON_DARK_STEP := 0.28

## Filets plus épais sur les décors dessinés dans l'artwork. Le rituel de la
## pièce et le résultat, plus dépouillés, reçoivent un trait plus marqué encore.
## Les deux filets latéraux partagés gardent une épaisseur fixe.
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
	neon_secondary_color = _god_secondary_color(god, neon_primary_color)
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
		Room.COIN_RITUAL:
			return NEON_WIDTH_SCALE_COIN
		Room.AFTERMATH, Room.AFTERMATH_DEFEAT, Room.AFTERMATH_DRAW:
			return NEON_WIDTH_SCALE_STRONG
	return NEON_WIDTH_SCALE


func _god_color(god: Dictionary) -> Color:
	return Color(str(god.get("color", VIOLET_NEON.to_html())))


## Les dieux dérivent leur second néon de leur couleur ; les deux identités sans
## dieu fournissent une palette explicite pour coller à leur illustration.
func _god_secondary_color(god: Dictionary, primary: Color) -> Color:
	var value := str(god.get("secondary_color", ""))
	return Color(value) if value != "" else _neon_variant(primary, 1.0)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	_draw_base()
	_draw_side_rails_for_room()
	var full_bleed := room == Room.BOARD or room == Room.PVP
	var scale := _full_bleed_scale_for_size(size) if full_bleed \
		else _artwork_scale_for_size(size)
	var offset := _full_bleed_offset_for_size(size, scale) if full_bleed \
		else _artwork_offset_for_size(size, scale)
	var visible_top := -offset.y / scale
	var visible_bottom := (size.y - offset.y) / scale
	draw_set_transform(offset, 0.0,
		Vector2.ONE * scale)
	match room:
		Room.REFUGE:
			_draw_main_menu()
		Room.ENCOUNTERS:
			_draw_encounters()
		Room.COIN_RITUAL:
			_draw_coin_ritual()
		Room.BOARD:
			_draw_board(visible_top, visible_bottom)
		Room.AFTERMATH:
			_draw_aftermath()
		Room.AFTERMATH_DEFEAT:
			_draw_aftermath_defeat()
		Room.AFTERMATH_DRAW:
			_draw_aftermath_draw()
		Room.PVP:
			_draw_pvp(visible_bottom)
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


## Les salles encadrées par des rails latéraux doivent remplir la largeur.
## Un ajustement "contain" laisse des bandes sur tablette ; l'ajustement par la
## largeur conserve les proportions et ne recadre que le haut/bas du décor.
func _full_bleed_scale_for_size(viewport_size: Vector2) -> float:
	return viewport_size.x / 1080.0


func _full_bleed_offset_for_size(viewport_size: Vector2, scale: float) -> Vector2:
	return Vector2(0.0, (viewport_size.y - 1920.0 * scale) * 0.5)


## Le bestiaire (personnalisation de deck), la campagne, la boutique, le profil
## et les règles partagent le même décor : deux néons verticaux d'un bord à
## l'autre. Dessinés en espace écran, hors de la zone d'artwork, ils couvrent
## toute la hauteur sur les téléphones 20:9 et restent dans la marge extérieure
## des panneaux opaques sur tablette.
func _uses_side_rails() -> bool:
	return room in [Room.BESTIARY, Room.ENCOUNTER_PATH, Room.PROFILE, Room.JOURNAL]


func _draw_side_rails_for_room() -> void:
	if not _uses_side_rails():
		return
	for ratio in [0.022, 0.978]:
		var x := size.x * float(ratio)
		_draw_neon_line(Vector2(x, 0.0), Vector2(x, size.y),
			neon_secondary_color, 2.0, false)


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


func _draw_encounters() -> void:
	var center := Vector2(540.0, 985.0)
	_draw_glow(center, 430.0, neon_primary_color, 0.014)
	_draw_neon_arc(center, 430.0, PI * 1.08, PI * 1.92, neon_secondary_color, 3.0)
	_draw_neon_arc(center, 397.0, PI * 1.10, PI * 1.90, neon_primary_color, 2.0)
	_draw_corner_marks(neon_secondary_color, 48.0, 88.0)


func _draw_coin_ritual() -> void:
	var center := Vector2(540.0, 990.0)
	_draw_glow(center, 900.0, neon_tertiary_color, 0.008)
	_draw_neon_circle(center, 840.0, neon_primary_color, 2.2)
	_draw_neon_circle(center, 630.0, neon_secondary_color, 2.8)
	_draw_neon_circle(center, 420.0, neon_tertiary_color, 3.4)


func _draw_board(visible_top: float = 0.0, visible_bottom: float = 1920.0) -> void:
	var seam := Color(0.72, 0.62, 0.72, 0.075)
	var seam_y := floorf(visible_top / 270.0) * 270.0 + 250.0
	while seam_y < visible_bottom:
		draw_line(Vector2(30.0, seam_y), Vector2(1050.0, seam_y), seam, 2.0)
		seam_y += 270.0
	for x in [270.0, 540.0, 810.0]:
		draw_line(Vector2(x, visible_top), Vector2(x, visible_bottom), seam, 2.0)
	_draw_neon_line(Vector2(18.0, visible_top), Vector2(18.0, visible_bottom),
		neon_primary_color, 1.5)
	_draw_neon_line(Vector2(1062.0, visible_top), Vector2(1062.0, visible_bottom),
		neon_primary_color, 1.5)
	_draw_corner_marks(neon_primary_color, 34.0, 104.0)
	var marker_y := floorf(visible_top / 390.0) * 390.0 + 390.0
	while marker_y < visible_bottom:
		_draw_neon_line(Vector2(18.0, marker_y), Vector2(42.0, marker_y - 22.0),
			neon_secondary_color, 1.0)
		_draw_neon_line(Vector2(1062.0, marker_y), Vector2(1038.0, marker_y - 22.0),
			neon_secondary_color, 1.0)
		marker_y += 390.0


func _draw_aftermath() -> void:
	_draw_firework(Vector2(155.0, 300.0), 175.0, 18, 0.02, 0)
	_draw_firework(Vector2(825.0, 285.0), 205.0, 21, 0.08, 1)
	_draw_firework(Vector2(525.0, 650.0), 125.0, 14, 0.0, 2)
	_draw_firework(Vector2(70.0, 740.0), 92.0, 12, 0.06, 0)
	_draw_firework(Vector2(1010.0, 820.0), 98.0, 13, 0.03, 1)
	_draw_firework(Vector2(170.0, 1030.0), 185.0, 19, 0.04, 1)
	_draw_firework(Vector2(850.0, 1170.0), 170.0, 17, 0.08, 0)
	_draw_firework(Vector2(540.0, 1570.0), 205.0, 22, 0.0, 2)


func _draw_aftermath_defeat() -> void:
	_draw_skull(SKULL_CENTER, neon_primary_color)


func _draw_aftermath_draw() -> void:
	_draw_arena_architecture(neon_primary_color, neon_secondary_color)
	_draw_crossed_swords(Vector2(540.0, 1030.0),
		neon_primary_color, neon_secondary_color)


func _winner_firework_color(index: int) -> Color:
	return _firework_color(neon_primary_color, index)


func _firework_color(base: Color, index: int) -> Color:
	var hue_shifts: Array[float] = [-0.075, -0.04, 0.0, 0.04, 0.075]
	var hue_shift: float = hue_shifts[posmod(index, hue_shifts.size())]
	var hue: float = fposmod(base.h + hue_shift, 1.0)
	var saturation := clampf(base.s * 0.88, 0.55, 1.0)
	var brightness := clampf(base.v + 0.28, 0.0, 1.0)
	return Color.from_hsv(hue, saturation, brightness)


func _draw_firework(center: Vector2, radius: float, ray_count: int,
	phase: float, pattern: int) -> void:
	for ray in range(ray_count):
		var angle := phase + TAU * float(ray) / float(ray_count)
		var length_factor := _firework_length_factor(ray, angle, pattern)
		var ray_length := radius * length_factor
		var fall := ray_length * _firework_fall_factor(pattern)
		var points := _firework_curve_points(center, angle, ray_length, fall, 12)
		var color := _winner_firework_color(ray + pattern * 2)
		var glow := color
		glow.a = 0.14
		draw_polyline(points, glow, 7.0, true)
		var ribbon := _firework_ribbon(points, 3.2)
		color.a = 0.92
		draw_colored_polygon(ribbon, color)
		var finish := points[points.size() - 1]
		draw_circle(finish, maxf(2.0, radius * 0.018), color)
	var core := _winner_firework_color(pattern * 2)
	core.a = 0.9
	draw_circle(center, maxf(3.0, radius * 0.035), core)


func _firework_length_factor(ray: int, angle: float, pattern: int) -> float:
	match pattern % 3:
		0:
			return 0.78 + 0.22 * absf(sin(float(ray) * 1.7))
		1:
			return 0.62 + 0.38 * absf(cos(angle * 2.0))
		_:
			return 0.68 if ray % 2 == 0 else 1.0


func _firework_fall_factor(pattern: int) -> float:
	var fall_factors: Array[float] = [0.20, 0.36, 0.27]
	return fall_factors[posmod(pattern, fall_factors.size())]


func _firework_curve_points(center: Vector2, angle: float, length: float,
	fall: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments + 1):
		var t := float(index) / float(segments)
		var direction := Vector2(cos(angle), sin(angle))
		points.append(center + direction * length * t + Vector2(0.0, fall * t * t))
	return points


func _firework_ribbon(points: PackedVector2Array,
	start_width: float) -> PackedVector2Array:
	var left_edge := PackedVector2Array()
	var right_edge := PackedVector2Array()
	for index in range(points.size()):
		var previous := points[maxi(0, index - 1)]
		var following := points[mini(points.size() - 1, index + 1)]
		var tangent := (following - previous).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var t := float(index) / float(points.size() - 1)
		var half_width := start_width * pow(1.0 - t, 0.72) * 0.5
		left_edge.append(points[index] + normal * half_width)
		right_edge.append(points[index] - normal * half_width)
	right_edge.reverse()
	left_edge.append_array(right_edge)
	return left_edge


func _draw_skull(center: Vector2, color: Color) -> void:
	var outline := PackedVector2Array()
	for index in range(25):
		var angle := PI + PI * float(index) / 24.0
		outline.append(_skull_point(center, Vector2(cos(angle) * 230.0,
			-125.0 + sin(angle) * 250.0)))
	for point in [
		Vector2(212.0, 42.0),
		Vector2(174.0, 145.0),
		Vector2(105.0, 204.0),
		Vector2(80.0, 260.0),
		Vector2(-80.0, 260.0),
		Vector2(-105.0, 204.0),
		Vector2(-174.0, 145.0),
		Vector2(-212.0, 42.0),
	]:
		outline.append(_skull_point(center, point))
	outline.append(outline[0])
	draw_polyline(outline, color, 4.0, true)

	for eye_x in [-105.0, 105.0]:
		var eye_center := _skull_point(center, Vector2(eye_x, -35.0))
		var eye_outline := PackedVector2Array()
		for index in range(25):
			var angle := TAU * float(index) / 24.0
			eye_outline.append(eye_center + Vector2(
				cos(angle) * 68.0 * SKULL_SCALE,
				sin(angle) * 68.0 * SKULL_SCALE))
		eye_outline.append(eye_outline[0])
		draw_colored_polygon(eye_outline.slice(0, -1), Color("#101013"))
		draw_polyline(eye_outline, color, 2.2, true)

	var nose := PackedVector2Array([
		_skull_point(center, Vector2(0.0, 45.0)),
		_skull_point(center, Vector2(-35.0, 112.0)),
		_skull_point(center, Vector2(35.0, 112.0)),
	])
	draw_colored_polygon(nose, Color("#101013"))
	_draw_neon_line(nose[0], nose[1], color, 1.8)
	_draw_neon_line(nose[1], nose[2], color, 1.8)
	_draw_neon_line(nose[2], nose[0], color, 1.8)
	_draw_neon_line(_skull_point(center, Vector2(-142.0, 142.0)),
		_skull_point(center, Vector2(142.0, 142.0)), color, 2.0)
	for tooth in range(7):
		var x := -105.0 + float(tooth) * 35.0
		_draw_neon_line(_skull_point(center, Vector2(x, 142.0)),
			_skull_point(center, Vector2(x, 190.0 if tooth % 2 == 0 else 176.0)),
			color, 1.2)


func _skull_point(center: Vector2, point: Vector2) -> Vector2:
	return center + point * SKULL_SCALE


## Le choix, la recherche et la salle partagent le même décor d'arène.
func _draw_pvp(visible_bottom: float = PVP_ARCH_BOTTOM) -> void:
	_draw_arena_architecture(neon_primary_color, neon_secondary_color,
		maxf(PVP_ARCH_BOTTOM, visible_bottom))
	_draw_crossed_swords(Vector2(540.0, 1030.0),
		neon_primary_color, neon_secondary_color)


func _draw_arena_architecture(outer_accent: Color, inner_accent: Color,
	bottom: float = PVP_ARCH_BOTTOM) -> void:
	var center := Vector2(540.0, 820.0)
	_draw_arena_arch(center, 510.0, bottom, Color("#1a171d"))
	_draw_arena_arch(center, 405.0, bottom, Color("#111014"))
	_draw_arch_outline(center, 510.0, outer_accent, 2.2, bottom)
	_draw_arch_outline(center, 405.0, inner_accent, 1.2, bottom)
	_draw_arch_keystone(center, outer_accent)
	_draw_arena_floor(outer_accent, bottom)


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


func _draw_arch_outline(center: Vector2, radius: float, color: Color,
		width: float, bottom: float = PVP_ARCH_BOTTOM) -> void:
	_draw_neon_arc(center, radius, PI, TAU, color, width)
	_draw_neon_line(Vector2(center.x - radius, center.y),
		Vector2(center.x - radius, bottom), color, width)
	_draw_neon_line(Vector2(center.x + radius, center.y),
		Vector2(center.x + radius, bottom), color, width)


func _draw_arch_keystone(center: Vector2, color: Color) -> void:
	var stone := PackedVector2Array([
		Vector2(center.x - 26.0, center.y - 494.0),
		Vector2(center.x, center.y - 526.0),
		Vector2(center.x + 26.0, center.y - 494.0),
	])
	draw_colored_polygon(stone, Color("#322b34"))
	_draw_neon_line(stone[0], stone[1], color, 1.4)
	_draw_neon_line(stone[1], stone[2], color, 1.4)


func _draw_arena_floor(accent: Color, bottom: float = PVP_ARCH_BOTTOM) -> void:
	var seam := Color("#a49aa5")
	seam.a = 0.11
	for y in [1530.0, 1640.0, 1740.0]:
		draw_line(Vector2(80.0, y), Vector2(1000.0, y), seam, 2.0)
	for x in [220.0, 390.0, 690.0, 860.0]:
		draw_line(Vector2(540.0, 1410.0), Vector2(x, bottom), seam, 2.0)
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


func _draw_neon_line(from: Vector2, to: Vector2, color: Color, width: float = 2.0,
		scale_by_room: bool = true) -> void:
	if scale_by_room:
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
