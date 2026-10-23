## Aspiration puis répartition des boucliers de Pillage.
extends "res://scripts/ui/combat/animations/CardRevealAnimation.gd"
const CAPTURE_END := 0.06
const ABSORPTION_END := 0.50
const DISTRIBUTION_END := 0.82
var _targets: Array[Vector2] = []
var _transfers: Array = []
var _channels: Array = []
var _face_gates: Dictionary = {}
## Ordre de dessin des quatre conduits du répartiteur.
const GATE_SIDES: Array[String] = ["top", "right", "bottom", "left"]
## Indices des conduits que le moteur pouvait choisir : ce sont les seuls que
## la recherche fait clignoter. Les autres restent éteints.
var _searchable_gates: Array[int] = []

func play(card: StoneCard, event: Dictionary, transfers: Array, duration: float) -> void:
	_prepare(card)
	_transfers = transfers
	var preview: BattleStoneModel = card.get_battle_stone().clone()
	preview.shields = event["shields_before"].duplicate()
	var seen := {}
	for index in range(_transfers.size()):
		var transfer: Dictionary = _transfers[index]
		var side := str(transfer["destination_side"])
		# Les nouveaux boucliers se rangent après ceux que la face avait déjà.
		var slot_index := preview.marker_offset("shield", side) \
			+ preview.marker_count_of("shield", side) + int(seen.get(side, 0))
		var target := _card_transform * card.marker_position(side, slot_index)
		_targets.append(target)
		transfer["target"] = target
		transfer["mouth"] = _card_transform * card.face_center(str(transfer["direction"]))
		_register_channel(transfer)
		var origin_card: StoneCard = transfer.get("card")
		if is_instance_valid(origin_card):
			origin_card.set_marker_growth(str(transfer["side"]), int(transfer["marker_index"]), 0.0)
		seen[side] = int(seen.get(side, 0)) + 1
	for side in BattleStoneModel.SIDES:
		_face_gates[side] = _card_transform * card.face_center(side)
	var possible := {}
	for transfer in _transfers:
		for side in transfer.get("candidate_sides", [transfer["destination_side"]]):
			possible[str(side)] = true
	for gate_index in range(GATE_SIDES.size()):
		if possible.has(GATE_SIDES[gate_index]):
			_searchable_gates.append(gate_index)
	card.set_combat_preview(preview)
	_start(duration)

func _register_channel(transfer: Dictionary) -> void:
	var origin_card: StoneCard = transfer.get("card")
	if not is_instance_valid(origin_card):
		return
	var key := "%d:%s" % [origin_card.get_instance_id(), transfer["side"]]
	for channel in _channels:
		if channel["key"] == key:
			return
	_channels.append({"key": key, "start": transfer["face"], "end": transfer["mouth"]})

func _update_preview() -> void:
	_update_stolen_marker_regrowth()

func _restore_preview() -> void:
	_restore_stolen_markers()
	super._restore_preview()

func _draw() -> void:
	if is_instance_valid(_card):
		_draw_pillage()

func _update_stolen_marker_regrowth() -> void:
	if _transfers.is_empty():
		return
	for index in range(_transfers.size()):
		var transfer: Dictionary = _transfers[index]
		var origin_card: StoneCard = transfer.get("card")
		if not is_instance_valid(origin_card):
			continue
		var delay := float(index) / float(maxi(1, _transfers.size())) * 0.08
		var value := clampf(inverse_lerp(ABSORPTION_END + delay, DISTRIBUTION_END + delay, progress), 0.0, 1.0)
		var growth := 1.0 - pow(1.0 - value, 3.0) + sin(value * PI) * 0.15
		origin_card.set_marker_growth(str(transfer["side"]), int(transfer["marker_index"]), growth)

func _restore_stolen_markers() -> void:
	var restored := {}
	for transfer in _transfers:
		var origin_card: StoneCard = transfer.get("card")
		if is_instance_valid(origin_card) and not restored.has(origin_card.get_instance_id()):
			origin_card.clear_marker_growth()
			restored[origin_card.get_instance_id()] = true

func _draw_pillage() -> void:
	var suction := clampf(inverse_lerp(CAPTURE_END, ABSORPTION_END, progress), 0.0, 1.0)
	if progress < ABSORPTION_END:
		for channel in _channels:
			_draw_suction_tunnel(channel, suction)
		for index in range(_transfers.size()):
			_draw_stolen_transfer(_transfers[index], index, suction)
	if progress >= ABSORPTION_END:
		_draw_random_distribution()


## Un entonnoir translucide relie directement la face vaincue à la face de
## Pillage. Les cinq courbes lui donnent le volume d'un demi-trou de ver.

