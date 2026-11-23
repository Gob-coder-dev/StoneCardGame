## Rythme du parcours guidé : chaque prise de parole et chaque action sont
## précédées d'une pause de lisibilité pendant laquelle les entrées sont
## bloquées. Une cible qui disparaît remet la même étape en place, sans avancer
## ni rejouer le dialogue déjà vu.
extends "res://tests/support/CombatTestSuite.gd"

const SCENE := "res://scenes/menus/MainMenu.tscn"
const TARGET_ANCHOR := "beat.target"
const FAST_BEAT := 0.12


func run() -> void:
	await _clear_dialogue()
	StoryService.stop_tutorial()
	var saved_auto := StoryService.auto_start_tutorials
	var saved_dialogue := StoryService._tutorial.dialogue_beat
	var saved_action := StoryService._tutorial.action_beat
	StoryService.auto_start_tutorials = false
	StoryService._tutorial.dialogue_beat = FAST_BEAT
	StoryService._tutorial.action_beat = FAST_BEAT
	await _test_dialogue_beat()
	await _test_action_beat()
	await _test_cancel_releases_shield()
	await _test_lost_target_rearms()
	await _test_scene_transition_keeps_step()
	await _clear_dialogue()
	StoryService.stop_tutorial()
	StoryService._tutorial.dialogue_beat = saved_dialogue
	StoryService._tutorial.action_beat = saved_action
	StoryService.auto_start_tutorials = saved_auto


func _wait_until(predicate: Callable, frames: int = 240) -> bool:
	for _frame in range(frames):
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())


## Une suite précédente peut laisser une séquence ouverte : le rythme se mesure
## sur un overlay réellement libre.
func _clear_dialogue() -> void:
	for _line in range(12):
		if not StoryLayer._dialogue.visible:
			return
		StoryLayer._dialogue._typing = false
		StoryLayer._dialogue._advance()
		await get_tree().process_frame


func _test_dialogue_beat() -> void:
	var chapter := {
		"id": "beat_dialogue",
		"steps": [{
			"id": "talk",
			"scene": SCENE,
			"dialogue": "journey_welcome",
			"spotlight": false,
			"wait_for": "tutorial_advance",
		}],
	}
	StoryService._tutorial.start(chapter, SCENE)
	_check(not StoryLayer._dialogue.visible
		and StoryService.is_tutorial_beat_active(),
		"rythme : le dialogue attend la fin de la pause de lisibilité")
	_check(StoryLayer._shield.visible
		and StoryLayer._shield.mouse_filter == Control.MOUSE_FILTER_STOP,
		"rythme : un bouclier plein écran bloque les gestes pendant la pause")
	_check(StoryService.blocks_placement()
		and not StoryService.selection_allowed({"monster_id": "gueule_de_travers_n1"}),
		"rythme : la sélection et la pose sont refusées pendant la pause")
	var opened := await _wait_until(func() -> bool: return StoryLayer._dialogue.visible)
	_check(opened and not StoryService.is_tutorial_beat_active()
		and not StoryLayer._shield.visible,
		"rythme : le dialogue s'ouvre et les entrées sont rendues après la pause")
	await _clear_dialogue()
	StoryService.stop_tutorial()
	_check(not StoryLayer._shield.visible,
		"rythme : arrêter le chapitre retire le bouclier")


func _test_action_beat() -> void:
	var target := _make_target(Vector2(400, 900))
	StoryService.register_anchor(TARGET_ANCHOR, target)
	var chapter := {
		"id": "beat_action",
		"steps": [{
			"id": "act",
			"scene": SCENE,
			"anchor": TARGET_ANCHOR,
			"prompt": "Touche la cible.",
			"wait_for": "tutorial_advance",
		}],
	}
	StoryService._tutorial.start(chapter, SCENE)
	# La résolution d'ancre cède une frame au layout avant la pause.
	await get_tree().process_frame
	_check(StoryService.is_tutorial_beat_active()
		and not StoryLayer._spotlight.visible,
		"rythme : la cible guidée attend aussi la fin de la pause")
	var shown := await _wait_until(func() -> bool:
		return StoryLayer._spotlight.visible and StoryLayer._spotlight._target == target)
	_check(shown and not StoryService.is_tutorial_beat_active(),
		"rythme : le spotlight n'apparaît qu'après la pause")
	_check(StoryService.is_guiding_anchor(TARGET_ANCHOR),
		"rythme : l'ancre guidée est exposée en lecture seule aux écrans")
	target.queue_free()
	await get_tree().process_frame
	StoryService.stop_tutorial()


