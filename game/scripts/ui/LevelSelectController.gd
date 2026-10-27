## LevelSelectController.gd
## Contrôleur de l'écran des Rencontres : choix du dieu, du palier de cartes,
## puis de la difficulté. L'adversaire est généré à la demande par
## OpponentCatalog : la page ne liste que six dieux, pas quatre-vingt-dix bots.
extends Control

const TouchButtonScript := preload("res://scripts/ui/input/TouchButton.gd")
const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const Gesture := preload("res://scripts/ui/input/TapGesture.gd")

@onready var npc_list: VBoxContainer = $Root/NPCListScroll/NPCList
@onready var modal: Control = $Modal
@onready var backdrop: ColorRect = $Modal/Backdrop
@onready var profile_panel: PanelContainer = $Modal/Center/ProfilePanel
@onready var profile_name: Label = $Modal/Center/ProfilePanel/ProfileContent/NPCName
@onready var profile_quote: Label = $Modal/Center/ProfilePanel/ProfileContent/NPCQuote
@onready var profile_difficulty: Label = $Modal/Center/ProfilePanel/ProfileContent/Difficulty
@onready var bracket_row: HBoxContainer = $Modal/Center/ProfilePanel/ProfileContent/BracketRow
@onready var difficulty_row: GridContainer = $Modal/Center/ProfilePanel/ProfileContent/DifficultyRow
@onready var fight_button: Button = $Modal/Center/ProfilePanel/ProfileContent/FightButton
@onready var close_button: Button = $Root/Header/CloseButton

var _selected_god_id: String = ""
var _selected_bracket_id: String = ""
var _selected_difficulty_id: String = ""
var _god_group: ButtonGroup = null
var _bracket_buttons: Dictionary = {}
var _difficulty_buttons: Dictionary = {}
var _backdrop_tap := Gesture.new()


func _ready() -> void:
	fight_button.pressed.connect(_on_fight)
	close_button.pressed.connect(_on_close)
	backdrop.gui_input.connect(_on_backdrop_input)
	modal.visible = false
	_selected_bracket_id = OpponentCatalogModel.default_bracket_id()
	_selected_difficulty_id = OpponentCatalogModel.default_difficulty_id()
	_god_group = ButtonGroup.new()
	_god_group.allow_unpress = false
	_build_choices()
	_populate()


func _populate() -> void:
	for child in npc_list.get_children():
		child.queue_free()
	for god in StoneLoader.get_all_gods():
		npc_list.add_child(_make_god_btn(god))


func _make_god_btn(god: Dictionary) -> Button:
	var btn: Button = TouchButtonScript.new()
	btn.text = "%s\n%s" % [str(god.get("name", "?")), str(god.get("family_name", ""))]
	btn.toggle_mode = true
	btn.button_group = _god_group
	var portrait_path := str(god.get("asset", ""))
	if portrait_path != "":
		btn.icon = load(portrait_path) as Texture2D
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 112)
		btn.add_theme_constant_override("h_separation", 24)
	btn.add_theme_font_size_override("font_size", 32)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 152)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_OFF
	btn.clip_text = true
	btn.pressed.connect(_on_god_selected.bind(str(god.get("id", ""))))
	return btn


## Les deux rangées de choix sont construites une fois : leurs libellés ne
## dépendent que du catalogue statique de OpponentCatalog.
func _build_choices() -> void:
	var bracket_group := ButtonGroup.new()
	bracket_group.allow_unpress = false
	for tier in OpponentCatalogModel.BRACKETS:
		var bracket_id := str(tier["id"])
		var btn := _make_choice_button(str(tier["name"]), bracket_group)
		btn.pressed.connect(_on_bracket_selected.bind(bracket_id))
		bracket_row.add_child(btn)
		_bracket_buttons[bracket_id] = btn
	var difficulty_group := ButtonGroup.new()
	difficulty_group.allow_unpress = false
	for level in OpponentCatalogModel.DIFFICULTIES:
		var difficulty_id := str(level["id"])
		var btn := _make_choice_button("%s  %s" % [
			OpponentCatalogModel.stars_text(int(level["stars"])),
			str(level["name"]),
		], difficulty_group)
		btn.pressed.connect(_on_difficulty_selected.bind(difficulty_id))
		difficulty_row.add_child(btn)
		_difficulty_buttons[difficulty_id] = btn
	_sync_choice(_bracket_buttons, _selected_bracket_id)
	_sync_choice(_difficulty_buttons, _selected_difficulty_id)


func _make_choice_button(text: String, group: ButtonGroup) -> Button:
	var btn: Button = TouchButtonScript.new()
	btn.text = text
	btn.toggle_mode = true
	btn.button_group = group
	btn.custom_minimum_size = Vector2(0, 96)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 27)
	return btn


func _sync_choice(buttons: Dictionary, selected_id: String) -> void:
	for button_id in buttons:
		var btn: Button = buttons[button_id]
		btn.set_pressed_no_signal(str(button_id) == selected_id)


func _on_god_selected(god_id: String) -> void:
	_selected_god_id = god_id
	var god := StoneLoader.get_god(god_id)
	if god.is_empty():
		return
	var god_color := Color(str(god.get("color", "#575361")))
	profile_name.text = str(god.get("name", "?"))
	profile_name.add_theme_color_override("font_color", god_color)
	profile_quote.text = str(god.get("description", ""))
	profile_panel.add_theme_stylebox_override("panel", UITheme.panel_style(
		UITheme.COL_PANEL_BG, god_color))
	modal.visible = true
	_backdrop_tap.reset()
	fight_button.disabled = false
	_refresh_summary()


func _on_bracket_selected(bracket_id: String) -> void:
	_selected_bracket_id = bracket_id
	_refresh_summary()


func _on_difficulty_selected(difficulty_id: String) -> void:
	_selected_difficulty_id = difficulty_id
	_refresh_summary()


func _refresh_summary() -> void:
	if _selected_god_id == "":
		return
	var tier := OpponentCatalogModel.bracket(_selected_bracket_id)
	var level := OpponentCatalogModel.difficulty(_selected_difficulty_id)
	profile_difficulty.text = "Palier : %s\nDifficulté : %s  %s" % [
		str(tier.get("name", "?")),
		OpponentCatalogModel.stars_text(int(level.get("stars", 0))),
		str(level.get("name", "?")),
	]


func _on_fight() -> void:
	if _selected_god_id == "":
		return
	var opponent := OpponentCatalogModel.build(
		_selected_god_id, _selected_bracket_id, _selected_difficulty_id)
	if opponent.is_empty():
		push_error("LevelSelectController: adversaire impossible à générer.")
		return
	BattleContext.select_opponent(opponent)
	get_tree().change_scene_to_file("res://scenes/menus/PreBattle.tscn")


## La carte est un vrai panneau modal : le fond assombri capte les gestes,
## donc la liste des dieux ne défile pas derrière. Un appui hors de la carte
## la referme, comme les fiches de pierre.
func _close_profile() -> void:
	modal.visible = false
	_backdrop_tap.reset()


func _on_backdrop_input(event: InputEvent) -> void:
	if _backdrop_tap.update(event, backdrop) == Gesture.Result.TAP:
		_close_profile()


## Sur Android, le bouton retour ferme d'abord la carte ouverte.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _go_back() -> void:
	if modal.visible:
		_close_profile()
	else:
		_on_close()


func _on_close() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")
