## LevelSelectController.gd
## Contrôleur de l'écran de sélection des adversaires.
extends Control

const TouchButtonScript := preload("res://scripts/ui/input/TouchButton.gd")

@onready var npc_list: VBoxContainer = $Root/NPCListScroll/NPCList
@onready var profile_panel: PanelContainer = $Root/ProfilePanel
@onready var profile_name: Label = $Root/ProfilePanel/ProfileContent/NPCName
@onready var profile_quote: Label = $Root/ProfilePanel/ProfileContent/NPCQuote
@onready var profile_difficulty: Label = $Root/ProfilePanel/ProfileContent/Difficulty
@onready var fight_button: Button = $Root/ProfilePanel/ProfileContent/FightButton
@onready var close_button: Button = $Root/Header/CloseButton

var _selected_npc_id: String = ""

func _ready() -> void:
	fight_button.pressed.connect(_on_fight)
	close_button.pressed.connect(_on_close)
	profile_panel.visible = false
	_populate()


func _populate() -> void:
	for child in npc_list.get_children():
		child.queue_free()
	for npc in StoneLoader.get_npcs_ordered():
		var btn := _make_npc_btn(npc)
		npc_list.add_child(btn)


func _make_npc_btn(npc: Dictionary) -> Button:
	var stars: String
	match npc["difficulty"]:
		"easy":   stars = "★☆☆"
		"medium": stars = "★★☆"
		_:        stars = "★★★"
	var btn: Button = TouchButtonScript.new()
	btn.text = "%s  %s" % [stars, npc["name"]]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 120)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_OFF
	btn.clip_text = true
	btn.pressed.connect(_on_npc_selected.bind(npc["id"]))
	return btn


func _on_npc_selected(npc_id: String) -> void:
	_selected_npc_id = npc_id
	var npc := StoneLoader.get_npc(npc_id)
	if npc.is_empty():
		return
	profile_name.text = "%s\n%s" % [npc["name"], npc.get("name_jp", "")]
	profile_quote.text = "« %s »" % npc.get("quote", "")
	var diff_text: String
	match npc["difficulty"]:
		"easy":   diff_text = "Niveau : Facile  ★☆☆"
		"medium": diff_text = "Niveau : Moyen   ★★☆"
		_:        diff_text = "Niveau : Difficile ★★★"
	var god := StoneLoader.get_god(str(npc.get("god_id", "")))
	profile_difficulty.text = "%s\nDieu : %s • %s" % [
		diff_text, god.get("name", "?"), god.get("family_name", "?")
	]
	profile_panel.visible = true
	fight_button.disabled = false


func _on_fight() -> void:
	if _selected_npc_id == "":
		return
	BattleContext.selected_npc_id = _selected_npc_id
	get_tree().change_scene_to_file("res://scenes/menus/PreBattle.tscn")


func _on_close() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")
