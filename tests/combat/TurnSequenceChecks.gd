extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_turn_manager_sequence()
	await _test_pillage_turn_sequence()
	await _test_swarm_turn_sequence()
	await _test_attack_turn_sequence()
	await _test_presentation_acknowledgement()
	await _test_close_during_animation()

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