func _draw_suction_tunnel(channel: Dictionary, value: float) -> void:
	var start: Vector2 = channel["start"]
	var end: Vector2 = channel["end"]
	var direction := (end - start).normalized()
	var tangent := Vector2(-direction.y, direction.x)
	var fade := smoothstep(0.0, 0.12, value) * (1.0 - smoothstep(0.78, 1.0, value))
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for step in range(17):
		var t := float(step) / 16.0
		var width := lerpf(_square * 0.29, _square * 0.09, smoothstep(0.0, 0.88, t))
		var bow := sin(t * PI) * _square * 0.040
		upper.append(start.lerp(end, t) + tangent * (width + bow))
		lower.append(start.lerp(end, t) - tangent * (width + bow))
	var fill := PackedVector2Array(upper)
	for index in range(lower.size() - 1, -1, -1):
		fill.append(lower[index])
	draw_colored_polygon(fill, Color(0.56, 0.18, 0.48, 0.16 * fade))
	for lane in range(-2, 3):
		var line := PackedVector2Array()
		for step in range(17):
			var t := float(step) / 16.0
			var width := lerpf(_square * 0.29, _square * 0.09, smoothstep(0.0, 0.88, t))
			var wave := sin(t * PI) * _square * 0.025 * sin(value * TAU * 2.0 + lane)
			line.append(start.lerp(end, t) + tangent * (float(lane) * width * 0.47 + wave))
		var color := Symbols.THEFT.lerp(Color("#b64ac7"), absf(float(lane)) * 0.18)
		color.a = fade * (0.90 if abs(lane) == 2 else 0.62)
		draw_polyline(line, color, maxf(2.0, _square * (0.024 if abs(lane) == 2 else 0.013)), true)
	# La bouche proche de la carte voleuse se contracte pendant l'aspiration.
	var mouth_radius := _square * lerpf(0.14, 0.065, value)
	draw_arc(end, mouth_radius, 0.0, TAU, 24, Color(1.0, 0.70, 0.34, fade),
		maxf(2.0, _square * 0.014), true)

func _draw_stolen_transfer(transfer: Dictionary, index: int, value: float) -> void:
	var delay := float(index) / float(maxi(1, _transfers.size())) * 0.20
	var travel := clampf(inverse_lerp(delay, 0.84 + delay * 0.4, value), 0.0, 1.0)
	var start: Vector2 = transfer["position"]
	var end: Vector2 = transfer["mouth"]
	var direction := (end - start).normalized()
	var tangent := Vector2(-direction.y, direction.x)
	var bend := (float(index % 3) - 1.0) * _square * 0.07
	var point := start.lerp(end, smoothstep(0.0, 1.0, travel)) \
		+ tangent * sin(travel * PI) * bend
	for trail in range(1, 6):
		var previous := maxf(0.0, travel - float(trail) * 0.035)
		var trail_point := start.lerp(end, smoothstep(0.0, 1.0, previous)) \
			+ tangent * sin(previous * PI) * bend
		var trail_color := Symbols.THEFT
		trail_color.a = (1.0 - float(trail) / 6.0) * 0.55
		draw_line(trail_point, point, trail_color, maxf(1.0, _square * 0.010), true)
	var alpha := 1.0 - smoothstep(0.88, 1.0, travel)
	_draw_flying_marker(point, direction, str(transfer["kind"]), _square * 0.050, alpha)


## Après l'aspiration, un noyau répartiteur alimente quatre conduits. De faux
## chemins s'allument rapidement, puis les destinations tirées par le moteur
## restent dorées et reçoivent leurs demi-boucliers.

