## Traduit les événements du moteur en coordonnées et attend les animations.
## Ne modifie ni le GameState ni son hasard.
extends Control
const RandomReveal := preload("res://scripts/ui/combat/animations/RandomBladeAnimation.gd")
const CoinReveal := preload("res://scripts/ui/combat/animations/CoinFlipAnimation.gd")
const PillageReveal := preload("res://scripts/ui/combat/animations/PillageAnimation.gd")
const AttackReveal := preload("res://scripts/ui/combat/AttackAnimation.gd")
const WeaknessReveal := preload("res://scripts/ui/combat/WeaknessAnimation.gd")
const SwarmReveal := preload("res://scripts/ui/combat/SwarmAnimation.gd")
const Timeline := preload("res://scripts/ui/combat/CombatTimeline.gd")
const Geometry := preload("res://scripts/ui/combat/BoardEffectGeometry.gd")
const Batch := preload("res://scripts/ui/combat/AnimationBatch.gd")
var _geometry: Geometry
var _board: BoardView
var _batch: Batch
var _active_step: CombatPresentation
var _tweens: Array[Tween] = []
## Garde-fou interne : il n'apparaît pas dans get_children(), donc
## _cancel_animations() ne le supprime pas avec les animations.
var _watchdog: Timer

func setup(board: BoardView) -> void:
	_board = board
	_geometry = Geometry.new(board)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_watchdog = Timer.new()
	_watchdog.one_shot = true
	_watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(_watchdog, false, Node.INTERNAL_MODE_BACK)

func present(step: CombatPresentation) -> void:
	_active_step = step
	step.cancelled.connect(_cancel_animations, CONNECT_ONE_SHOT)
	_batch = Batch.new()
	var current_batch = _batch
	var duration := Timeline.step_duration(step)
	if _watchdog.is_inside_tree():
		_watchdog.start(duration + Timeline.WATCHDOG_MARGIN)
	# Le changement d'Essaim révélé à l'étape suivante reste masqué pendant celle-ci.
	_hold_swarm_preview(step.pending_swarm)
	match step.kind:
		CombatPresentation.Kind.PLACEMENT:
			animate_placement(step.row, step.col)
		CombatPresentation.Kind.PREPARATION:
			animate_preparation(step.row, step.col, step.events, duration)
		CombatPresentation.Kind.SWARM:
			animate_swarm(step.events, duration)
		CombatPresentation.Kind.ATTACK:
			animate_attacks(step.row, step.col, step.events, step.player, duration)
		CombatPresentation.Kind.EFFECTS:
			animate_effects(step.events, duration)
	current_batch.seal()
	if not current_batch.completed:
		await current_batch.finished
	# Arrêté avant complete() : l'étape suivante peut démarrer dans le même appel.
	_watchdog.stop()
	if step.cancelled.is_connected(_cancel_animations):
		step.cancelled.disconnect(_cancel_animations)
	if _active_step == step:
		_active_step = null
	step.complete()

## Une animation qui ne signale jamais sa fin ne doit pas bloquer la partie :
## le résultat est déjà calculé, il suffit d'interrompre sa présentation.
func _on_watchdog_timeout() -> void:
	var step := _active_step
	if step == null or step.completed:
		return
	push_warning("Animation %s interrompue : elle a dépassé sa durée prévue." %
		CombatPresentation.Kind.keys()[step.kind])
	_cancel_animations()
	# Si present() s'est arrêté sur une erreur, personne n'attend plus le lot.
	if not step.completed:
		if _active_step == step:
			_active_step = null
		step.complete()

func _track(animation: Node) -> void:
	if _batch != null and not _batch.completed:
		_batch.track(animation.reveal_finished)

func _hold_swarm_preview(events: Array) -> void:
	for event in events:
		for member in event.get("members", []):
			var card := _board.card_at(member["row"], member["col"])
			if card != null and card.get_battle_stone() != null:
				var preview = card.get_battle_stone().clone()
				preview.swarm_blades = member["before"].duplicate()
				card.set_combat_preview(preview)

func animate_capture(row: int, col: int, new_owner: int) -> void:
	var card: StoneCard = _board.card_at(row, col)
	if card == null or card.get_combat_owner() == new_owner:
		return
	card.pivot_offset = card.size * 0.5
	var tween := _create_tracked_tween()
	tween.tween_property(card, "modulate", Color(1.6, 1.6, 1.2), 0.12)
	tween.tween_property(card, "modulate", Color(1, 1, 1), 0.18)
	card.set_owner_color(new_owner)


## Tween gardé pour pouvoir l'arrêter si l'étape est annulée. Aucune connexion
## ne le retient : les tweens terminés ou arrêtés sont simplement oubliés ici.
func _create_tracked_tween() -> Tween:
	for index in range(_tweens.size() - 1, -1, -1):
		if not _tweens[index].is_valid():
			_tweens.remove_at(index)
	var tween := create_tween()
	_tweens.append(tween)
	return tween


func animate_placement(row: int, col: int) -> void:
	var card: StoneCard = _board.card_at(row, col)
	if card == null:
		return
	card.hide_placement_power()
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2.ONE * 0.90
	var tween := _create_tracked_tween()
	tween.tween_property(card, "scale", Vector2.ONE * 1.035, Timeline.PLACEMENT * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE, Timeline.PLACEMENT * 0.45)
	if _batch != null and not _batch.completed:
		_batch.track(tween.finished)


