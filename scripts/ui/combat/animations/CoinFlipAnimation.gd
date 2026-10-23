## Pièce superposée : le moteur a déjà décidé si les faces s'échangent.
extends "res://scripts/ui/combat/animations/CardRevealAnimation.gd"
const COIN_RESULT := 0.62
const COIN_REVEAL := 0.76
var _axis: String = ""
var _flipped: bool = false

func play(card: StoneCard, event: Dictionary, duration: float) -> void:
	_prepare(card)
	_axis = event["axis"]
	_flipped = event["flipped"]
	var preview: BattleStoneModel = card.get_battle_stone().clone()
	if _flipped:
		preview.swap_faces("left" if _axis == "horizontal" else "top", "right" if _axis == "horizontal" else "bottom")
	card.set_combat_preview(preview)
	_start(duration)

func _update_preview() -> void:
	if is_instance_valid(_card) and progress >= COIN_REVEAL:
		_card.set_combat_preview(null)

func _draw() -> void:
	if is_instance_valid(_card):
		_draw_coin()

func _draw_coin() -> void:
	var tossing := progress < COIN_RESULT
	var toss := clampf(progress / COIN_RESULT, 0.0, 1.0)
	var radius := _square * 0.20
	var center := _center - Vector2(0, sin(toss * PI) * _square * 0.16)
	var flatten := maxf(0.10, absf(cos(toss * TAU * 2.0))) if tossing else 1.0
	var points := PackedVector2Array()
	for i in range(49):
		var angle := TAU * float(i) / 48.0
		points.append(center + Vector2(cos(angle) * radius * flatten, sin(angle) * radius))
	draw_circle(center + Vector2(0, radius * 0.12), radius * 1.06, Color("#29142bc0"))
	draw_colored_polygon(points, Color("#ffce55"))
	points.append(points[0])
	draw_polyline(points, Color("#fff0b8"), maxf(2.0, _square * 0.013), true)
	if tossing:
		if flatten > 0.45:
			Symbols.draw_icon(self, center, radius * 0.58 * flatten, "coin_" + _axis)
	else:
		var ink := Color("#267443") if _flipped else Color("#852d42")
		var width := maxf(3.0, radius * 0.15)
		if _flipped:
			draw_polyline(PackedVector2Array([center + Vector2(-0.48, 0.0) * radius,
				center + Vector2(-0.10, 0.35) * radius,
				center + Vector2(0.52, -0.40) * radius]), ink, width, true)
		else:
			draw_line(center + Vector2(-0.36, -0.36) * radius, center + Vector2(0.36, 0.36) * radius, ink, width, true)
			draw_line(center + Vector2(-0.36, 0.36) * radius, center + Vector2(0.36, -0.36) * radius, ink, width, true)
		_draw_caption(("ÉCHANGE ↔" if _axis == "horizontal" else "ÉCHANGE ↕") if _flipped else "INCHANGÉ", Color("#ffe9a8"))
		if _flipped and progress >= COIN_REVEAL:
			var sides := ["left", "right"] if _axis == "horizontal" else ["top", "bottom"]
			for side in sides:
				var point := _card_transform * _card.marker_position(side)
				draw_arc(point, _square * 0.075, 0.0, TAU, 24, Color("#fff0b8"), maxf(2.0, _square * 0.012), true)
