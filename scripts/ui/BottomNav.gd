## Barre de navigation persistante des trois écrans principaux.
class_name BottomNav
extends PanelContainer

enum Tab { CARDS, PLAY, RULES }

@export var current_tab: Tab = Tab.PLAY

@onready var _buttons: Array[Button] = [
	$Tabs/CardsButton,
	$Tabs/PlayButton,
	$Tabs/RulesButton
]

const SCENES: Array[String] = [
	"res://scenes/menus/CollectionScreen.tscn",
	"res://scenes/menus/MainMenu.tscn",
	"res://scenes/menus/HowToPlay.tscn"
]

const ICONS: Array[Texture2D] = [preload("res://assets/ui/nav-decks.svg"),
	preload("res://assets/ui/nav-play.svg"), preload("res://assets/ui/nav-rules.svg")]


func _ready() -> void:
	for index in range(_buttons.size()):
		_add_tab_content(_buttons[index], index)
		_buttons[index].pressed.connect(_on_tab_pressed.bind(index))
		_apply_tab_style(_buttons[index], index == current_tab)


func _add_tab_content(button: Button, index: int) -> void:
	var caption := button.text
	button.text = ""
	button.tooltip_text = caption
	var content := VBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_top = 12
	content.offset_bottom = -10
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 4)
	var icon := TextureRect.new()
	icon.texture = ICONS[index]
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(0, 54)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(icon)
	var label := Label.new()
	label.name = "Caption"
	label.text = caption
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	content.add_child(label)


func _apply_tab_style(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override("normal", UITheme.nav_tab_style(selected))
	button.add_theme_stylebox_override("hover", UITheme.nav_tab_style(selected, true))
	button.add_theme_stylebox_override("pressed", UITheme.nav_tab_style(true, true))
	button.add_theme_color_override("font_color", UITheme.COL_ACCENT_LIGHT if selected else UITheme.COL_TEXT_DIM)
	button.get_node("Content/Caption").add_theme_color_override("font_color",
		UITheme.COL_ACCENT_LIGHT if selected else UITheme.COL_TEXT_DIM)


func _on_tab_pressed(index: int) -> void:
	if index == current_tab:
		return
	get_tree().change_scene_to_file(SCENES[index])
