## TutorialDirector.gd
## Exécute un chapitre guidé à travers plusieurs scènes. Une étape est liée à
## une scène, éventuellement à une ancre, et avance sur un geste réel. Le
## directeur ne dessine rien et ne connaît ni le plateau ni les menus : il ne
## voit que des identifiants d'ancres, des événements et leurs propriétés.
##
## Aucune attente n'expire : une étape reste en place tant que le joueur n'a
## pas fait le geste demandé, même après un long moment d'inactivité ou un
## passage de l'application en arrière-plan. Seul `cancel()` interrompt un
## chapitre, et seul un chapitre mené jusqu'au bout est marqué comme acquis :
## fermer le jeu avant la fin le fait reprendre au début, jamais après.
class_name TutorialDirector
extends Node

## Drapeau d'étape : le chapitre est acquis dès ce geste, même si un dialogue
## de conclusion reste à lire (l'échange de carte clôt le parcours guidé).
const COMPLETE_KEY := "complete_chapter"
## Pauses de lisibilité du parcours guidé : le joueur voit l'écran avant
## qu'une prise de parole ou une cible ne s'impose. Une étape peut les
## surcharger avec sa clé `beat`.
const DEFAULT_DIALOGUE_BEAT := 0.65
const DEFAULT_ACTION_BEAT := 0.5
## Clé interne : la cible guidée a disparu avant le geste attendu.
const TARGET_LOST_KEY := "__target_lost"
## Un changement de scène retire l'ancre de navigation du menu sortant avant
## que l'écran entrant ne publie `screen_opened` : la perte d'ancre n'est donc
## conclue qu'après quelques frames. Sans cette grâce, l'étape qui vient
## précisément de réussir la transition serait abandonnée avant son événement.
const ANCHOR_LOST_GRACE_FRAMES := 4

## Surchargeables par les tests pour ne pas dépendre d'un rythme réel.
var dialogue_beat := DEFAULT_DIALOGUE_BEAT
var action_beat := DEFAULT_ACTION_BEAT

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
var _beat_active := false
## Une pause interrompue ne doit pas éteindre le verrou d'une pause suivante
## quand sa minuterie se réveille plus tard.
var _beat_generation := 0
## Identifiant de l'exécution courante. Une coroutine d'un chapitre annulé
## peut se réveiller après le démarrage du suivant : elle doit alors se taire au
## lieu d'avancer ou de terminer le nouveau chapitre.
var _run_generation := 0
## Un dialogue ou une pause déjà vus ne sont pas rejoués quand la même étape
## repart après la disparition de son ancre.
var _step_dialogue_done := false
var _step_action_beat_done := false


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
	_beat_active = false
	_run_generation += 1
	_beat_generation += 1
	_step_dialogue_done = false
	_step_action_beat_done = false
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
	_run_generation += 1
	_beat_generation += 1
	_beat_active = false
	_step_dialogue_done = false
	_step_action_beat_done = false
	if _service != null:
		## Une attente devenue sans limite ne doit pas survivre au chapitre
		## qu'elle servait, sinon elle consommerait les gestes du suivant.
		_service.tutorial_beat_ended.emit()
		_service.cancel_waits()
		_service.spotlight_cleared.emit()
		_service.tutorial_step_changed.emit()


func is_running() -> bool:
	return _running


## Chapitre en cours (vide hors exécution). Les écrans s'en servent pour
## n'appliquer un traitement qu'au parcours concerné.
func chapter_id() -> String:
	return str(_chapter.get("id", ""))


## Pendant une étape guidée, le joueur ne doit pas pouvoir poser une carte par
## un glissement ou un raccourci. Les étapes qui attendent explicitement une
## pose restent, elles, compatibles avec le plateau. Une attente sans consigne
## (résolution d'ancre, dialogue) ne verrouille jamais le plateau : le joueur
## ne doit pas se retrouver bloqué sans cible visible.
func blocks_placement() -> bool:
	if _beat_active:
		return true
	if not _running or not _waiting or _current_step.is_empty():
		return false
	if _wait_for == "":
		return false
	return _wait_for != "monster_placed" and _wait_for != "cell_pressed"