func animate_attacks(row: int, col: int, attacks: Array, owner: int, duration: float) -> void:
	var card: StoneCard = _board.card_at(row, col)
	if card == null or attacks.is_empty():
		return
	var paths := _geometry.attack_paths(card, attacks)
	var animation := AttackReveal.new()
	animation.name = "AttackReveal"
	add_child(animation)
	_track(animation)
	animation.target_hit.connect(_on_attack_hit)
	animation.play(card, paths, attacks, owner, duration)


func _on_attack_hit(row: int, col: int, success: bool, owner: int) -> void:
	if success:
		animate_capture(row, col, owner)


func animate_effects(events: Array, duration: float = 0.0) -> void:
	var weakening_events: Array = []
	var repair_events: Array = []
	for event in events:
		var event_type := str(event.get("type", ""))
		if event_type == CombatEvents.WEAKEN or event_type == CombatEvents.TEMPORARY_WEAKEN:
			weakening_events.append(event)
			continue
		if event_type == CombatEvents.WEAKNESS_EXPIRED:
			repair_events.append(event)
			continue
		var row := int(event.get("row", -1))
		var col := int(event.get("col", -1))
		if row < 0 or col < 0:
			continue
		var card: StoneCard = _board.card_at(row, col)
		if card == null:
			continue
		if event_type == CombatEvents.SHIELD_THEFT:
			var animation := PillageReveal.new()
			animation.name = "PillageReveal"
			add_child(animation)
			_track(animation)
			animation.play(card, event, _geometry.pillage_transfers(event), duration)
			continue
		push_warning("Événement visuel inconnu : " + event_type)
	if not weakening_events.is_empty():
		_animate_weakening(weakening_events, duration)
	if not repair_events.is_empty():
		var weakened_now := {}
		for event in weakening_events:
			weakened_now["%d:%d" % [event["row"], event["col"]]] = true
		var visible_repairs: Array = []
		for event in repair_events:
			if not weakened_now.has("%d:%d" % [event["row"], event["col"]]):
				visible_repairs.append(event)
		if not visible_repairs.is_empty():
			_animate_weakness_repair(visible_repairs, duration)


func _animate_weakening(events: Array, duration: float) -> void:
	var first: Dictionary = events[0]
	var source_row := int(first.get("source_row", -1))
	var source_col := int(first.get("source_col", -1))
	if source_row < 0 or source_col < 0:
		return
	var source: StoneCard = _board.card_at(source_row, source_col)
	if source == null:
		return
	var targets := _geometry.weakness_targets(events)
	if targets.is_empty():
		return
	var animation := WeaknessReveal.new()
	animation.name = "WeaknessReveal"
	add_child(animation)
	_track(animation)
	animation.play_weakening(source, targets, first.get("scope", "") == "global",
		maxf(0.1, duration))


func _animate_weakness_repair(events: Array, duration: float) -> void:
	var targets := _geometry.weakness_targets(events)
	if targets.is_empty():
		return
	var animation := WeaknessReveal.new()
	animation.name = "WeaknessRepair"
	add_child(animation)
	_track(animation)
	animation.play_repair(targets, minf(maxf(0.1, duration), WeaknessReveal.REPAIR_DURATION))


func animate_swarm(events: Array, duration: float, delay: float = 0.0) -> void:
	if events.is_empty():
		return
	var event: Dictionary = events[0]
	var data := _geometry.swarm_data(event)
	if data.is_empty():
		return
	var members: Array = data["members"]
	var links_before: Array = data["links_before"]
	var links_after: Array = data["links_after"]
	var source_center: Vector2 = data["source"]
	var animation := SwarmReveal.new()
	animation.name = "SwarmReveal"
	add_child(animation)
	_track(animation)
	animation.transition_started.connect(
		_on_swarm_transition_started.bind(links_before))
	animation.reveal_finished.connect(
		_on_swarm_transition_finished.bind(links_after))
	animation.play(members, links_before, links_after, source_center,
		maxf(0.1, duration), maxf(0.0, delay))


func set_swarm_links(raw_links: Array) -> void:
	_board.replace_swarm_links(_geometry.persistent_links(raw_links))


func _on_swarm_transition_started(links_before: Array) -> void:
	if is_instance_valid(_board):
		_board.remove_swarm_links(links_before)


func _on_swarm_transition_finished(links_after: Array) -> void:
	if is_instance_valid(_board):
		_board.add_swarm_links(links_after)


func animate_preparation(row: int, col: int, events: Array, duration: float) -> void:
	var card := _board.card_at(row, col)
	if card == null or events.is_empty():
		return
	var animation: Control
	if events[0]["type"] == CombatEvents.COIN_FLIP:
		animation = CoinReveal.new()
		animation.name = "CoinReveal"
		add_child(animation)
		_track(animation)
		animation.play(card, events[0], duration)
	else:
		animation = RandomReveal.new()
		animation.name = "RandomReveal"
		add_child(animation)
		_track(animation)
		animation.play(card, events, duration)

func _cancel_animations() -> void:
	for tween in _tweens:
		tween.kill()
	_tweens.clear()
	for animation in get_children():
		remove_child(animation)
		animation.queue_free()
	if is_instance_valid(_board):
		for row in range(GameState.BOARD_SIZE):
			for col in range(GameState.BOARD_SIZE):
				var card := _board.card_at(row, col)
				if card != null:
					card.set_combat_preview(null)
					card.clear_marker_growth()
					card.clear_visual_weakness()
					card.finish_attack_animation()
					card.scale = Vector2.ONE
					card.modulate = Color.WHITE
	if _batch != null:
		_batch.cancel()

func _exit_tree() -> void:
	if _active_step != null:
		_active_step.cancel()
