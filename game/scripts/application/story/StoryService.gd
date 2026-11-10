## StoryService.gd
## Autoload du scénario. Il charge les dialogues, résout les personnages,
## choisit les déclencheurs, met les séquences en file et conserve l'état
## « déjà vu » dans la progression de campagne. L'affichage est confié à
## StoryLayer : ce service ne crée aucun Control.
extends Node

signal session_started(session: StorySession)
signal session_finished(session: StorySession)
signal event_received(name: String, payload: Dictionary)
signal spotlight_requested(target: Control, prompt: String, show_advance: bool)
signal spotlight_cleared
signal tutorial_step_changed

const LoaderModel := preload("res://scripts/data/story/StoryContentLoader.gd")
const TriggerRulesModel := preload("res://scripts/domain/story/StoryTriggerRules.gd")
const SessionModel := preload("res://scripts/application/story/StorySession.gd")
const DirectorModel := preload("res://scripts/application/story/TutorialDirector.gd")
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")

var _dialogues: Dictionary = {}
var _tutorials: Dictionary = {}
var _problems: Array[String] = []
var _active_session: StorySession = null
var _queue: Array[StorySession] = []
var _anchors: Dictionary = {}
var _memory_states: Dictionary = {}
var _tutorial: TutorialDirector = null
var _pending_event: Dictionary = {}
var _waiting_names: Array = []
var _screen_path: String = ""
## Les tests d'interface démarrent sans onboarding ; le jeu réel le laisse à
## true. Ce n'est pas une option de contenu : le chapitre reste le même.
var auto_start_tutorials: bool = true


func _ready() -> void:
	var content := LoaderModel.read()
	_dialogues = content.get("dialogues", {})
	_tutorials = content.get("tutorials", {})
	_problems.clear()
	for problem in content.get("problems", []):
		_problems.append(str(problem))
	if not _problems.is_empty():
		push_warning("StoryService: %s" % _problems[0])
	_tutorial = DirectorModel.new()
	_tutorial.name = "TutorialDirector"
	_tutorial.setup(self)
	add_child(_tutorial)
	event_received.connect(_on_event_received)


func is_ready() -> bool:
	return _problems.is_empty() and not _dialogues.is_empty()


func problems() -> Array[String]:
	return _problems.duplicate()


func sequences() -> Dictionary:
	return _dialogues.get("sequences", {})


func sequence(sequence_id: String) -> Dictionary:
	var all: Dictionary = _dialogues.get("sequences", {})
	var value: Variant = all.get(sequence_id, {})
	return (value as Dictionary) if value is Dictionary else {}


func sequence_title(sequence_id: String) -> String:
	var entry := sequence(sequence_id)
	var title := str(entry.get("title", ""))
	return title if title != "" else sequence_id.replace("_", " ").capitalize()


func chapters() -> Dictionary:
	return _tutorials.get("chapters", {})


func chapter(chapter_id: String) -> Dictionary:
	var all: Dictionary = _tutorials.get("chapters", {})
	var value: Variant = all.get(chapter_id, {})
	return (value as Dictionary) if value is Dictionary else {}


func play_level_start(node_id: String) -> StorySession:
	var trigger := _first_trigger(node_id, "level_start")
	if trigger.is_empty():
		return null
	return play_sequence(str(trigger.get("sequence", "")), {"trigger": trigger})


func play_sequence(sequence_id: String, options: Dictionary = {}) -> StorySession:
	if not is_ready():
		return null
	var source := sequence(sequence_id)
	if source.is_empty():
		push_warning("StoryService: séquence inconnue '%s'." % sequence_id)
		return null
	var trigger: Dictionary = {}
	if options.get("trigger") is Dictionary:
		trigger = (options.get("trigger") as Dictionary).duplicate(true)
	var session: StorySession = SessionModel.new()
	session.sequence_id = sequence_id
	session.sequence = _prepare_sequence(source)
	session.context = _build_context()
	session.trigger = trigger
	session.replay = bool(options.get("replay", false))
	_queue.append(session)
	_pump()
	return session


func is_playing() -> bool:
	return _active_session != null


func notify_event(name: String, payload: Dictionary = {}) -> void:
	event_received.emit(name, payload)


func wait_for_event(names: Array, timeout: float) -> Dictionary:
	_pending_event = {}
	_waiting_names = names.duplicate()
	var deadline := Time.get_ticks_msec() + int(maxf(0.1, timeout) * 1000.0)
	while _pending_event.is_empty() and Time.get_ticks_msec() < deadline \
			and is_inside_tree():
		await get_tree().process_frame
	_waiting_names.clear()
	var result := _pending_event
	_pending_event = {}
	return result


