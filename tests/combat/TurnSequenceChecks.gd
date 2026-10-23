extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_turn_manager_sequence()
	await _test_pillage_turn_sequence()
	await _test_swarm_turn_sequence()
	await _test_attack_turn_sequence()
	await _test_presentation_acknowledgement()
	await _test_close_during_animation()
	await _test_swarm_pillage_presentation()
	await _test_stuck_animation_watchdog()
	await _test_cancelled_tweens_are_released()

func _test_turn_manager_sequence() -> void:
	var manager := _animated_manager()
	var observed := {"preparing": false, "placed": false}
	manager.stone_preparing.connect(func(_row: int, _col: int, events: Array):
		observed["preparing"] = events.size() == 2
	)
	manager.stone_placed.connect(func(_row: int, _col: int, _stone_id: String, _owner: int):
		observed["placed"] = true
	)
	manager.start_game(["kappa"], ["fx_plain"], [], "", GameState.PLAYER_HUMAN, "inari", "hachiman")
	var accepted := manager.human_play(1, 1, "kappa")
	_check(accepted and observed["placed"] and not observed["preparing"], "la pose commence avant la révélation Fortune")
	await manager.stone_preparing
	_check(observed["preparing"], "Fortune se révèle après le rebond de pose")
	_check(manager.get_state().current_player == GameState.PLAYER_HUMAN, "le tour ne change pas avant la révélation")
	await manager.turn_started
	_check(manager.get_state().current_player == GameState.PLAYER_AI, "le tour change après la résolution animée")
	manager.queue_free()


func _test_pillage_turn_sequence() -> void:
	var manager := _animated_manager()
	var observed := {"captured": false, "effects_after_capture": false}
	manager.stone_captured.connect(func(_row: int, _col: int, _owner: int):
		observed["captured"] = true
	)
	manager.effects_resolved.connect(func(events: Array):
		observed["effects_after_capture"] = observed["captured"] and not events.is_empty()
	)
	manager.start_game(["fx_thief", "fx_plain"], ["fx_plain"], [], "", GameState.PLAYER_HUMAN)
	_force_instance(manager.get_state(), 0, 1, "fx_wall", GameState.PLAYER_AI)
	manager.human_play(1, 1, "fx_thief")
	await manager.effects_resolved
	_check(observed["effects_after_capture"], "Pillage révèle son aura après la capture")
	_check(manager.get_state().current_player == GameState.PLAYER_HUMAN and not manager.human_play(2, 2, "fx_plain"),
		"aucun second coup n'est autorisé pendant l'aspiration et la répartition")
	await manager.turn_started
	_check(manager.get_state().current_player == GameState.PLAYER_AI, "le tour suivant attend la fin du Pillage")
	manager.queue_free()
	await get_tree().process_frame

	var last_move := _animated_manager()
	last_move.start_game(["fx_thief"], [], [], "", GameState.PLAYER_HUMAN)
	for row in range(3):
		for col in range(3):
			if row == 1 and col == 1:
				continue
			_force_instance(last_move.get_state(), row, col, "fx_wall", GameState.PLAYER_AI)
	last_move.human_play(1, 1, "fx_thief")
	_check(not last_move.get_state().is_game_over, "le dernier coup montre également son animation avant la fin de partie")
	await last_move.game_over
	_check(last_move.get_state().is_game_over, "la fin de partie est émise après la révélation des boucliers")
	last_move.queue_free()
	await get_tree().process_frame


func _test_swarm_turn_sequence() -> void:
	var manager := _animated_manager()
	var observed := {"emitted": false, "members": 0}
	manager.swarm_changed.connect(func(events: Array):
		observed["emitted"] = true
		observed["members"] = events[0]["members"].size()
	)
	manager.start_game(["fx_swarm_b", "fx_plain"], [], [], "", GameState.PLAYER_HUMAN)
	_force_instance(manager.get_state(), 1, 0, "fx_swarm_a", GameState.PLAYER_HUMAN)
	var accepted := manager.human_play(1, 1, "fx_swarm_b")
	await manager.swarm_changed
	_check(accepted and observed["emitted"] and observed["members"] == 2
		and manager.phase == TurnManager.Phase.SWARM,
		"le tour réserve une fenêtre au réseau Essaim après la pose")
	_check(not manager.human_play(0, 0, "fx_plain"),
		"aucun second coup n'est autorisé pendant la pousse des lames")
	await manager.turn_started
	_check(manager.get_state().current_player == GameState.PLAYER_AI,
		"le tour suivant attend la fin du renfort Essaim")
	manager.queue_free()
	await get_tree().process_frame


