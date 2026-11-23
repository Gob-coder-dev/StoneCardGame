## TutorialInputShield.gd
## Bouclier d'entrées du rythme guidé : plein écran et invisible, il absorbe
## pointeur et clavier pendant la courte pause qui précède un dialogue ou une
## action. Il possède sa propre échéance : une étape interrompue ne peut pas
## laisser le jeu verrouillé. Il ne connaît aucun contenu et ne décide rien.
class_name TutorialInputShield
extends Control

signal expired

var _remaining := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	visible = false
	set_process(false)


## Bloque les entrées pendant `seconds`. Une durée nulle libère aussitôt.
func hold(seconds: float) -> void:
	if seconds <= 0.0:
		release()
		return
	_remaining = seconds
	visible = true
	set_process(true)
	if is_inside_tree():
		grab_focus()


func release() -> void:
	_remaining = 0.0
	if has_focus():
		release_focus()
	visible = false
	set_process(false)


func is_holding() -> bool:
	return visible and _remaining > 0.0


func _process(delta: float) -> void:
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining > 0.0:
		return
	release()
	expired.emit()


## Absorbe les appuis et les glissements : aucun widget situé dessous ne doit
## réagir pendant la pause.
func _gui_input(event: InputEvent) -> void:
	accept_event()


## Le GUI ne couvre pas les raccourcis clavier et manette : ils sont consommés
## ici tant que le bouclier est actif.
func _input(event: InputEvent) -> void:
	if not is_holding():
		return
	get_viewport().set_input_as_handled()
