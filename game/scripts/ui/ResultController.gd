## ResultController.gd
## Écran de résultat après une partie.
extends Control

@onready var result_label: Label = $VBoxCenter/ResultLabel
@onready var score_label: Label = $VBoxCenter/ScoreLabel
@onready var replay_btn: Button = $VBoxCenter/ReplayButton
@onready var level_btn: Button = $VBoxCenter/LevelSelectButton
@onready var menu_btn: Button = $VBoxCenter/MainMenuButton


func _ready() -> void:
	replay_btn.pressed.connect(_on_replay)
	level_btn.pressed.connect(_on_level_select)
	menu_btn.pressed.connect(_on_menu)

	## Lire le résultat depuis BattleContext
	match BattleContext.last_winner:
		GameState.PLAYER_HUMAN:
			result_label.text = "VICTOIRE !"
		GameState.PLAYER_AI:
			result_label.text = "DÉFAITE..."
		_:
			result_label.text = "ÉGALITÉ"

	var npc := BattleContext.current_opponent()
	var npc_name: String = npc.get("name", "Adversaire")
	score_label.text = "%s %d  —  %d %s" % [
		PlayerData.player_name,
		BattleContext.last_score_human,
		BattleContext.last_score_ai,
		npc_name
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_menu()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_menu()


func _on_replay() -> void:
	## Une revanche commence par un nouveau tirage au sort.
	BattleContext.forced_first_player = 0
	get_tree().change_scene_to_file("res://scenes/menus/PreBattle.tscn")


func _on_level_select() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/LevelSelect.tscn")


func _on_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")