## La sélection n'est acceptée que si l'étape courante l'attend et si la carte
## correspond à `expect`. Un simple blocage global ne suffirait pas : il
## laisserait le joueur sélectionner la mauvaise carte.
func allows_selection(payload: Dictionary) -> bool:
	if _beat_active:
		return false
	if not _running or not _waiting or _wait_for != "card_selected":
		return false
	return _expect_matches(payload)


## Même principe pour la pose : la case et le monstre doivent correspondre au
## plan du chapitre. Hors tutoriel, StoryService laisse toujours passer.
func allows_placement(payload: Dictionary) -> bool:
	if _beat_active:
		return false
	if not _running or not _waiting or _wait_for != "monster_placed":
		return false
	return _expect_matches(payload)


func _run_current_step() -> void:
	if not _running or _canceled or _waiting:
		return
	var generation := _run_generation
	if _step_index >= _steps.size():
		await _finish_chapter(generation)
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
	if dialogue != "" and not _step_dialogue_done:
		_step_dialogue_done = true
		await _beat(DEFAULT_DIALOGUE_BEAT)
		if not _is_current(generation):
			return
		await _play(dialogue)
		if not _is_current(generation):
			return
	var anchor_id := str(step.get("anchor", ""))
	var target: Control = null
	if anchor_id != "":
		target = await _wait_for_anchor(anchor_id, step_scene, generation)
		if not _is_current(generation):
			return
		if target == null:
			# La scène a changé pendant l'attente : l'étape reste à faire et
			# sera relancée quand le joueur reviendra sur cet écran.
			_release_step(generation)
			return
	var wait_for := str(step.get("wait_for", ""))
	var spot := bool(step.get("spotlight", true)) and target != null
	if wait_for == "":
		_advance_step(generation)
		return
	_wait_for = wait_for
	_service.tutorial_step_changed.emit()
	if spot:
		if not _step_action_beat_done:
			_step_action_beat_done = true
			await _beat(DEFAULT_ACTION_BEAT)
			if not _is_current(generation):
				return
		_service.spotlight_requested.emit(target, str(step.get("prompt", "")),
			wait_for == "tutorial_advance")
	var event: Dictionary = await _wait_for_expected(wait_for, anchor_id, generation)
	if not _is_current(generation):
		return
	if bool(event.get(TARGET_LOST_KEY, false)):
		_rewait_step(spot, generation)
		return
	if spot:
		_service.spotlight_cleared.emit()
	_wait_for = ""
	_service.tutorial_step_changed.emit()
	if event.is_empty():
		_release_step(generation)
		return
	_advance_step(generation)


## Une coroutine d'une exécution révolue ne doit plus rien changer : c'est ce
## qui empêche un ancien dialogue de faire avancer le chapitre suivant.
func _is_current(generation: int) -> bool:
	return generation == _run_generation and _running and not _canceled


## Pause de lisibilité avant une prise de parole ou une action guidée. Le
## bouclier d'entrées appartient à StoryLayer ; le directeur ne fait que
## demander le temps et bloquer ses propres gestes pendant celui-ci.
func _beat(default_seconds: float) -> void:
	if _service == null:
		return
	var seconds := float(_current_step.get("beat", default_seconds))
	if seconds <= 0.0:
		return
	_beat_generation += 1
	var generation := _beat_generation
	_beat_active = true
	_service.tutorial_beat_requested.emit(seconds)
	await get_tree().create_timer(seconds).timeout
	if generation != _beat_generation:
		return
	_beat_active = false
	if not _canceled:
		_service.tutorial_beat_ended.emit()


## Même étape, même consigne : la cible guidée a disparu, on remet l'attente en
## place sans avancer ni rejouer le dialogue ou la pause déjà vus.
func _rewait_step(spotlight: bool, generation: int) -> void:
	if generation != _run_generation:
		return
	if spotlight:
		_service.spotlight_cleared.emit()
	_wait_for = ""
	_service.tutorial_step_changed.emit()
	_waiting = false
	_current_step = {}
	_run_current_step()


