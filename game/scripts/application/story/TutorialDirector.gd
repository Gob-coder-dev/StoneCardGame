## TutorialDirector.gd
## Exécute un chapitre guidé à travers plusieurs scènes. Une étape est liée à
## une scène, éventuellement à une ancre, et avance sur un geste réel. Le
## directeur ne dessine rien et ne connaît ni le plateau ni les menus : il ne
## voit que des identifiants d'ancres, des événements et leurs propriétés.
class_name TutorialDirector
extends Node

var _service: Node = null
var _chapter: Dictionary = {}
var _steps: Array = []
var _step_index := 0
var _scene := ""
var _running := false
var _canceled := false
var _waiting := false
var _wait_for := ""
var _current_step: Dictionary = {}


func setup(service: Node) -> void:
	_service = service


## `scene_path` est la scène déjà ouverte quand le chapitre démarre. Les étapes
## des autres scènes attendent leur `notify_screen`, sans jamais bloquer la
## navigation du joueur.
func start(chapter: Dictionary, scene_path: String = "") -> void:
	if _running or chapter.is_empty() or _service == null:
		return
	_chapter = chapter.duplicate(true)
	_steps = _chapter.get("steps", [])
	_step_index = 0
	_scene = scene_path
	_running = true
	_canceled = false
	_waiting = false
	_wait_for = ""
	_current_step = {}
	_run_current_step()


func notify_screen(scene_path: String) -> void:
	if not _running:
		return
	_scene = scene_path
	if _waiting:
		return
	_run_current_step()


func cancel() -> void:
	_canceled = true
	_running = false
	_waiting = false
	_wait_for = ""
	_current_step = {}
	_steps = []
	_chapter = {}
	if _service != null:
		_service.spotlight_cleared.emit()
		_service.tutorial_step_changed.emit()


func is_running() -> bool:
	return _running


## Pendant une étape guidée, le joueur ne doit pas pouvoir poser une carte par
## un glissement ou un raccourci. Les étapes qui attendent explicitement une
## pose restent, elles, compatibles avec le plateau.
func blocks_placement() -> bool:
	if not _running or not _waiting or _current_step.is_empty():
		return false
	return _wait_for != "stone_placed" and _wait_for != "cell_pressed"


## La sélection n'est acceptée que si l'étape courante l'attend et si la carte
## correspond à `expect`. Un simple blocage global ne suffirait pas : il
## laisserait le joueur sélectionner la mauvaise carte.
func allows_selection(payload: Dictionary) -> bool:
	if not _running or not _waiting or _wait_for != "card_selected":
		return false
	return _expect_matches(payload)


## Même principe pour la pose : la case et la pierre doivent correspondre au
## plan du chapitre. Hors tutoriel, StoryService laisse toujours passer.
func allows_placement(payload: Dictionary) -> bool:
	if not _running or not _waiting or _wait_for != "stone_placed":
		return false
	return _expect_matches(payload)


func _run_current_step() -> void:
	if not _running or _canceled or _waiting:
		return
	if _step_index >= _steps.size():
		await _finish_chapter()
		return
	var value: Variant = _steps[_step_index]
	if not value is Dictionary:
		_step_index += 1
		_run_current_step()
		return
	var step: Dictionary = value
	var step_scene := str(step.get("scene", ""))
	if step_scene != "" and step_scene != _scene:
		# Le chapitre reste vivant : la scène suivante le relancera via
		# StoryService.notify_screen().
		return
	_waiting = true
	_current_step = step
	var dialogue := str(step.get("dialogue", ""))
	if dialogue != "":
		await _play(dialogue)
		if _canceled:
			return
		if not _running:
			return
	var anchor_id := str(step.get("anchor", ""))
	var target: Control = null
	if anchor_id != "":
		target = await _wait_for_anchor(anchor_id, float(step.get("timeout", 20.0)))
		if _canceled:
			return
		if target == null:
			push_warning("TutorialDirector: ancre introuvable '%s'." % anchor_id)
			_finish(false)
			return
	var wait_for := str(step.get("wait_for", ""))
	var spotlight := bool(step.get("spotlight", true)) and target != null
	if wait_for != "":
		_wait_for = wait_for
		_service.tutorial_step_changed.emit()
		if spotlight:
			_service.spotlight_requested.emit(target, str(step.get("prompt", "")),
				wait_for == "tutorial_advance")
		var event: Dictionary = await _wait_for_expected(wait_for,
			float(step.get("timeout", 20.0)))
		if _canceled:
			return
		_wait_for = ""
		if spotlight:
			_service.spotlight_cleared.emit()
		_service.tutorial_step_changed.emit()
		if event.is_empty():
			push_warning("TutorialDirector: action '%s' non reçue (étape '%s')." % [
				wait_for, str(step.get("id", ""))])
			_finish(false)
			return
	_waiting = false
	_current_step = {}
	_step_index += 1
	_run_current_step()


## Attend le bon événement, en ignorant les gestes qui ne correspondent pas à
## la cible. Un mauvais choix ne consomme donc pas l'étape ni son délai.
func _wait_for_expected(name: String, timeout: float) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(maxf(0.1, timeout) * 1000.0)
	while not _canceled and Time.get_ticks_msec() < deadline:
		var remaining := float(deadline - Time.get_ticks_msec()) / 1000.0
		var event: Dictionary = await _service.wait_for_event([name], maxf(0.1, remaining))
		if event.is_empty():
			return {}
		var payload: Dictionary = {}
		if event.get("payload") is Dictionary:
			payload = (event.get("payload") as Dictionary).duplicate(true)
		if _expect_matches(payload):
			return event
	return {}


func _expect_matches(payload: Dictionary) -> bool:
	var expected: Variant = _current_step.get("expect", {})
	if not expected is Dictionary or (expected as Dictionary).is_empty():
		return true
	for key in (expected as Dictionary).keys():
		if not payload.has(key):
			return false
		var wanted: Variant = (expected as Dictionary)[key]
		var actual: Variant = payload[key]
		if wanted is int or wanted is float:
			if int(actual) != int(wanted):
				return false
		elif str(actual) != str(wanted):
			return false
	return true


func _play(sequence_id: String) -> void:
	var session = _service.play_sequence(sequence_id)
	if session == null:
		return
	await session.finished


func _wait_for_anchor(anchor_id: String, timeout: float) -> Control:
	var deadline := Time.get_ticks_msec() + int(maxf(0.1, timeout) * 1000.0)
	while not _canceled and Time.get_ticks_msec() < deadline:
		var target: Control = _service.get_anchor(anchor_id)
		if target != null:
			# Laisser une frame au layout pour que le spotlight vise la position
			# réelle de la carte, pas sa position de construction.
			await get_tree().process_frame
			return target
		await get_tree().process_frame
	return null


func _finish_chapter() -> void:
	var outro := str(_chapter.get("outro", ""))
	if outro != "":
		await _play(outro)
		if _canceled:
			return
	_finish(true)


func _finish(success: bool) -> void:
	if _canceled:
		return
	_running = false
	_waiting = false
	_wait_for = ""
	_current_step = {}
	_steps = []
	if _service != null:
		_service.spotlight_cleared.emit()
		_service.tutorial_step_changed.emit()
	if success:
		_service.mark_chapter_done(str(_chapter.get("id", "")))
	_chapter = {}
