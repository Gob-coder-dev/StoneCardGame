## Projectiles et impacts provenant exclusivement du compte rendu du moteur.
## La couleur de capture peut être révélée à l'impact ; le GameState reste intact.
extends Control

signal reveal_finished

signal target_hit(row: int, col: int, success: bool, owner: int)

const Timeline := preload("res://scripts/ui/combat/CombatTimeline.gd")
const Symbols := preload("res://scripts/ui/StoneSymbols.gd")

var elapsed: float = 0.0:
	set(value):
		elapsed = value
		_update_reveal()
		queue_redraw()

var _card: StoneCard
var _owner: int = 0
var _square: float = 0.0
var _flight_end: float = 0.0
var _projectiles: Array = []
var _impacts: Array = []
const BARRIER_OFFSET: float = 0.07
const IMPACT_LIFETIME: float = 0.28


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10


## paths contient les coordonnées calculées par BoardView dans son repère.
func play(card: StoneCard, paths: Array, attacks: Array, owner: int, duration: float) -> void:
	_card = card
	_owner = owner
	_square = minf(card.size.x, card.size.y)
	_flight_end = Timeline.flight_end(attacks)
	card.start_attack_animation(attacks)
	for path in paths:
		_build_projectiles(path)
	var tween := create_tween()
	tween.tween_property(self, "elapsed", duration, duration)
	tween.tween_callback(_finish)


func _build_projectiles(path: Dictionary) -> void:
	var attack: Dictionary = path["attack"]
	var direction: Vector2 = path["direction"]
	var hits: Array = path["hits"]
	for hit in hits:
		var impact: Dictionary = hit.duplicate()
		if not bool(hit["success"]):
			impact["point"] = _barrier_point(hit["point"], direction)
		impact["time"] = Timeline.hit_time(int(hit["distance"]))
		impact["direction"] = direction
		impact["emitted"] = false
		impact["blocked"] = false
		impact["blue"] = int(attack["long_count"]) > 0
		_impacts.append(impact)
	if attack["endpoint"]["type"] == "blocked":
		_impacts.append({"point": _barrier_point(path["end"], direction), "time": Timeline.hit_time(int(attack["endpoint"]["distance"])),
			"direction": direction, "success": false, "emitted": false, "blocked": true, "blue": true})
	for marker in path["markers"]:
		var is_long: bool = marker["kind"] == "long"
		var start: Vector2 = marker["position"]
		var offset: Vector2 = start - path["source_face"]
		offset -= direction * offset.dot(direction)
		var stops: Array = [{"time": Timeline.WINDUP, "point": start}]
		for hit in hits:
			var hit_point: Vector2 = hit["point"]
			if not bool(hit["success"]):
				hit_point = _barrier_point(hit_point, direction)
			stops.append({"time": Timeline.hit_time(int(hit["distance"])), "point": hit_point + offset})
			if not is_long:
				break
		var endpoint: Dictionary = attack["endpoint"]
		if is_long and endpoint["type"] != "enemy":
			var endpoint_position: Vector2 = path["end"]
			if endpoint["type"] == "blocked":
				endpoint_position = _barrier_point(endpoint_position, direction)
			stops.append({"time": Timeline.hit_time(int(endpoint["distance"])), "point": endpoint_position + offset})
		var failed: bool = not bool(hits[-1]["success"]) or endpoint["type"] == "blocked"
		if not is_long:
			failed = not bool(hits[0]["success"])
		_projectiles.append({"kind": marker["kind"], "direction": direction, "stops": stops,
			"failed": failed, "exit": is_long and endpoint["type"] == "exit", "index": _projectiles.size()})


func _barrier_point(target_face: Vector2, direction: Vector2) -> Vector2:
	return target_face - direction * _square * BARRIER_OFFSET


func _update_reveal() -> void:
	if not is_instance_valid(_card):
		return
	if elapsed < Timeline.WINDUP:
		_card.attack_regrowth = 1.0 - elapsed / Timeline.WINDUP
	else:
		var growth := clampf((elapsed - _flight_end) / (Timeline.RECOVERY * 0.85), 0.0, 1.0)
		_card.attack_regrowth = 1.0 - pow(1.0 - growth, 3.0) + sin(growth * PI) * 0.16
	for impact in _impacts:
		if not impact["emitted"] and elapsed >= float(impact["time"]):
			impact["emitted"] = true
			if not impact["blocked"]:
				target_hit.emit(int(impact["row"]), int(impact["col"]), bool(impact["success"]), _owner)


func _finish() -> void:
	if is_instance_valid(_card):
		_card.finish_attack_animation()
	reveal_finished.emit()
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_card):
		_card.finish_attack_animation()


func _draw() -> void:
	if not is_instance_valid(_card):
		return
	for projectile in _projectiles:
		_draw_projectile(projectile)
	for impact in _impacts:
		_draw_impact(impact)


