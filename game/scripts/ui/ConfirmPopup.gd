## ConfirmPopup.gd
## Confirmation modale commune. Elle ne décide de rien : elle émet `confirmed`
## ou `cancelled`. Un clic à côté de la carte annule, comme le bouton retour.
class_name ConfirmPopup
extends Control

signal confirmed
signal cancelled

const FocusScope := preload("res://scripts/ui/input/FocusScope.gd")

@onready var card: PanelContainer = $Center/Card
@onready var message_label: Label = $Center/Card/Content/Message
@onready var no_btn: Button = $Center/Card/Content/Actions/NoButton
@onready var yes_btn: Button = $Center/Card/Content/Actions/YesButton

var _open := false
var _focus := FocusScope.new()


func _ready() -> void:
	visible = false
	no_btn.pressed.connect(_cancel)
	yes_btn.pressed.connect(_confirm)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		yes_btn.add_theme_color_override(color_name, UITheme.COL_ERROR)
	card.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.COL_SURFACE, UITheme.COL_DANGER, 3, 22))


## Les libellés et l'icône restent optionnels afin de réutiliser la même
## confirmation pour une suppression, un abandon ou une dépense localisée.
func open(text: String, confirm_text: String = "OUI",
		confirm_icon: Texture2D = null, cancel_text: String = "NON", opener: Control = null) -> void:
	_focus.capture(self, opener)
	message_label.text = text
	no_btn.text = cancel_text
	yes_btn.text = confirm_text
	yes_btn.icon = confirm_icon
	if confirm_icon != null:
		yes_btn.add_theme_constant_override("icon_max_width", 44)
	else:
		yes_btn.remove_theme_constant_override("icon_max_width")
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
	_focus.restore()


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


func _input(event: InputEvent) -> void:
	if _open and is_visible_in_tree():
		_focus.handle(event, [no_btn, yes_btn], get_viewport())
