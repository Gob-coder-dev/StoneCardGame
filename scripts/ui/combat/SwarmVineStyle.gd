## Style procédural partagé par les lianes persistantes et leur animation.
## Plusieurs lianes indépendantes relient des points répartis sur toute la
## largeur des deux bords. Leurs destinations mélangées créent les croisements.
extends RefCounted

const VINE := Color("#83d85d")
const VINE_BRIGHT := Color("#dcff9d")
const VINE_DARK := Color("#173b26")


const STRAND_COUNT := 9
const ANCHOR_SPAN := 0.29


static func curve_points(start: Vector2, finish: Vector2, square: float,
	seed: int = 0, phase: float = 0.0) -> PackedVector2Array:
	var direction := (finish - start).normalized()
	var tangent := Vector2(-direction.y, direction.x)
	var points := PackedVector2Array()
	for step in range(17):
		var value := float(step) / 16.0
		# L'enveloppe maintient exactement les points d'ancrage sur les cartes.
		# Les deux fréquences évitent des traits trop droits sans former un câble.
		var envelope := sin(value * PI)
		var wave := sin(value * TAU * 1.35 + float(seed) * 1.17 + phase) * square * 0.011
		wave += sin(value * TAU * 2.8 + float(seed) * 0.63 - phase * 0.28) * square * 0.004
		points.append(start.lerp(finish, value) + tangent * wave * envelope)
	return points


static func _anchor_offset(index: int, count: int, square: float, seed: int) -> float:
	var ratio := float(index) / float(count - 1)
	# Un très léger décalage déterministe casse la régularité des ancrages tout
	# en les gardant répartis sur presque toute la face de la pierre.
	var jitter := sin(float(seed * 13 + index * 19)) * square * 0.012
	return lerpf(-square * ANCHOR_SPAN, square * ANCHOR_SPAN, ratio) + jitter


static func draw_vine(canvas: CanvasItem, start: Vector2, finish: Vector2,
	square: float, opacity: float, seed: int = 0, phase: float = 0.0,
	energized: bool = false) -> PackedVector2Array:
	var strength := clampf(opacity, 0.0, 1.0)
	var direction := (finish - start).normalized()
	var tangent := Vector2(-direction.y, direction.x)
	var main := PackedVector2Array()
	var permutation_shift := posmod(seed, STRAND_COUNT)
	for strand_index in range(STRAND_COUNT):
		# Multiplier par 4 (premier avec 9) distribue toutes les arrivées sans
		# doublon. Chaque liane traverse ainsi librement les autres dans l'espace.
		var end_index := posmod(strand_index * 4 + permutation_shift, STRAND_COUNT)
		var strand_start := start + tangent * _anchor_offset(
			strand_index, STRAND_COUNT, square, seed)
		var strand_finish := finish + tangent * _anchor_offset(
			end_index, STRAND_COUNT, square, seed + 37)
		var points := curve_points(strand_start, strand_finish, square,
			seed + strand_index * 11, phase * (0.70 + float(strand_index) * 0.055))
		if strand_index == STRAND_COUNT / 2:
			main = points
		var ratio := float(strand_index) / float(STRAND_COUNT - 1)
		var width := maxf(1.3, square * (0.0200 + float(strand_index % 3) * 0.0015))
		var vine_color := VINE_DARK.lerp(VINE, 0.75 + ratio * 0.24)
		vine_color.a = (0.62 + float(strand_index % 2) * 0.10) * strength
		canvas.draw_polyline(points, Color(VINE_DARK, 0.30 * strength),
			width + maxf(1.0, square * 0.005), true)
		canvas.draw_polyline(points, vine_color, width, true)
		if energized and strand_index % 2 == 0:
			canvas.draw_polyline(points, Color(VINE_BRIGHT, 0.32 * strength),
				maxf(0.8, square * 0.003), true)
	return main
