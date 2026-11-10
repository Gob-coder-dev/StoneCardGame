## StoryLayer.gd
## Couche d'affichage du scénario, au-dessus de toutes les scènes. Elle relie
## StoryService aux deux overlays et referme la session quand le joueur a lu la
## dernière ligne. Elle ne connaît aucun nœud de campagne.
extends CanvasLayer

const DialogueModel := preload("res://scripts/ui/story/DialogueOverlay.gd")
const SpotlightModel := preload("res://scripts/ui/story/SpotlightOverlay.gd")

var _dialogue: DialogueOverlay = null
var _spotlight: SpotlightOverlay = null
var _session: StorySession = null


func _ready() -> void:
	layer = 100
	_dialogue = DialogueModel.new()
	_dialogue.name = "DialogueOverlay"
	add_child(_dialogue)
	_dialogue.closed.connect(_on_dialogue_closed)
	_spotlight = SpotlightModel.new()
	_spotlight.name = "SpotlightOverlay"
	add_child(_spotlight)
	_spotlight.advance_requested.connect(_on_advance_requested)
	StoryService.session_started.connect(_on_session_started)
	StoryService.spotlight_requested.connect(_on_spotlight_requested)
	StoryService.spotlight_cleared.connect(_on_spotlight_cleared)


func _on_session_started(session: StorySession) -> void:
	_session = session
	_spotlight.hide_spotlight()
	_dialogue.show_session(session)


func _on_dialogue_closed() -> void:
	if _session == null:
		return
	var finished: StorySession = _session
	_session = null
	finished.finish()


func _on_spotlight_requested(target: Control, prompt: String, show_advance: bool) -> void:
	_dialogue.hide_overlay()
	_spotlight.show_target(target, prompt, show_advance)


func _on_spotlight_cleared() -> void:
	_spotlight.hide_spotlight()


## Le bouton n'agit pas directement sur le directeur : il publie le même
## événement qu'un geste réel. Le scénario reste ainsi la seule autorité.
func _on_advance_requested() -> void:
	StoryService.notify_event("tutorial_advance")
