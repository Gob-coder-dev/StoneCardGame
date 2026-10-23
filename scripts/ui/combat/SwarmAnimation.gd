## Révélation visuelle des groupes Essaim. Le résolveur fournit les réseaux et
## les lames avant/après ; cette vue masque le résultat, anime sa transition,
## puis rend la main à l'état réel sans modifier le gameplay.
extends Control

signal reveal_finished
signal transition_started

const VineStyle := preload("res://scripts/ui/combat/SwarmVineStyle.gd")
const AURA := Color("#83d85d")
const AURA_BRIGHT := Color("#dcff9d")
const AURA_DARK := Color("#245b39")
const BREAK_COLOR := Color("#9bb47c")

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		_update_members()
		queue_redraw()

var _members: Array = []
var _links_before: Array = []
var _links_after: Array = []
var _before_keys := {}
var _after_keys := {}
var _source_center := Vector2.ZERO
var _base_square: float = 100.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 19


func play(members: Array, links_before: Array, links_after: Array,
	source_center: Vector2, duration: float, delay: float = 0.0) -> void:
	_members = members
	_links_before = links_before
	_links_after = links_after
	_source_center = source_center
	for link in _links_before:
		_before_keys[str(link.get("key", ""))] = true
	for link in _links_after:
		_after_keys[str(link.get("key", ""))] = true
	var max_distance := 1.0
	if not _members.is_empty():
		_base_square = float(_members[0].get("square", 100.0))
	for member in _members:
		max_distance = maxf(max_distance,
			_source_center.distance_to(member.get("center", _source_center)))
	for member in _members:
		var distance: float = _source_center.distance_to(member.get("center", _source_center))
		member["arrival"] = 0.46 + distance / max_distance * 0.13
		member["showing_after"] = false
		var card: StoneCard = member.get("card")
		if is_instance_valid(card):
			card.set_combat_preview(_preview_with_swarm(card, member.get("before", {})))
	_update_members()
	var tween := create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_callback(_begin_transition)
	tween.tween_property(self, "progress", 1.0, maxf(0.1, duration))
	tween.tween_callback(_finish)


func _begin_transition() -> void:
	transition_started.emit()


func _preview_with_swarm(card: StoneCard, blades: Dictionary):
	var stone = card.get_battle_stone()
	if stone == null:
		return null
	var preview = stone.clone()
	preview.swarm_blades = _complete_side_map(blades)
	return preview


func _update_members() -> void:
	for member in _members:
		var card: StoneCard = member.get("card")
		if not is_instance_valid(card):
			continue
		var before: Dictionary = member.get("before", {})
		var after: Dictionary = member.get("after", {})
		var arrival := float(member.get("arrival", 0.52))
		if progress < arrival:
			var retract := smoothstep(0.04, 0.28, progress)
			for side in BattleStone.SIDES:
				var before_count := int(before.get(side, 0))
				var after_count := int(after.get(side, 0))
				for swarm_index in range(after_count, before_count):
					card.set_marker_growth(side,
						_swarm_marker_start(card, side) + swarm_index, 1.0 - retract)
			continue
		if not bool(member.get("showing_after", false)):
			card.clear_marker_growth()
			card.set_combat_preview(_preview_with_swarm(card, after))
			member["showing_after"] = true
		var growth_time := clampf(inverse_lerp(arrival, minf(0.88, arrival + 0.22), progress), 0.0, 1.0)
		var growth := _growth_with_bounce(growth_time)
		for side in BattleStone.SIDES:
			var before_count := int(before.get(side, 0))
			var after_count := int(after.get(side, 0))
			for swarm_index in range(before_count, after_count):
				card.set_marker_growth(side,
					_swarm_marker_start(card, side) + swarm_index, growth)


func _swarm_marker_start(card: StoneCard, side: String) -> int:
	var stone = card.get_battle_stone()
	if stone == null:
		return 0
	return int(stone.base_blades.get(side, 0)) + int(stone.random_blades.get(side, 0))


func _growth_with_bounce(value: float) -> float:
	if value < 0.72:
		return value / 0.72 * 1.12
	return lerpf(1.12, 1.0, smoothstep(0.72, 1.0, value))


func _finish() -> void:
	_restore_cards()
	reveal_finished.emit()
	queue_free()


func _exit_tree() -> void:
	_restore_cards()


func _restore_cards() -> void:
	for member in _members:
		var card: StoneCard = member.get("card")
		if is_instance_valid(card):
			card.clear_marker_growth()
			card.set_combat_preview(null)


func _draw() -> void:
	if progress <= 0.0:
		return
	_draw_broken_links()
	_draw_living_links()
	_draw_source_pulse()
	_draw_member_pulses()


