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


func _ready() -> void:
	for index in range(_buttons.size()):
		_buttons[index].pressed.connect(_on_tab_pressed.bind(index))
		_apply_tab_style(_buttons[index], index == current_tab)


func _apply_tab_style(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override("normal", UITheme.nav_tab_style(selected))
	button.add_theme_stylebox_override("hover", UITheme.nav_tab_style(selected, true))
	button.add_theme_stylebox_override("pressed", UITheme.nav_tab_style(true, true))
	button.add_theme_color_override("font_color", Color("#ffe080") if selected else Color("#c8b898"))


func _on_tab_pressed(index: int) -> void:
	if index == current_tab:
		return
	get_tree().change_scene_to_file(SCENES[index])
