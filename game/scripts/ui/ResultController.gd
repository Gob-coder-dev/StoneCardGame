## ResultController.gd
## Écran de résultat après une partie : cinq sorties vers la boucle de
## rencontres (niveau suivant, revanche, autre niveau, autre dieu, accueil).
extends Control

const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const EncounterPathModel := preload("res://scripts/domain/EncounterPath.gd")

@onready var result_label: Label = $VBoxCenter/ResultLabel
@onready var score_label: Label = $VBoxCenter/ScoreLabel
@onready var background: MenuBackground = $Background
@onready var next_btn: Button = $VBoxCenter/NextButton
@onready var replay_btn: Button = $VBoxCenter/ReplayButton
@onready var level_btn: Button = $VBoxCenter/LevelsButton
@onready var gods_btn: Button = $VBoxCenter/GodsButton
@onready var menu_btn: Button = $VBoxCenter/MainMenuButton


func _ready() -> void:
	next_btn.pressed.connect(_on_next_level)
	replay_btn.pressed.connect(_on_replay)
	level_btn.pressed.connect(_on_level_select)
	gods_btn.pressed.connect(_on_god_select)
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
	if BattleContext.last_winner == GameState.PLAYER_HUMAN:
		background.set_result_victory(StoneLoader.get_god(PlayerData.player_god_id))
	elif BattleContext.last_winner == GameState.PLAYER_AI:
		background.set_result_defeat(StoneLoader.get_god(str(npc.get("god_id", ""))))
	else:
		background.set_result_draw(StoneLoader.get_god(PlayerData.player_god_id),
			StoneLoader.get_god(str(npc.get("god_id", ""))))
	var npc_name: String = npc.get("name", "Adversaire")
	score_label.text = "%s %d  —  %d %s" % [
		PlayerData.player_name,
		BattleContext.last_score_human,
		BattleContext.last_score_ai,
		npc_name
	]
	_refresh_next_button()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_menu()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_menu()


## Niveau qui suit celui joué dans le même chemin. Vide au dernier rond.
func _next_level() -> Dictionary:
	var source := BattleContext.current_source_id()
	if source == "":
		return {}
	return EncounterPathModel.next_level(
		OpponentCatalogModel.levels_for(source), BattleContext.selected_npc_id)


## Le suivant n'apparaît qu'après une victoire et s'il reste un rond.
func _refresh_next_button() -> void:
	next_btn.visible = BattleContext.last_winner == GameState.PLAYER_HUMAN \
		and not _next_level().is_empty()


func _on_next_level() -> void:
	var next_level := _next_level()
	if next_level.is_empty() or BattleContext.last_winner != GameState.PLAYER_HUMAN:
		return
	var source := BattleContext.current_source_id()
	var opponent := OpponentCatalogModel.build_for_source(
		source, str(next_level.get("bracket_id", "")), str(next_level.get("difficulty_id", "")))
	if opponent.is_empty():
		push_error("Result: impossible de générer l'adversaire du niveau suivant.")
		return
	BattleContext.select_source(source)
	BattleContext.select_opponent(opponent)
	BattleContext.forced_first_player = 0
	get_tree().change_scene_to_file("res://scenes/menus/PreBattle.tscn")


func _on_replay() -> void:
	## Une revanche commence par un nouveau tirage au sort.
	BattleContext.forced_first_player = 0
	get_tree().change_scene_to_file("res://scenes/menus/PreBattle.tscn")


## Rouvre le serpentin du dernier adversaire, pour choisir un autre de ses
## niveaux sans repasser par la grille des dieux.
func _on_level_select() -> void:
	BattleContext.select_source(BattleContext.navigation_source_id())
	get_tree().change_scene_to_file("res://scenes/menus/EncounterPath.tscn")


## Retour à la grille des sept chemins, indépendamment de la source courante.
func _on_god_select() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/EncounterSelect.tscn")


func _on_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")