func _draw_broken_links() -> void:
	var break_value := clampf(inverse_lerp(0.02, 0.36, progress), 0.0, 1.0)
	if break_value >= 1.0:
		return
	for link in _links_before:
		if _after_keys.has(str(link.get("key", ""))):
			continue
		var start: Vector2 = link["start"]
		var end: Vector2 = link["end"]
		var middle := start.lerp(end, 0.5)
		var first_end := middle.lerp(start, break_value * 0.72)
		var second_start := middle.lerp(end, break_value * 0.72)
		var fade := 1.0 - break_value
		var seed := absi(hash(str(link.get("key", "")))) % 97
		VineStyle.draw_vine(self, start, first_end, _base_square,
			fade, seed, progress * 7.0, true)
		VineStyle.draw_vine(self, second_start, end, _base_square,
			fade, seed + 3, -progress * 7.0, true)
		var normal := (end - start).normalized()
		var tangent := Vector2(-normal.y, normal.x)
		var crack := PackedVector2Array([
			middle - normal * _base_square * 0.055,
			middle + tangent * _base_square * 0.040,
			middle - tangent * _base_square * 0.035,
			middle + normal * _base_square * 0.055
		])
		draw_polyline(crack, Color(AURA_BRIGHT, fade),
			maxf(2.0, _base_square * 0.018), true)
		draw_circle(first_end, _base_square * 0.018, Color(AURA_BRIGHT, 0.82 * fade))
		draw_circle(second_start, _base_square * 0.018, Color(AURA_BRIGHT, 0.82 * fade))
		for cut in [{"point": first_end, "direction": normal},
			{"point": second_start, "direction": -normal}]:
			for fiber in range(3):
				var side := -1.0 if fiber % 2 == 0 else 1.0
				var fiber_end: Vector2 = cut["point"] + cut["direction"] * _base_square * (0.022 + fiber * 0.007) \
					+ tangent * side * _base_square * (0.012 + fiber * 0.006)
				draw_line(cut["point"], fiber_end, Color(BREAK_COLOR, 0.78 * fade),
					maxf(1.0, _base_square * 0.007), true)
		var flash := 1.0 - smoothstep(0.02, 0.18, progress)
		if flash > 0.0:
			draw_arc(middle, _base_square * lerpf(0.025, 0.075, 1.0 - flash),
				0.0, TAU, 18, Color(AURA_BRIGHT, flash),
				maxf(1.5, _base_square * 0.012), true)


func _draw_living_links() -> void:
	var reveal := smoothstep(0.16, 0.42, progress)
	if reveal <= 0.0:
		return
	for index in range(_links_after.size()):
		var link: Dictionary = _links_after[index]
		var start: Vector2 = link["start"]
		var end: Vector2 = link["end"]
		if start.distance_squared_to(_source_center) > end.distance_squared_to(_source_center):
			var swap := start
			start = end
			end = swap
		var seed := absi(hash(str(link.get("key", index)))) % 97
		var points := VineStyle.draw_vine(self, start, end, _base_square,
			reveal, seed, progress * 8.0, true)
		_draw_link_impulse(points, index)


func _draw_link_impulse(points: PackedVector2Array, index: int) -> void:
	var travel := clampf(inverse_lerp(0.22, 0.70, progress), 0.0, 1.0)
	if travel <= 0.0 or travel >= 1.0:
		return
	var scaled := travel * float(points.size() - 1)
	var point_index := mini(points.size() - 2, int(floor(scaled)))
	var head := points[point_index].lerp(points[point_index + 1], scaled - point_index)
	for trail in range(5, -1, -1):
		var distance := _base_square * float(trail) * 0.026
		var direction := (points[0] - points[-1]).normalized()
		var weight := 1.0 - float(trail) / 6.0
		draw_circle(head + direction * distance, _base_square * (0.012 + weight * 0.018),
			Color(AURA_BRIGHT, weight * 0.76))
	draw_circle(head, _base_square * 0.035, Color(AURA_BRIGHT, 0.92))


func _draw_source_pulse() -> void:
	var strength := smoothstep(0.02, 0.16, progress) * (1.0 - smoothstep(0.42, 0.68, progress))
	if strength <= 0.0:
		return
	var radius := _base_square * lerpf(0.15, 0.30, smoothstep(0.0, 0.55, progress))
	draw_arc(_source_center, radius, 0.0, TAU, 32, Color(AURA_BRIGHT, strength),
		maxf(2.0, _base_square * 0.018), true)
	var node_radius := _base_square * 0.025
	var nodes := [
		_source_center + Vector2(0.0, -_base_square * 0.075),
		_source_center + Vector2(-_base_square * 0.070, _base_square * 0.050),
		_source_center + Vector2(_base_square * 0.070, _base_square * 0.050)
	]
	for first in range(nodes.size()):
		draw_line(nodes[first], nodes[(first + 1) % nodes.size()],
			Color(AURA, strength), maxf(2.0, _base_square * 0.014), true)
		draw_circle(nodes[first], node_radius, Color(AURA_BRIGHT, strength))


func _draw_member_pulses() -> void:
	for member in _members:
		var arrival := float(member.get("arrival", 0.52))
		var age := progress - arrival
		if age < 0.0 or age > 0.28:
			continue
		var fade := 1.0 - age / 0.28
		var square := float(member.get("square", _base_square))
		var center: Vector2 = member["center"]
		var radius := square * (0.18 + age * 0.62)
		draw_arc(center, radius, 0.0, TAU, 28, Color(AURA_BRIGHT, fade),
			maxf(2.0, square * 0.018), true)
		for particle in range(6):
			var direction := Vector2.from_angle(TAU * float(particle) / 6.0 + age * 5.0)
			draw_circle(center + direction * radius, square * 0.014, Color(AURA, fade * 0.76))


func _complete_side_map(source: Dictionary) -> Dictionary:
	var result := {}
	for side in BattleStone.SIDES:
		result[side] = int(source.get(side, 0))
	return result