func _position_at(stops: Array, time: float) -> Vector2:
	for index in range(1, stops.size()):
		if time <= float(stops[index]["time"]):
			var weight := clampf(inverse_lerp(float(stops[index - 1]["time"]), float(stops[index]["time"]), time), 0.0, 1.0)
			var start: Vector2 = stops[index - 1]["point"]
			return start.lerp(stops[index]["point"], weight)
	return stops[-1]["point"]


func _draw_projectile(projectile: Dictionary) -> void:
	var stops: Array = projectile["stops"]
	var stop_time := float(stops[-1]["time"])
	var point := _position_at(stops, elapsed)
	var direction: Vector2 = projectile["direction"]
	var alpha := 1.0
	var after := elapsed - stop_time
	if after >= 0.0:
		if projectile["failed"]:
			var fall := clampf(after / 0.24, 0.0, 1.0)
			point -= direction * _square * 0.12 * sin(fall * PI * 0.7)
			point += Vector2.DOWN * _square * 0.23 * fall * fall
			direction = direction.rotated(fall * (2.1 if int(projectile["index"]) % 2 == 0 else -2.1))
			alpha = 1.0 - fall
		elif projectile["exit"]:
			alpha = 0.0
		else:
			var enter := clampf(after / 0.12, 0.0, 1.0)
			point += direction * _square * 0.20 * enter
			alpha = 1.0 - enter
	if projectile["exit"] and after < 0.0:
		alpha *= clampf(-after / 0.07, 0.0, 1.0)
	if alpha <= 0.01:
		return
	var kind := str(projectile["kind"])
	var color := Symbols.GOLD
	match kind:
		"long": color = Symbols.LONG
		"random": color = Symbols.FORTUNE
		"swarm": color = Symbols.SWARM
	color.a = alpha
	var launch := smoothstep(0.0, Timeline.WINDUP, elapsed)
	var length := _square * (0.080 if kind == "long" else 0.060) * launch
	if length < 0.5:
		return
	if kind == "long" and after < 0.0:
		for trail in range(1, 6):
			var tail := _position_at(stops, maxf(Timeline.WINDUP, elapsed - trail * 0.013))
			var trail_color := color
			trail_color.a *= (1.0 - trail / 6.0) * 0.65
			draw_line(tail, point, trail_color, maxf(1.0, _square * 0.014 * (1.0 - trail / 7.0)), true)
	var tangent := Vector2(-direction.y, direction.x)
	var points := PackedVector2Array([point + direction * length,
		point - direction * length * 0.7 + tangent * length * 0.5,
		point - direction * length * 0.7 - tangent * length * 0.5])
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, Color(0.12, 0.08, 0.04, alpha), maxf(1.0, _square * 0.006), true)
	if kind == "long":
		var inner := PackedVector2Array()
		for index in range(3):
			inner.append(points[index].lerp(point - direction * length * 0.35, 0.45))
		draw_colored_polygon(inner, Color(1.0, 0.92, 0.66, alpha))


func _draw_impact(impact: Dictionary) -> void:
	var age := elapsed - float(impact["time"])
	if age < 0.0 or age > IMPACT_LIFETIME:
		return
	var fade := 1.0 - age / IMPACT_LIFETIME
	var point: Vector2 = impact["point"]
	var direction: Vector2 = impact["direction"]
	var tangent := Vector2(-direction.y, direction.x)
	if impact["success"]:
		point += direction * _square * 0.07
		var color := Symbols.LONG if impact["blue"] else Symbols.GOLD
		color.a = fade
		var radius := _square * (0.04 + age * 0.32)
		draw_arc(point, radius, 0, TAU, 24, color, maxf(1.5, _square * 0.01), true)
		for index in range(6):
			var ray := Vector2.from_angle(TAU * index / 6.0)
			draw_line(point + ray * radius, point + ray * radius * 1.5, color, maxf(1.0, _square * 0.007), true)
	else:
		var color := Color(1.0, 0.93, 0.48, fade)
		var impact_pulse := sin(clampf(age / 0.10, 0.0, 1.0) * PI)
		var half_length := _square * (0.33 - impact_pulse * 0.022)
		var barrier := PackedVector2Array()
		for index in range(13):
			var across := lerpf(-1.0, 1.0, float(index) / 12.0)
			var curve := (1.0 - across * across) * _square * (0.036 + impact_pulse * 0.015)
			barrier.append(point + tangent * half_length * across - direction * curve)
		var halo := Color(1.0, 0.62, 0.12, fade * 0.40)
		draw_polyline(barrier, halo, maxf(6.0, _square * 0.052), true)
		draw_polyline(barrier, color, maxf(2.5, _square * 0.018), true)
		var cap_radius := maxf(3.0, _square * 0.027)
		draw_circle(barrier[0], cap_radius, halo)
		draw_circle(barrier[-1], cap_radius, halo)
		draw_circle(barrier[0], cap_radius * 0.43, color)
		draw_circle(barrier[-1], cap_radius * 0.43, color)
