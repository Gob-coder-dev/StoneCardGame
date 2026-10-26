## Sceau purement visuel d'une case interdite.
## Toute la géométrie est proportionnelle à la case : aucun glyphe ni taille de
## police ne peut devenir illisible sur un téléphone ou démesuré sur une tablette.
class_name BlockedCellOverlay
extends Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 0.0:
		return
	var origin := (size - Vector2.ONE * side) * 0.5
	var bounds := Rect2(origin + Vector2.ONE * side * 0.08, Vector2.ONE * side * 0.84)

	# Entailles obliques : elles distinguent la case d'une simple case sombre,
	# même quand une partie de la grande croix est cachée par un doigt.
	var hatch := Color(UITheme.COL_BOARD_BLOCKED_SHADOW, 0.34)
	var hatch_width := maxf(1.5, side * 0.018)
	for segment in [
		[Vector2(0.10, 0.32), Vector2(0.32, 0.10)],
		[Vector2(0.68, 0.10), Vector2(0.90, 0.32)],
		[Vector2(0.10, 0.68), Vector2(0.32, 0.90)],
		[Vector2(0.68, 0.90), Vector2(0.90, 0.68)],
		[Vector2(0.08, 0.50), Vector2(0.22, 0.36)],
		[Vector2(0.78, 0.64), Vector2(0.92, 0.50)]
	]:
		draw_line(origin + segment[0] * side, origin + segment[1] * side,
			hatch, hatch_width, true)

	var a := bounds.position + bounds.size * 0.18
	var b := bounds.end - bounds.size * 0.18
	var c := Vector2(b.x, a.y)
	var d := Vector2(a.x, b.y)
	var shadow_width := maxf(8.0, side * 0.115)
	var mark_width := maxf(5.0, side * 0.068)
	_draw_rounded_stroke(a, b, UITheme.COL_BOARD_BLOCKED_SHADOW, shadow_width)
	_draw_rounded_stroke(c, d, UITheme.COL_BOARD_BLOCKED_SHADOW, shadow_width)
	_draw_rounded_stroke(a, b, UITheme.COL_BOARD_BLOCKED_MARK, mark_width)
	_draw_rounded_stroke(c, d, UITheme.COL_BOARD_BLOCKED_MARK, mark_width)


func _draw_rounded_stroke(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(from, to, color, width, true)
	draw_circle(from, width * 0.5, color)
	draw_circle(to, width * 0.5, color)
