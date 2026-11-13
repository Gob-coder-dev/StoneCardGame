## ConfirmPopup.gd
## Confirmation modale commune. Elle ne décide de rien : elle émet `confirmed`
## ou `cancelled`. Un clic à côté de la carte annule, comme le bouton retour.
class_name ConfirmPopup
extends Control

signal confirmed
signal cancelled

@onready var card: PanelContainer = $Center/Card
@onready var message_label: Label = $Center/Card/Content/Message
@onready var no_btn: Button = $Center/Card/Content/Actions/NoButton
@onready var yes_btn: Button = $Center/Card/Content/Actions/YesButton

var _open := false


func _ready() -> void:
	visible = false
	no_btn.pressed.connect(_cancel)
	yes_btn.pressed.connect(_confirm)
	yes_btn.add_theme_color_override("font_color", UITheme.COL_DANGER)
	card.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.COL_SURFACE, UITheme.COL_DANGER, 3, 22))


func open(text: String) -> void:
	message_label.text = text
	_open = true
	visible = true
	no_btn.grab_focus()


func is_open() -> bool:
	return _open


## Fermeture sans décision : utilisée par le bouton retour.
func dismiss() -> void:
	if not _open:
		return
	close()
	cancelled.emit()


func close() -> void:
	_open = false
	visible = false


func _confirm() -> void:
	if not _open:
		return
	close()
	confirmed.emit()


func _cancel() -> void:
	if not _open:
		return
	close()
	cancelled.emit()


## Seul l'appui qui atteint la racine est un appui hors de la carte : les
## enfants de la carte consomment les leurs. Le toucher est traité comme la
## souris afin que le geste annule aussi la confirmation sur téléphone.
func _gui_input(event: InputEvent) -> void:
	if not _open:
		return
	var click := event as InputEventMouseButton
	var touch := event as InputEventScreenTouch
	if (click != null and click.pressed) or (touch != null and touch.pressed):
		dismiss()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		dismiss()
		get_viewport().set_input_as_handled()
