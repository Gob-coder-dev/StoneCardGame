## Aura de Déclin. Le moteur fournit les valeurs avant/après ; cette couche ne
## fait que retarder leur révélation visuelle jusqu'à l'arrivée du poison.
extends Control

signal reveal_finished

const AURA := Color("#9b6bc7")
const AURA_BRIGHT := Color("#e889d4")
const AURA_DARK := Color("#321544")
const REPAIR_DURATION: float = 0.48

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		_update_target_states()
		queue_redraw()

var mode: String = ""
var _source: StoneCard
var _source_center := Vector2.ZERO
var _square: float = 0.0
var _targets: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 20


## Une traînée de poison part de la pierre posée vers chaque pierre affaiblie :
## ses voisines pour le Miasme, les pierres qui ont résisté pour l'Échec corrosif.
func play_weakening(source: StoneCard, targets: Array, duration: float) -> void:
	mode = CombatEvents.WEAKEN
	_source = source
	_targets = targets
	var source_transform := get_global_transform().affine_inverse() * source.get_global_transform()
	_source_center = source_transform * (source.size * 0.5)
	_square = minf(source.size.x, source.size.y)
	for index in range(_targets.size()):
		var target: Dictionary = _targets[index]
		# Une cible plus lointaine (lame bleue) est atteinte un peu plus tard.
		var distance := _source_center.distance_to(target["center"])
		var stagger := minf(0.12, maxf(0.0, distance / maxf(_square, 1.0) - 1.2) * 0.06)
		target["arrival"] = 0.54 + stagger
		var card: StoneCard = target.get("card")
		if is_instance_valid(card):
			card.set_visual_weakness(int(target["before"]))
	_start(duration)


func play_repair(targets: Array, duration: float) -> void:
	mode = "repair"
	_targets = targets
	if not _targets.is_empty():
		_square = float(_targets[0].get("square", 100.0))
	for target in _targets:
		var card: StoneCard = target.get("card")
		if is_instance_valid(card):
			card.set_visual_weakness(int(target["before"]))
	_start(duration)


func _start(duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "progress", 1.0, duration * 0.98)
	tween.tween_callback(_finish)


func _update_target_states() -> void:
	for target in _targets:
		var card: StoneCard = target.get("card")
		if not is_instance_valid(card):
			continue
		var reveal_at := 0.48 if mode == "repair" else float(target.get("arrival", 0.54))
		card.set_visual_weakness(int(target["after"] if progress >= reveal_at else target["before"]))


func _finish() -> void:
	_restore_cards()
	reveal_finished.emit()
	queue_free()


func _exit_tree() -> void:
	_restore_cards()


func _restore_cards() -> void:
	for target in _targets:
		var card: StoneCard = target.get("card")
		if is_instance_valid(card):
			card.clear_visual_weakness()


func _draw() -> void:
	if mode == CombatEvents.WEAKEN and is_instance_valid(_source):
		_draw_source_aura()
		for index in range(_targets.size()):
			_draw_poison_path(_targets[index], index)
	elif mode == "repair":
		for index in range(_targets.size()):
			_draw_repair(_targets[index], index)


func _draw_source_aura() -> void:
	var cast := smoothstep(0.0, 0.22, progress) * (1.0 - smoothstep(0.68, 0.96, progress))
	if cast <= 0.0:
		return
	var pulse := 1.0 + sin(progress * TAU * 7.0) * 0.08
	draw_circle(_source_center, _square * 0.24 * pulse, Color(0.20, 0.04, 0.28, 0.20 * cast))
	draw_arc(_source_center, _square * 0.28 * pulse, -PI * 0.15, PI * 1.35,
		32, Color(AURA_BRIGHT, 0.72 * cast), maxf(3.0, _square * 0.025), true)
	for index in range(12):
		var angle := TAU * float(index) / 12.0 + sin(progress * 5.0 + index) * 0.10
		var direction := Vector2.from_angle(angle)
		var tangent := Vector2(-direction.y, direction.x)
		var inner := _source_center + direction * _square * 0.14
		var outer := _source_center + direction * _square * (0.30 + 0.10 * sin(progress * 8.0 + index * 1.7))
		var flame := PackedVector2Array([inner - tangent * _square * 0.035,
			outer, inner + tangent * _square * 0.035])
		draw_colored_polygon(flame, Color(AURA, cast * (0.20 + 0.10 * (index % 2))))


func _draw_poison_path(target: Dictionary, index: int) -> void:
	var arrival := float(target.get("arrival", 0.54))
	var travel := clampf(inverse_lerp(0.16, arrival, progress), 0.0, 1.0)
	var start := _source_center
	var end: Vector2 = target["center"]
	var direction := (end - start).normalized()
	var tangent := Vector2(-direction.y, direction.x)
	var bend := (1.0 if index % 2 == 0 else -1.0) * _square * 0.075
	if travel > 0.0 and travel < 1.0:
		var head := _wisp_point(start, end, tangent, bend, travel)
		for trail in range(11, -1, -1):
			var trail_value := maxf(0.0, travel - float(trail) * 0.035)
			var point := _wisp_point(start, end, tangent, bend, trail_value)
			var weight := 1.0 - float(trail) / 12.0
			var smoke_color := AURA_DARK.lerp(AURA_BRIGHT, weight * 0.55)
			smoke_color.a = weight * 0.52
			draw_circle(point, _square * (0.028 + weight * 0.032), smoke_color)
			draw_circle(point + tangent * sin(trail + index) * _square * 0.018,
				_square * 0.016, Color(AURA_BRIGHT, weight * 0.30))
		draw_circle(head, _square * 0.055, Color(AURA_BRIGHT, 0.80))
	var age := progress - arrival
	if age >= 0.0 and age <= 0.34:
		var fade := 1.0 - age / 0.34
		var target_square := float(target.get("square", _square))
		var radius := target_square * (0.18 + age * 0.75)
		draw_arc(end, radius, 0.0, TAU, 28, Color(AURA_BRIGHT, fade),
			maxf(2.0, target_square * 0.020), true)
		for particle in range(8):
			var ray := Vector2.from_angle(TAU * float(particle) / 8.0 + index * 0.31)
			var particle_point := end + ray * radius * (0.62 + age)
			draw_circle(particle_point, target_square * 0.018, Color(AURA, fade * 0.75))


func _wisp_point(start: Vector2, end: Vector2, tangent: Vector2, bend: float, value: float) -> Vector2:
	return start.lerp(end, smoothstep(0.0, 1.0, value)) \
		+ tangent * sin(value * PI) * bend * sin(value * PI * 1.5 + progress * 7.0)


func _draw_repair(target: Dictionary, index: int) -> void:
	var center: Vector2 = target["center"]
	var target_square := float(target.get("square", _square))
	var fade := sin(progress * PI)
	for particle in range(7):
		var direction := Vector2.from_angle(TAU * float(particle) / 7.0 + index * 0.27)
		var distance := target_square * lerpf(0.20, 0.38, progress)
		var point := center + direction * distance
		draw_circle(point, target_square * 0.014, Color(AURA_BRIGHT, fade * 0.65))
	if progress >= 0.40 and progress <= 0.70:
		draw_arc(center, target_square * 0.22, 0.0, TAU, 24,
			Color(0.82, 0.68, 0.95, fade), maxf(2.0, target_square * 0.014), true)