func register_anchor(anchor_id: String, control: Control) -> void:
	if anchor_id == "" or control == null:
		return
	_anchors[anchor_id] = weakref(control)


func get_anchor(anchor_id: String) -> Control:
	var reference: Variant = _anchors.get(anchor_id)
	if reference == null:
		return null
	var control = reference.get_ref()
	if control == null or not is_instance_valid(control) or not control.is_inside_tree():
		return null
	return control as Control


func start_tutorial_for_node(node_id: String) -> void:
	if not auto_start_tutorials or not is_ready() or _tutorial == null:
		return
	var found := _chapter_for_node(node_id)
	if found.is_empty():
		return
	var chapter_id := str(found.get("id", ""))
	if chapter_id == "" or is_chapter_done(chapter_id) or _tutorial.is_running():
		return
	_tutorial.start(found, _screen_path)


## Un chapitre peut être rattaché à un écran plutôt qu'à un niveau. C'est le
## cas du parcours de Pr. Stone, qui traverse l'accueil, le cabinet, la carte,
## l'avant-combat, le plateau puis le résultat. Chaque scène signale son
## ouverture au service : le directeur reprend l'étape prévue pour elle.
func notify_screen(scene_path: String) -> void:
	if scene_path == "":
		return
	_screen_path = scene_path
	notify_event("screen_opened", {"scene": scene_path})
	if _tutorial == null:
		return
	if _tutorial.is_running():
		_tutorial.notify_screen(scene_path)
		return
	if not auto_start_tutorials or not is_ready():
		return
	var found := _chapter_for_scene(scene_path)
	if found.is_empty():
		return
	var chapter_id := str(found.get("id", ""))
	if chapter_id == "" or is_chapter_done(chapter_id):
		return
	_tutorial.start(found, scene_path)


func start_tutorial_for_scene(scene_path: String) -> void:
	notify_screen(scene_path)


## Le setup de match du tutoriel reste une donnée du chapitre. Une fois le
## chapitre terminé, le même niveau retrouve exactement le setup de campagne.
func match_setup_for_node(node_id: String) -> Dictionary:
	if not is_ready() or _tutorial == null or not _tutorial.is_running():
		return {}
	var found := _chapter_for_node(node_id)
	if found.is_empty():
		found = _chapter_for_match_node(node_id)
	if found.is_empty():
		return {}
	var chapter_id := str(found.get("id", ""))
	if chapter_id == "" or is_chapter_done(chapter_id):
		return {}
	var setup: Variant = found.get("match", {})
	return (setup as Dictionary).duplicate(true) if setup is Dictionary else {}


func stop_tutorial() -> void:
	if _tutorial != null:
		_tutorial.cancel()


func blocks_placement() -> bool:
	return _tutorial != null and _tutorial.blocks_placement()


func selection_allowed(payload: Dictionary) -> bool:
	if _tutorial == null or not _tutorial.is_running():
		return true
	return _tutorial.allows_selection(payload)


func placement_allowed(payload: Dictionary) -> bool:
	if _tutorial == null or not _tutorial.is_running():
		return true
	return _tutorial.allows_placement(payload)


func mark_chapter_done(chapter_id: String) -> void:
	if chapter_id == "":
		return
	_mark_story_state("chapter:%s:done" % chapter_id, true)


func is_chapter_done(chapter_id: String) -> bool:
	return _story_state("chapter:%s:done" % chapter_id)


func replayable_sequences_for_node(node_id: String) -> Array:
	var result: Array = []
	if not is_ready():
		return result
	var triggers: Array = _dialogues.get("triggers", [])
	for value in triggers:
		if not value is Dictionary:
			continue
		var trigger: Dictionary = value
		if str(trigger.get("node_id", "")) != node_id:
			continue
		if not bool(trigger.get("once", true)):
			continue
		var trigger_id := str(trigger.get("id", ""))
		if not _story_state(TriggerRulesModel.state_key(trigger_id)):
			continue
		var sequence_id := str(trigger.get("sequence", ""))
		result.append({
			"id": sequence_id,
			"title": sequence_title(sequence_id),
			"event": str(trigger.get("event", "")),
		})
	return result


func _prepare_sequence(source: Dictionary) -> Dictionary:
	var copy := source.duplicate(true)
	var player_name := PlayerData.player_name
	var lines: Array = copy.get("lines", [])
	for value in lines:
		if value is Dictionary:
			var line: Dictionary = value
			line["text"] = str(line.get("text", "")).replace("{player_name}", player_name)
	return copy


