## Révèle les lames aléatoires vers les faces déjà choisies par le moteur.
extends "res://scripts/ui/combat/animations/CardRevealAnimation.gd"
var _targets: Array[Vector2] = []

func play(card: StoneCard, events: Array, duration: float) -> void:
	_prepare(card)
	var preview: BattleStoneModel = card.get_battle_stone().clone()
	var seen := {}
	for event in events:
		var side := str(event["side"])
		var index := preview.marker_offset("random", side) + int(seen.get(side, 0))
		_targets.append(_card_transform * card.marker_position(side, index))
		seen[side] = int(seen.get(side, 0)) + 1
	for side in StoneSide.ALL:
		preview.random_blades[side] = 0
	card.set_combat_preview(preview)
	_start(duration)

func _draw() -> void:
	if is_instance_valid(_card):
		_draw_spiral(progress)

func _spiral_position(value: float, index: int) -> Vector2:
	var phase := TAU * float(index) / float(maxi(1, _targets.size()))
	var angle := value * TAU * 2.2 + phase
	var radius := _square * (0.33 - value * 0.09)
	var orbit := _center + Vector2(cos(angle), sin(angle)) * radius
	var landing_start := 0.64 + float(index) / float(maxi(1, _targets.size())) * 0.14
	var landing := smoothstep(landing_start, 0.97, value)
	return orbit.lerp(_targets[index], landing)

func _draw_spiral(value: float) -> void:
	var color := Symbols.FORTUNE
	for index in range(_targets.size()):
		# Traînée contrastée, puis symbole opaque au premier plan.
		for trail in range(1, 9):
			var previous := maxf(0.0, value - float(trail) * 0.012)
			var point := _spiral_position(previous, index)
			var trail_color := color.lerp(Color("#8d43ff"), float(trail) / 9.0)
			trail_color.a = 0.75 * (1.0 - float(trail) / 10.0)
			draw_circle(point, _square * (0.025 - trail * 0.0016), trail_color)
		var point := _spiral_position(value, index)
		var symbol_size := _square * 0.062
		draw_circle(point, symbol_size * 0.88, Color("#29142bba"))
		var direction := (point - _center).normalized()
		var tangent := Vector2(-direction.y, direction.x)
		var points := PackedVector2Array([
			point + direction * symbol_size,
			point - direction * symbol_size * 0.65 + tangent * symbol_size * 0.65,
			point - direction * symbol_size * 0.65 - tangent * symbol_size * 0.65
		])
		draw_colored_polygon(points, color)
		points.append(points[0])
		draw_polyline(points, Color.WHITE, maxf(1.5, _square * 0.008), true)
		draw_circle(point, symbol_size * 0.19, Color.WHITE)