## Consomme l'étape courante. Un chapitre ne revient jamais en arrière : l'index
## n'avance que lorsque le geste attendu est reçu.
func _advance_step(generation: int) -> void:
	if generation != _run_generation:
		return
	if bool(_current_step.get(COMPLETE_KEY, false)):
		_service.mark_chapter_done(chapter_id())
	_waiting = false
	_current_step = {}
	_step_dialogue_done = false
	_step_action_beat_done = false
	_step_index += 1
	_run_current_step()


## Rend l'étape au prochain `notify_screen()` sans toucher à l'index : le
## joueur retrouve la même consigne en revenant sur l'écran, jamais un chapitre
## reparti de zéro.
func _release_step(generation: int) -> void:
	if generation != _run_generation or not _running:
		return
	_wait_for = ""
	_waiting = false
	_current_step = {}
	_step_dialogue_done = false
	_step_action_beat_done = false
	_service.tutorial_step_changed.emit()


## Attend le bon événement, sans limite de temps : le joueur peut lire,
## réfléchir ou laisser l'application en arrière-plan, l'étape reste en place.
## Un geste qui ne correspond pas à `expect` ne consomme pas l'étape.
func _wait_for_expected(event_name: String, anchor_id: String,
		generation: int) -> Dictionary:
	var missing_frames := 0
	while _is_current(generation):
		# Le geste est lu avant de conclure à la perte de l'ancre : un appui qui
		# ferme lui-même sa cible reste un geste valide. La surveillance se fait
		# à la frame, jamais sur une horloge réelle.
		var event: Dictionary = _service.take_event([event_name])
		if not event.is_empty():
			var payload: Dictionary = {}
			if event.get("payload") is Dictionary:
				payload = (event.get("payload") as Dictionary).duplicate(true)
			if _expect_matches(payload):
				return event
		if not _running or _canceled:
			return {}
		if anchor_id != "" and _service.get_anchor(anchor_id) == null:
			missing_frames += 1
			if missing_frames >= ANCHOR_LOST_GRACE_FRAMES:
				return {TARGET_LOST_KEY: true}
		else:
			missing_frames = 0
		await get_tree().process_frame
	return {}


## Vrai pendant une pause de lisibilité : les écrans qui écoutent `_input`
## avant le GUI peuvent ainsi refuser les gestes, comme le bouclier visuel.
func is_beat_active() -> bool:
	return _beat_active


## Ancre de l'étape réellement en attente d'un geste. Vide hors guidage : un
## écran ne protège un panneau que lorsqu'une consigne le met en surbrillance.
func guided_anchor_id() -> String:
	if not _running or not _waiting or _current_step.is_empty() or _wait_for == "":
		return ""
	return str(_current_step.get("anchor", ""))


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


## L'ancre est le vrai Control de la scène, jamais une copie. L'attente n'a pas
## de limite tant que la scène de l'étape est ouverte ; si le joueur va
## ailleurs, l'étape est rendue à `notify_screen()` au lieu d'être abandonnée.
func _wait_for_anchor(anchor_id: String, step_scene: String,
		generation: int) -> Control:
	while _is_current(generation):
		if step_scene != "" and step_scene != _scene:
			return null
		var target: Control = _service.get_anchor(anchor_id)
		if target != null:
			# Laisser une frame au layout pour que le spotlight vise la position
			# réelle de la carte, pas sa position de construction.
			await get_tree().process_frame
			return target
		await get_tree().process_frame
	return null


func _finish_chapter(generation: int) -> void:
	var outro := str(_chapter.get("outro", ""))
	if outro != "":
		await _play(outro)
		if not _is_current(generation):
			return
	_finish(generation)


## Seule une exécution menée jusqu'au bout marque le chapitre comme acquis ;
## une interruption laisse la progression intacte pour la prochaine session.
func _finish(generation: int) -> void:
	if generation != _run_generation or _canceled:
		return
	var finished_chapter := chapter_id()
	_running = false
	_waiting = false
	_wait_for = ""
	_current_step = {}
	_steps = []
	_run_generation += 1
	_beat_generation += 1
	_beat_active = false
	_step_dialogue_done = false
	_step_action_beat_done = false
	if _service != null:
		_service.tutorial_beat_ended.emit()
		_service.cancel_waits()
		_service.spotlight_cleared.emit()
		_service.tutorial_step_changed.emit()
		_service.mark_chapter_done(finished_chapter)
	_chapter = {}
