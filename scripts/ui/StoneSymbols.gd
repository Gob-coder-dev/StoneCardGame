## Dessin partagé des pouvoirs : cartes, légendes des règles et animations.
## Aucun tirage ni état de combat n'est modifié par ce composant.
extends RefCounted

const Effects := preload("res://scripts/domain/StoneEffects.gd")
const Weakness := preload("res://scripts/engine/effects/WeaknessSystem.gd")

const FORTUNE := Color("#ff55c8")
const SHIELD := Color("#92e7f2")
const LONG := Color("#4fa9ff")
const SWARM := Color("#83d85d")
const THEFT := Color("#ef8b45")
const GOLD := Color("#ffe9a8")


static func badges_for(stone: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := int(stone.get("random_blades", 0))
	if count > 0:
		result.append({"kind": "fortune", "count": count})
	var axis := str(stone.get("coin_flip", ""))
	if axis != "":
		result.append({"kind": "coin_" + axis})
	if _sum(stone.get("shields", {})) > 0:
		result.append({"kind": "shield"})
	if _sum(stone.get("long_blades", {})) > 0:
		result.append({"kind": "long"})
	for effect in stone.get("effects", []):
		match str(effect):
			Effects.WEAKEN_ON_FAILED_ATTACK: result.append({"kind": "weaken_miss"})
			Effects.WEAKEN_ADJACENT: result.append({"kind": "weaken_adjacent"})
			Effects.SWARM: result.append({"kind": "swarm"})
			Effects.SHIELD_THEFT: result.append({"kind": "theft"})
	return result


static func badge_width(radius: float, count: int = 0) -> float:
	if count <= 0:
		return radius * 2.0
	# Un petit espace fixe après le dessin, puis la vraie largeur du texte.
	# Les proportions seules éloignaient trop le compteur sur les petites cartes.
	return radius * 2.03 + _counter_size(radius, count).x


static func _counter_size(radius: float, count: int) -> Vector2:
	var font_size := maxi(8, int(radius * 0.82 * 1.45))
	return ThemeDB.fallback_font.get_string_size("×%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)


## center désigne le centre du pictogramme ; le compteur s'étend à droite.
static func draw_badge(canvas: CanvasItem, center: Vector2, radius: float, kind: String, color: Color, count: int = 0) -> void:
	var extra := badge_width(radius, count) - radius * 2.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#20152df5")
	box.border_color = color.lightened(0.22)
	box.set_border_width_all(maxi(1, int(radius * 0.13)))
	box.set_corner_radius_all(int(radius))
	canvas.draw_style_box(box, Rect2(center - Vector2.ONE * radius, Vector2(radius * 2.0 + extra, radius * 2.0)))
	draw_icon(canvas, center, radius * 0.64, kind)
	if count > 0:
		var text_center := center + Vector2(radius * 0.78 + _counter_size(radius, count).x * 0.5, 0)
		draw_text(canvas, text_center, radius * 0.82, "×%d" % count, Color.WHITE)


static func draw_icon(canvas: CanvasItem, center: Vector2, radius: float, kind: String) -> void:
	var line_width := maxf(1.2, radius * 0.20)
	match kind:
		"fortune":
			for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				var tangent := Vector2(-direction.y, direction.x)
				canvas.draw_colored_polygon(PackedVector2Array([
					center + direction * radius,
					center + direction * radius * 0.18 + tangent * radius * 0.28,
					center + direction * radius * 0.18 - tangent * radius * 0.28
				]), FORTUNE)
			canvas.draw_circle(center, radius * 0.22, Color.WHITE)
		"coin_horizontal", "coin_vertical":
			canvas.draw_circle(center, radius * 0.94, GOLD)
			var axis := Vector2.RIGHT if kind == "coin_horizontal" else Vector2.UP
			var tangent := Vector2(-axis.y, axis.x)
			var ink := Color("#602862")
			canvas.draw_line(center - axis * radius * 0.72, center + axis * radius * 0.72, ink, line_width)
			for sign_value in [-1.0, 1.0]:
				var tip: Vector2 = center + axis * radius * 0.72 * sign_value
				for direction in [-1.0, 1.0]:
					canvas.draw_line(tip, tip - axis * radius * 0.38 * sign_value + tangent * radius * 0.30 * direction, ink, line_width)
		"shield":
			draw_shield(canvas, center + Vector2(0, radius * 0.52), radius * 1.9, radius * 1.2, Vector2.UP, SHIELD)
		"long":
			var points := PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(radius * 0.54, radius * 0.78),
				center + Vector2(-radius * 0.54, radius * 0.78)
			])
			canvas.draw_colored_polygon(points, LONG)
			var inner := PackedVector2Array()
			for point in points:
				inner.append(point.lerp(center, 0.38))
			canvas.draw_colored_polygon(inner, GOLD)
		"weaken_miss":
			draw_text(canvas, center, radius, "-%d" % Weakness.CORROSION_AMOUNT, Color("#e889d4"))
		"weaken_adjacent":
			canvas.draw_circle(center, radius * 0.25, Color("#e889d4"))
			for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				canvas.draw_line(center + direction * radius * 0.30, center + direction * radius * 0.70, Color("#e889d4"), line_width)
				canvas.draw_circle(center + direction * radius * 0.82, radius * 0.16, Color("#e889d4"))
		"swarm":
			var points := [center + Vector2(0, -radius * 0.62), center + Vector2(-radius * 0.62, radius * 0.48), center + Vector2(radius * 0.62, radius * 0.48)]
			for i in range(points.size()):
				canvas.draw_line(points[i], points[(i + 1) % points.size()], SWARM, line_width)
				canvas.draw_circle(points[i], radius * 0.25, SWARM)
		"theft":
			canvas.draw_arc(center, radius * 0.72, 0.0, TAU, 20, THEFT, line_width)
			canvas.draw_line(center + Vector2(-radius * 0.42, 0), center + Vector2(radius * 0.42, 0), Color.WHITE, line_width)
			canvas.draw_line(center + Vector2(0, -radius * 0.42), center + Vector2(0, radius * 0.42), Color.WHITE, line_width)


## Demi-disque tourné vers l'extérieur, base plate contre le cadre.
static func draw_shield(canvas: CanvasItem, base: Vector2, width: float, height: float, outward: Vector2, color: Color) -> void:
	var tangent := Vector2(-outward.y, outward.x)
	var points := PackedVector2Array()
	for i in range(17):
		var angle := PI * float(i) / 16.0
		points.append(base + tangent * cos(angle) * width * 0.5 + outward * sin(angle) * height)
	canvas.draw_colored_polygon(points, color.darkened(0.70))
	points.append(points[0])
	canvas.draw_polyline(points, color, maxf(1.5, width * 0.12), true)


static func draw_text(canvas: CanvasItem, center: Vector2, radius: float, value: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var font_size := maxi(8, int(radius * 1.45))
	var text_size := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	canvas.draw_string(font, center + Vector2(-text_size.x * 0.5, font.get_ascent(font_size) * 0.5 - font.get_descent(font_size) * 0.5), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


static func _sum(values: Dictionary) -> int:
	var total := 0
	for value in values.values():
		total += int(value)
	return total
