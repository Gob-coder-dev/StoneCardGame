## StoryLayer.gd
## Couche d'affichage du scénario, au-dessus de toutes les scènes. Elle relie
## StoryService aux deux overlays et referme la session quand le joueur a lu la
## dernière ligne. Elle ne connaît aucun nœud de campagne.
extends CanvasLayer

const DialogueModel := preload("res://scripts/ui/story/DialogueOverlay.gd")
const SpotlightModel := preload("res://scripts/ui/story/SpotlightOverlay.gd")
const ShieldModel := preload("res://scripts/ui/story/TutorialInputShield.gd")

var _dialogue: DialogueOverlay = null
var _spotlight: SpotlightOverlay = null
var _shield: TutorialInputShield = null
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
	# Ajouté en dernier : le bouclier couvre les deux overlays pendant la pause.
	_shield = ShieldModel.new()
	_shield.name = "TutorialInputShield"
	add_child(_shield)
	StoryService.session_started.connect(_on_session_started)
	StoryService.spotlight_requested.connect(_on_spotlight_requested)
	StoryService.spotlight_cleared.connect(_on_spotlight_cleared)
	StoryService.tutorial_beat_requested.connect(_on_beat_requested)
	StoryService.tutorial_beat_ended.connect(_on_beat_ended)


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
	# Une séquence encore active n'a pas été refermée : l'étape suivante a
	# repris la main (chapitre interrompu, test qui saute une étape). La
	# terminer évite qu'elle bloque définitivement la file des dialogues.
	if _session != null:
		var interrupted: StorySession = _session
		_session = null
		_dialogue.hide_overlay()
		interrupted.finish()
	_spotlight.show_target(target, prompt, show_advance)


func _on_spotlight_cleared() -> void:
	_spotlight.hide_spotlight()


## La pause est purement visuelle : le directeur tient le rythme, ce bouclier
## empêche seulement le joueur d'agir avant d'avoir vu l'écran.
func _on_beat_requested(seconds: float) -> void:
	_shield.hold(seconds)


func _on_beat_ended() -> void:
	_shield.release()


## Le bouton n'agit pas directement sur le directeur : il publie le même
## événement qu'un geste réel. Le scénario reste ainsi la seule autorité.
func _on_advance_requested() -> void:
	StoryService.notify_event("tutorial_advance")