func _test_attack_turn_sequence() -> void:
	var manager := _animated_manager()
	manager.start_game(["fx_weaken_attack1", "fx_plain"], ["fx_plain"], [], "", GameState.PLAYER_HUMAN)
	_force_instance(manager.get_state(), 1, 2, "fx_plain", GameState.PLAYER_AI)
	manager.human_play(1, 1, "fx_weaken_attack1")
	await manager.attacks_started
	var target: BattleStoneModel = manager.get_state().get_cell(1, 2)["stone"]
	_check(target.permanent_weakness == 0 and not manager.human_play(0, 0, "fx_plain"),
		"les attaques se jouent avant le Miasme et interdisent un second coup")
	await manager.turn_started
	_check(target.permanent_weakness == 1 and manager.get_state().get_cell(1, 2)["owner"] == GameState.PLAYER_AI,
		"le Miasme est appliqué après l'impact raté puis le tour avance")
	manager.queue_free()
	await get_tree().process_frame


func _test_presentation_acknowledgement() -> void:
	var manager := TurnManager.new()
	add_child(manager)
	var held: Array[CombatPresentation] = []
	manager.presentation_requested.connect(func(step: CombatPresentation): held.append(step))
	manager.start_game(["fx_plain"], ["fx_plain"], [], "", GameState.PLAYER_HUMAN)
	manager.human_play(1, 1, "fx_plain")
	await get_tree().create_timer(0.35).timeout
	_check(manager.phase == TurnManager.Phase.PLACING
		and manager.get_state().current_player == GameState.PLAYER_HUMAN,
		"le tour attend une vraie fin de présentation même après la durée de pose habituelle")
	held.pop_front().complete()
	await get_tree().process_frame
	_check(manager.phase == TurnManager.Phase.EFFECTS and held.size() == 1,
		"la fin de pose débloque uniquement la prochaine étape")
	held.pop_front().complete()
	_check(manager.phase == TurnManager.Phase.WAITING_INPUT
		and manager.get_state().current_player == GameState.PLAYER_AI,
		"le dernier acquittement débloque le joueur suivant")
	manager.start_game(["fx_plain"], ["fx_plain"], [], "", GameState.PLAYER_HUMAN)
	manager.human_play(0, 0, "fx_plain")
	var old_step: CombatPresentation = held.pop_front()
	manager.start_game(["fx_plain"], ["fx_plain"], [], "", GameState.PLAYER_AI)
	_check(old_step.completed and manager.phase == TurnManager.Phase.WAITING_INPUT
		and manager.get_state().get_cell(0, 0)["owner"] == GameState.PLAYER_NONE,
		"redémarrer annule le coup suspendu sans l'appliquer au nouveau match")
	manager.queue_free()
	await get_tree().process_frame


func _test_close_during_animation() -> void:
	var manager := _animated_manager()
	manager.start_game(["kappa"], ["fx_plain"], [], "", GameState.PLAYER_HUMAN)
	manager.human_play(1, 1, "kappa")
	manager.queue_free()
	await get_tree().process_frame
	_check(not is_instance_valid(manager), "fermer la scène pendant une pose annule les animations et leurs attentes")


