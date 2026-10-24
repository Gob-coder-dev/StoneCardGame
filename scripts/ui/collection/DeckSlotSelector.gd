## Trois boutons numérotés. Les decks et leur sauvegarde restent dans PlayerData.
extends RefCounted

signal slot_selected(slot: int)

const TouchButtonScript := preload("res://scripts/ui/input/TouchButton.gd")
var _buttons: Array[Button] = []
var _group := ButtonGroup.new()


func _init(row: HBoxContainer) -> void:
	for index in range(DeckRules.DECKS_PER_GOD):
		var button: Button = TouchButtonScript.new()
		button.name = "Deck%d" % (index + 1)
		button.text = str(index + 1)
		button.custom_minimum_size = UITheme.DECK_SLOT_BUTTON_SIZE
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
		button.pressed.connect(slot_selected.emit.bind(index))
		row.add_child(button)
		_buttons.append(button)


## Les styles restent stables : TouchButton peut restaurer son survol de souris
## après un geste tactile sans récupérer l'apparence d'une ancienne sélection.
func refresh(selected: int) -> void:
	for index in range(_buttons.size()):
		_buttons[index].set_pressed_no_signal(index == selected)
