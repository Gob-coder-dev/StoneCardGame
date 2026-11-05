## ResultController.gd
## Écran de résultat après une partie : cinq sorties vers la boucle de
## rencontres (niveau suivant, revanche, autre niveau, autre dieu, accueil).
extends Control

const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const EncounterPathModel := preload("res://scripts/domain/EncounterPath.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")

@onready var result_label: Label = $VBoxCenter/ResultLabel
@onready var score_label: Label = $VBoxCenter/ScoreLabel
@onready var background: MenuBackground = $Background
@onready var next_btn: Button = $VBoxCenter/NextButton
@onready var replay_btn: Button = $VBoxCenter/ReplayButton
@onready var level_btn: Button = $VBoxCenter/LevelsButton
@onready var gods_btn: Button = $VBoxCenter/GodsButton
@onready var menu_btn: Button = $VBoxCenter/MainMenuButton
@onready var save_status: Label = $VBoxCenter/SaveStatus
@onready var retry_save_btn: Button = $VBoxCenter/RetrySaveButton


func _ready() -> void:
	next_btn.pressed.connect(_on_next_level)
	replay_btn.pressed.connect(_on_replay)
	level_btn.pressed.connect(_on_level_select)
	gods_btn.pressed.connect(_on_god_select)
	menu_btn.pressed.connect(_on_menu)
	retry_save_btn.pressed.connect(_on_retry_save)

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
	_refresh_save_status()


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
		and BattleContext.last_result_saved and not _next_level().is_empty()


func _refresh_save_status() -> void:
	var failed := not BattleContext.last_result_saved
	save_status.visible = failed
	retry_save_btn.visible = failed
	if failed:
		save_status.text = "La progression n'a pas pu être enregistrée (%s)." \
			% error_string(BattleContext.last_save_error)


func _on_retry_save() -> void:
	retry_save_btn.disabled = true
	var error := BattleContext.persist_result()
	retry_save_btn.disabled = false
	if error == OK:
		save_status.text = "Progression enregistrée."
		save_status.add_theme_color_override("font_color", UITheme.COL_SUCCESS)
		retry_save_btn.visible = false
		_refresh_next_button()
		return
	save_status.text = "Échec de l'enregistrement (%s). Réessayez ou vérifiez l'espace disponible." \
		% error_string(error)
	save_status.add_theme_color_override("font_color", UITheme.COL_ERROR)


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
	Routes.go(get_tree(), Routes.PRE_BATTLE)


func _on_replay() -> void:
	## Une revanche commence par un nouveau tirage au sort.
	BattleContext.forced_first_player = 0
	Routes.go(get_tree(), Routes.PRE_BATTLE)


## Rouvre le serpentin du dernier adversaire, pour choisir un autre de ses
## niveaux sans repasser par la grille des dieux.
func _on_level_select() -> void:
	BattleContext.select_source(BattleContext.navigation_source_id())
	Routes.go(get_tree(), Routes.ENCOUNTER_PATH)


## Retour à la grille des sept chemins, indépendamment de la source courante.
func _on_god_select() -> void:
	Routes.go(get_tree(), Routes.ENCOUNTER_SELECT)


func _on_menu() -> void:
	Routes.go(get_tree(), Routes.MAIN_MENU)