## Un Pillage capture une pierre Essaim : sa lame verte est volée, puis le
## groupe rompu perd ses bonus. L'affichage doit raconter ces étapes dans l'ordre.
func _test_swarm_pillage_presentation() -> void:
	var manager := _animated_manager()
	var board: BoardView = manager.get_child(0)
	manager.start_game(["fx_thief", "fx_plain"], ["fx_plain"], [], "", GameState.PLAYER_HUMAN)
	var state := manager.get_state()
	_force_instance(state, 0, 0, "fx_swarm_bottom", GameState.PLAYER_AI)
	_force_instance(state, 0, 1, "fx_swarm_bottom", GameState.PLAYER_AI)
	CombatResolverModel.recalculate_swarm(state)
	board.refresh(state)
	var victim: StoneCard = board.card_at(0, 1)
	var partner: StoneCard = board.card_at(0, 0)
	var gained := [0]
	manager.effects_resolved.connect(func(events: Array):
		for event in events:
			if event["type"] == CombatEvents.SHIELD_THEFT:
				gained[0] += int(event["amount"]))
	manager.human_play(1, 1, "fx_thief")
	await manager.effects_resolved
	await get_tree().process_frame
	var pillage: Node = board.animations.get_node_or_null("PillageReveal")
	_check(gained[0] == 1 and pillage != null and pillage._transfers.size() == 1
		and pillage._transfers[0]["kind"] == "swarm",
		"le Pillage anime la lame d'Essaim réellement volée")
	_check(_sum(victim.displayed_stone().swarm_blades) == 1
		and _sum(partner.displayed_stone().swarm_blades) == 1
		and _sum(victim.get_battle_stone().swarm_blades) == 0,
		"les lames d'Essaim restent visibles pendant le Pillage, avant leur rétraction")
	await manager.turn_started
	_check(_sum(victim.displayed_stone().swarm_blades) == 0
		and _sum(partner.displayed_stone().swarm_blades) == 0,
		"l'animation Essaim retire ensuite les lames perdues")
	manager.queue_free()
	await get_tree().process_frame


## Une animation qui ne signale jamais sa fin est interrompue : le tour reprend
## avec l'état déjà calculé par le moteur. Ce test écrit un avertissement attendu.
func _test_stuck_animation_watchdog() -> void:
	var manager := _animated_manager()
	var board: BoardView = manager.get_child(0)
	manager.start_game(["fx_plain"], ["fx_plain"], [], "", GameState.PLAYER_HUMAN)
	_expect_log("Animation PLACEMENT interrompue")
	manager.human_play(1, 1, "fx_plain")
	for tween in board.animations._tweens:
		tween.kill()
	var limit := Timeline.PLACEMENT + Timeline.WATCHDOG_MARGIN
	await get_tree().create_timer(limit * 0.5).timeout
	_check(manager.phase == TurnManager.Phase.PLACING,
		"une animation bloquée retient le tour jusqu'à la limite du garde-fou")
	await get_tree().create_timer(limit * 0.5 + 0.2).timeout
	_check(manager.phase == TurnManager.Phase.WAITING_INPUT
		and manager.get_state().current_player == GameState.PLAYER_AI
		and board.card_at(1, 1).scale == Vector2.ONE
		and board.animations.get_child_count() == 0,
		"le garde-fou interrompt l'animation bloquée, nettoie la carte et la partie continue")
	manager.queue_free()
	await get_tree().process_frame


## Une présentation annulée arrête ses tweens ; aucun ne doit rester en mémoire.
func _test_cancelled_tweens_are_released() -> void:
	var state := _state_with_hands([], [])
	_force_instance(state, 0, 0, "fx_plain", GameState.PLAYER_HUMAN)
	var view := BoardView.new()
	view.size = Vector2(900, 900)
	add_child(view)
	view.build()
	view.refresh(state)
	var released: Array = []
	for attempt in range(3):
		var step := CombatPresentation.new(CombatPresentation.Kind.PLACEMENT, 0, 0, GameState.PLAYER_HUMAN)
		view.animations.present(step)
		released.append_array(_weak_tweens(view.animations))
		step.cancel()
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var alive := 0
	for reference in released:
		if reference.get_ref() != null:
			alive += 1
	_check(not released.is_empty() and alive == 0, "les tweens d'une présentation annulée sont libérés")
	view.queue_free()
	await get_tree().process_frame


## Hors de la coroutine : sa variable de boucle ne garde aucun tween en vie.
func _weak_tweens(animations: Node) -> Array:
	var references: Array = []
	for tween in animations._tweens:
		references.append(weakref(tween))
	return references
