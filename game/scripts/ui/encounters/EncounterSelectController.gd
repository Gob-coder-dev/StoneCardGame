## EncounterSelectController.gd
## Écran des Rencontres : une grande case par dieu, puis Pr.Stone sur une
## ligne dédiée. Toucher une case choisit la source du chemin ; aucune règle
## de combat ni écriture de profil ici.
extends Control

const GodCardTileView := preload("res://scripts/ui/encounters/GodCardTile.gd")
const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const PATH_SCENE := "res://scenes/menus/EncounterPath.tscn"
const MENU_SCENE := "res://scenes/menus/MainMenu.tscn"

@onready var background: MenuBackground = $Background
@onready var back_button: Button = $Root/Header/BackButton
@onready var gods_grid: GridContainer = $Root/Scroll/Content/Gods
@onready var godless_row: VBoxContainer = $Root/Scroll/Content/Godless


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	background.set_god(StoneLoader.get_god(PlayerData.player_god_id))
	_populate()


func _populate() -> void:
	for source in OpponentCatalogModel.sources():
		var source_id := str(source.get("id", ""))
		var is_neutral := source_id == OpponentCatalogModel.NEUTRAL_BOT_ID
		var tile: GodCardTileView = GodCardTileView.new()
		tile.name = "Godless" if is_neutral else "God_%s" % source_id
		tile.setup(source, is_neutral)
		tile.pressed.connect(_open_path.bind(source_id))
		if is_neutral:
			godless_row.add_child(tile)
		else:
			gods_grid.add_child(tile)


func _open_path(source_id: String) -> void:
	if source_id == "":
		return
	BattleContext.select_source(source_id)
	get_tree().change_scene_to_file(PATH_SCENE)


func _on_back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()
