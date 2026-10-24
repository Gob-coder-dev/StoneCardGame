## Boutons numérotés partagés par les decks et les niveaux, sans règle de jeu.
extends RefCounted

signal value_selected(value: int)

const TouchButtonScript := preload("res://scripts/ui/input/TouchButton.gd")
var _buttons: Array[Button] = []
var _group := ButtonGroup.new()
var _first_value: int


func _init(row: HBoxContainer, count: int, first_value: int = 1) -> void:
	_first_value = first_value
	for index in range(count):
		var button: Button = TouchButtonScript.new()
		button.name = "Number%d" % (index + 1)
		button.text = str(index + 1)
		button.custom_minimum_size = UITheme.NUMBERED_BUTTON_SIZE
		button.add_theme_font_size_override("font_size", UITheme.FONT_SUBTITLE)
		button.toggle_mode = true
		button.button_group = _group
		button.add_theme_stylebox_override("normal", UITheme.nav_tab_style(false))
		button.add_theme_stylebox_override("hover", UITheme.nav_tab_style(false, true))
		var selected_style := UITheme.panel_style(UITheme.COL_GOLD.darkened(0.65), UITheme.COL_GOLD)
		button.add_theme_stylebox_override("pressed", selected_style)
		button.add_theme_stylebox_override("hover_pressed", selected_style)
		button.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
		button.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		button.pressed.connect(value_selected.emit.bind(index + first_value))
		row.add_child(button)
		_buttons.append(button)


## Les styles restent stables : TouchButton peut restaurer son survol de souris
## après un geste tactile sans récupérer l'apparence d'une ancienne sélection.
func refresh(selected: int) -> void:
	for index in range(_buttons.size()):
		_buttons[index].set_pressed_no_signal(index + _first_value == selected)
