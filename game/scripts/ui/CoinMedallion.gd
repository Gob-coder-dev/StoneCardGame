extends Panel


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.42
	draw_circle(center + Vector2(0.0, radius * 0.09), radius, Color("#100d12"))
	draw_circle(center, radius, Color("#bd8050"))
	draw_circle(center, radius * 0.87, Color("#49342c"))

	draw_arc(center, radius * 0.94, PI * 1.08, PI * 1.92, 48,
		Color("#f2c08a"), 2.5, true)
	draw_arc(center, radius * 0.94, PI * 0.08, PI * 0.92, 48,
		Color("#6d4436"), 3.0, true)
	draw_arc(center, radius * 0.82, 0.0, TAU, 48, Color("#8c6044"), 1.5, true)

	for notch in range(24):
		var angle := TAU * float(notch) / 24.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * radius * 0.94,
			center + direction * radius * 0.99, Color("#704735"), 1.6, true)

	for side in [-1.0, 1.0]:
		var mark_center := center + Vector2(radius * 0.60 * side, 0.0)
		var star_radius := radius * 0.065
		var mark := PackedVector2Array([
			mark_center + Vector2(0.0, -star_radius),
			mark_center + Vector2(star_radius * 0.34, -star_radius * 0.34),
			mark_center + Vector2(star_radius, 0.0),
			mark_center + Vector2(star_radius * 0.34, star_radius * 0.34),
			mark_center + Vector2(0.0, star_radius),
			mark_center + Vector2(-star_radius * 0.34, star_radius * 0.34),
			mark_center + Vector2(-star_radius, 0.0),
			mark_center + Vector2(-star_radius * 0.34, -star_radius * 0.34),
		])
		draw_colored_polygon(mark, Color("#d6ae78"))