func _build_context() -> Dictionary:
	var characters: Dictionary = {}
	var source: Variant = _dialogues.get("characters", {})
	if source is Dictionary:
		characters = (source as Dictionary).duplicate(true)
	var opponent := GodIdentityModel.bot(BattleContext.effective_opponent_god_id())
	characters["opponent_god"] = {
		"name": str(opponent.get("name", "Sans dieu")),
		"asset": str(opponent.get("asset", "")),
		"color": str(opponent.get("color", "#bdb4ab")),
		"side": "right",
	}
	var player_god := GodIdentityModel.player(PlayerData.player_god_id)
	characters["player_god"] = {
		"name": str(player_god.get("name", "Sans dieu")),
		"asset": str(player_god.get("asset", "")),
		"color": str(player_god.get("color", "#8b5e3c")),
		"side": "left",
	}
	## Le dieu du nœud de campagne parle lui-même dans les réflexions : la
	## politique `theme_god` devient une identité réelle au moment du dialogue.
	var theme_god := _theme_god_character()
	if not theme_god.is_empty():
		characters["theme_god"] = theme_god
	return {
		"characters": characters,
		"player_name": PlayerData.player_name,
	}


## Le dieu de thème du nœud actif. Vide hors campagne ou si le nœud n'en a
## pas : la politique de locuteur reste alors simplement non résolue.
func _theme_god_character() -> Dictionary:
	if BattleContext.campaign_node_id == "" or BattleContext.campaign_service == null:
		return {}
	var node = BattleContext.campaign_service.node(BattleContext.campaign_node_id)
	if node == null:
		return {}
	var god := StoneLoader.get_god(str(node.theme_god_id))
	if god.is_empty():
		return {}
	return {
		"name": str(god.get("name", "")),
		"asset": str(god.get("asset", "")),
		"color": str(god.get("color", "#bdb4ab")),
		"side": "right",
	}


func _first_trigger(node_id: String, event: String) -> Dictionary:
	if not is_ready():
		return {}
	var triggers: Array = _dialogues.get("triggers", [])
	for value in triggers:
		if not value is Dictionary:
			continue
		var trigger: Dictionary = value
		if not TriggerRulesModel.matches(trigger, node_id, event):
			continue
		var trigger_id := str(trigger.get("id", ""))
		if bool(trigger.get("once", true)) \
				and _story_state(TriggerRulesModel.state_key(trigger_id)):
			continue
		return trigger
	return {}


func _pump() -> void:
	if _active_session != null or _queue.is_empty():
		return
	_active_session = _queue.pop_front()
	_active_session.finished.connect(_on_session_finished.bind(_active_session))
	session_started.emit(_active_session)


func _on_session_finished(session: StorySession) -> void:
	if session != _active_session:
		return
	if not session.replay and not session.trigger.is_empty() \
			and bool(session.trigger.get("once", true)):
		_mark_story_state(
			TriggerRulesModel.state_key(str(session.trigger.get("id", ""))), true)
	_active_session = null
	session_finished.emit(session)
	_pump.call_deferred()


func _on_event_received(name: String, payload: Dictionary) -> void:
	if _pending_event.is_empty() and _waiting_names.has(name):
		_pending_event = {"name": name, "payload": payload}


func _chapter_for_node(node_id: String) -> Dictionary:
	var all: Dictionary = _tutorials.get("chapters", {})
	for key in all.keys():
		var value: Variant = all[key]
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		if str(entry.get("entry_node_id", "")) == node_id:
			return entry
	return {}


func _chapter_for_scene(scene_path: String) -> Dictionary:
	var all: Dictionary = _tutorials.get("chapters", {})
	for key in all.keys():
		var value: Variant = all[key]
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		if str(entry.get("entry_scene", "")) == scene_path:
			return entry
	return {}


## Le niveau scénarisé peut différer du point d'entrée du chapitre (le parcours
## commence sur l'accueil mais son match est celui de tuto_01).
func _chapter_for_match_node(node_id: String) -> Dictionary:
	var all: Dictionary = _tutorials.get("chapters", {})
	for key in all.keys():
		var value: Variant = all[key]
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		if str(entry.get("match_node_id", "")) == node_id:
			return entry
	return {}


func _story_state(key: String) -> bool:
	if _memory_states.has(key):
		return bool(_memory_states[key])
	if key == "":
		return false
	var service := CampaignContext.get_service()
	if service != null and service.is_ready():
		return bool(service.progress().story_states.get(key, false))
	return false


func _mark_story_state(key: String, value: bool) -> void:
	if key == "":
		return
	var service := CampaignContext.get_service()
	if service != null and service.is_ready():
		var error := service.mark_story_state(key, value)
		if error != OK:
			push_warning("StoryService: état '%s' non enregistré (%s)." % [
				key, error_string(error)])
			return
	_memory_states[key] = value