func _draw_random_distribution() -> void:
	var search := clampf(inverse_lerp(ABSORPTION_END, DISTRIBUTION_END, progress), 0.0, 1.0)
	var landing := clampf(inverse_lerp(DISTRIBUTION_END, 1.0, progress), 0.0, 1.0)
	var gates := [_face_gates.get("top", _center), _face_gates.get("right", _center),
		_face_gates.get("bottom", _center), _face_gates.get("left", _center)]
	var side_names := GATE_SIDES
	var selected_sides := {}
	for transfer in _transfers:
		var selected_side := str(transfer["destination_side"])
		selected_sides[selected_side] = int(selected_sides.get(selected_side, 0)) + 1
	var active_gate := -1
	if not _searchable_gates.is_empty():
		active_gate = _searchable_gates[int(floor(search * 15.0)) % _searchable_gates.size()]
	# Les quatre conduits restent lisibles ; seuls les possibles sont parcourus.
	for gate_index in range(gates.size()):
		var gate: Vector2 = gates[gate_index]
		var closed := not _searchable_gates.has(gate_index)
		var chosen := landing > 0.0 and selected_sides.has(side_names[gate_index])
		var searching := landing <= 0.0 and gate_index == active_gate
		var branch_color := Color(0.31, 0.14, 0.24, 0.62)
		var branch_width := maxf(3.0, _square * 0.019)
		if closed:
			# La face qui a capturé ne peut rien recevoir : son conduit reste éteint.
			branch_color = Color(0.20, 0.10, 0.14, 0.22)
		elif searching:
			branch_color = Color(1.0, 0.72, 0.24, 0.96)
			branch_width = maxf(7.0, _square * 0.052)
		elif chosen:
			branch_color = Color(1.0, 0.66, 0.18, 0.92)
			branch_width = maxf(6.0, _square * 0.043)
		var path := _distribution_branch(gate, gate_index)
		draw_polyline(path, Color(branch_color, branch_color.a * 0.26), branch_width * 1.75, true)
		draw_polyline(path, branch_color, branch_width, true)
		var gate_color := Symbols.THEFT if not searching and not chosen else Color("#ffd45b")
		gate_color.a = 0.58 if not searching and not chosen else 1.0
		if closed:
			gate_color.a = 0.20
		draw_circle(gate, _square * (0.050 if searching or chosen else 0.037),
			Color(0.19, 0.08, 0.10, 0.40 if closed else 0.88))
		draw_arc(gate, _square * (0.058 if searching or chosen else 0.044), 0.0, TAU, 20,
			gate_color, maxf(2.0, _square * 0.016), true)
	# Un paquet lumineux parcourt le faux chemin actif pour matérialiser le tirage.
	if landing <= 0.0:
		var search_step := fposmod(search * 15.0, 1.0)
		var pulse_point := _distribution_branch_point(gates[active_gate], active_gate,
			sin(search_step * PI) if search_step < 1.0 else 1.0)
		draw_circle(pulse_point, _square * 0.046, Color(1.0, 0.90, 0.42, 0.35))
		draw_circle(pulse_point, _square * 0.022, Color("#fff3a8"))
	# Le noyau est volontairement grand : il remplace la petite roulette et
	# annonce clairement que les unités absorbées attendent une destination.
	var core_pulse := 1.0 + sin(search * TAU * 7.5) * 0.08 if landing <= 0.0 else 1.0
	draw_circle(_center, _square * 0.125 * core_pulse, Color(0.13, 0.05, 0.08, 0.92))
	draw_circle(_center, _square * 0.092 * core_pulse, Color(0.78, 0.25, 0.10, 0.94))
	draw_arc(_center, _square * 0.128 * core_pulse, 0.0, TAU, 28,
		Color("#ffd45b"), maxf(3.0, _square * 0.020), true)
	Symbols.draw_text(self, _center, _square * 0.080,
		"?" if landing <= 0.0 else "×%d" % _transfers.size(), Color("#fff3bd"))
	# À la résolution, chaque bouclier quitte le noyau par son vrai conduit.
	for index in range(_transfers.size()):
		var transfer: Dictionary = _transfers[index]
		var delayed_landing := clampf(landing * 1.22 - float(index) / float(maxi(1, _transfers.size())) * 0.18, 0.0, 1.0)
		if delayed_landing <= 0.0:
			continue
		var destination_side := str(transfer["destination_side"])
		var destination_index := side_names.find(destination_side)
		var target: Vector2 = transfer["target"]
		var travel := smoothstep(0.0, 1.0, delayed_landing)
		var point := _distribution_branch_point(target, destination_index, travel)
		var previous := _distribution_branch_point(target, destination_index, maxf(0.0, travel - 0.10))
		var movement: Vector2 = (point - previous).normalized()
		draw_line(previous, point, Color(1.0, 0.76, 0.25, 0.82), maxf(3.0, _square * 0.020), true)
		_draw_flying_marker(point, movement, "shield", _square * 0.066, 1.0)
		if delayed_landing > 0.72:
			var glow := Symbols.THEFT
			glow.a = (delayed_landing - 0.72) / 0.28
			draw_arc(target, _square * 0.075, 0.0, TAU, 20, glow,
				maxf(2.0, _square * 0.012), true)

func _distribution_branch(end: Vector2, index: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in range(13):
		points.append(_distribution_branch_point(end, index, float(step) / 12.0))
	return points

func _distribution_branch_point(end: Vector2, index: int, value: float) -> Vector2:
	var direction := (end - _center).normalized()
	var tangent := Vector2(-direction.y, direction.x)
	var bend_sign := -1.0 if index % 2 == 0 else 1.0
	return _center.lerp(end, smoothstep(0.0, 1.0, value)) \
		+ tangent * sin(value * PI) * _square * 0.030 * bend_sign

func _draw_flying_marker(point: Vector2, direction: Vector2, kind: String, size: float, alpha: float) -> void:
	var color := Symbols.GOLD
	match kind:
		"random": color = Symbols.FORTUNE
		"swarm": color = Symbols.SWARM
		"long": color = Symbols.LONG
		"shield": color = Symbols.SHIELD
	color.a = alpha
	if kind == "shield":
		Symbols.draw_shield(self, point - direction * size * 0.25, size * 1.35, size,
			direction if not direction.is_zero_approx() else Vector2.UP, color)
		return
	var forward := direction if not direction.is_zero_approx() else Vector2.UP
	var tangent := Vector2(-forward.y, forward.x)
	var points := PackedVector2Array([point + forward * size,
		point - forward * size * 0.65 + tangent * size * 0.58,
		point - forward * size * 0.65 - tangent * size * 0.58])
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, Color(1.0, 0.91, 0.68, alpha), maxf(1.0, _square * 0.008), true)