func _test_cancel_releases_shield() -> void:
	StoryService._tutorial.dialogue_beat = 0.5
	var chapter := {
		"id": "beat_cancel",
		"steps": [{
			"id": "talk",
			"scene": SCENE,
			"dialogue": "journey_welcome",
			"spotlight": false,
			"wait_for": "tutorial_advance",
		}],
	}
	StoryService._tutorial.start(chapter, SCENE)
	var holding := StoryService.is_tutorial_beat_active()
	StoryService.stop_tutorial()
	_check(holding and not StoryService.is_tutorial_beat_active()
		and not StoryLayer._shield.visible,
		"rythme : annuler une pause ne laisse jamais les entrées bloquées")
	var next := {
		"id": "beat_after_cancel",
		"steps": [{
			"id": "talk",
			"scene": SCENE,
			"dialogue": "journey_welcome",
			"spotlight": false,
			"wait_for": "tutorial_advance",
		}],
	}
	StoryService._tutorial.start(next, SCENE)
	_check(StoryService.is_tutorial_beat_active(),
		"rythme : la minuterie annulée n'éteint pas la pause suivante")
	StoryService.stop_tutorial()
	await _clear_dialogue()
	StoryService._tutorial.dialogue_beat = FAST_BEAT


func _test_lost_target_rearms() -> void:
	var target := _make_target(Vector2(420, 820))
	StoryService.register_anchor(TARGET_ANCHOR, target)
	var chapter := {
		"id": "beat_rearm",
		"steps": [{
			"id": "act",
			"scene": SCENE,
			"anchor": TARGET_ANCHOR,
			"prompt": "Touche la cible.",
			"wait_for": "tutorial_advance",
		}],
	}
	StoryService._tutorial.start(chapter, SCENE)
	var shown := await _wait_until(func() -> bool: return StoryLayer._spotlight.visible)
	target.queue_free()
	await get_tree().process_frame
	var lost := await _wait_until(func() -> bool:
		return not StoryLayer._spotlight.visible \
			and StoryService._tutorial._wait_for == "")
	_check(shown and lost,
		"rythme : une cible disparue retire le spotlight sans valider l'étape")
	var replacement := _make_target(Vector2(420, 900))
	StoryService.register_anchor(TARGET_ANCHOR, replacement)
	var rearmed := await _wait_until(func() -> bool:
		return StoryLayer._spotlight.visible \
			and StoryLayer._spotlight._target == replacement)
	_check(rearmed and StoryService._tutorial._step_index == 0
		and StoryService._tutorial.chapter_id() == "beat_rearm",
		"rythme : la cible revenue remet la même consigne sans avancer l'étape")
	StoryService.stop_tutorial()
	replacement.queue_free()
	await get_tree().process_frame


## Un changement de scène retire l'ancre de navigation de l'écran sortant
## avant que l'écran entrant ne publie `screen_opened`. L'étape doit lire cet
## événement, et non s'abandonner sur la disparition de son bouton : c'est ce
## qui laissait le parcours figé dès l'ouverture du deck.
func _test_scene_transition_keeps_step() -> void:
	var navigation := _make_target(Vector2(400, 1600))
	StoryService.register_anchor(TARGET_ANCHOR, navigation)
	var next_scene := "res://scenes/menus/CollectionScreen.tscn"
	var chapter := {
		"id": "beat_transition",
		"steps": [
			{
				"id": "navigate",
				"scene": SCENE,
				"anchor": TARGET_ANCHOR,
				"prompt": "Ouvre l'écran.",
				"wait_for": "screen_opened",
				"expect": {"scene": next_scene},
			},
			# L'étape suivante garde le chapitre ouvert : le test n'écrit aucun
			# état de progression dans la campagne du joueur.
			{
				"id": "arrived",
				"scene": next_scene,
				"spotlight": false,
				"wait_for": "tutorial_advance",
			},
		],
	}
	StoryService._tutorial.start(chapter, SCENE)
	var shown := await _wait_until(func() -> bool: return StoryLayer._spotlight.visible)
	# L'écran sortant libère son bouton avant que l'écran entrant ne signale
	# son ouverture : une frame sépare les deux, comme dans le jeu réel.
	navigation.queue_free()
	await get_tree().process_frame
	StoryService.notify_screen(next_scene)
	var advanced := await _wait_until(func() -> bool:
		return str(StoryService._tutorial._current_step.get("id", "")) == "arrived", 60)
	_check(shown and advanced,
		"rythme : une transition d'écran ne fait pas perdre l'étape qui la valide")
	StoryService.stop_tutorial()
	await get_tree().process_frame


func _make_target(at: Vector2) -> Control:
	var target := Control.new()
	target.position = at
	target.size = Vector2(220, 140)
	add_child(target)
	return target
