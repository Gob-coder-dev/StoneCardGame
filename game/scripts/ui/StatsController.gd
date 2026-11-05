## Profil local et statistiques du joueur.
extends Control

const Routes := preload("res://scripts/ui/GameRoutes.gd")

const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const EncounterPathModel := preload("res://scripts/domain/EncounterPath.gd")

@onready var close_button: Button = $Root/Header/CloseButton
@onready var scroll: ScrollContainer = $Root/Scroll
@onready var pseudo_label: Label = $Root/Scroll/Content/ProfilePanel/ProfileContent/PseudoRow/PseudoLabel
@onready var edit_button: Button = $Root/Scroll/Content/ProfilePanel/ProfileContent/PseudoRow/EditButton
@onready var edit_row: VBoxContainer = $Root/Scroll/Content/ProfilePanel/ProfileContent/EditRow
@onready var name_input: LineEdit = $Root/Scroll/Content/ProfilePanel/ProfileContent/EditRow/NameInput
@onready var error_label: Label = $Root/Scroll/Content/ProfilePanel/ProfileContent/EditRow/ErrorLabel
@onready var save_name_button: Button = $Root/Scroll/Content/ProfilePanel/ProfileContent/EditRow/EditButtons/SaveButton
@onready var cancel_name_button: Button = $Root/Scroll/Content/ProfilePanel/ProfileContent/EditRow/EditButtons/CancelButton
@onready var global_stats: VBoxContainer = $Root/Scroll/Content/GlobalPanel/GlobalStats
@onready var npc_list: VBoxContainer = $Root/Scroll/Content/NPCPanel/NPCList


func _ready() -> void:
	close_button.pressed.connect(_close)
	edit_button.pressed.connect(_begin_edit)
	save_name_button.pressed.connect(_save_name)
	cancel_name_button.pressed.connect(_cancel_edit)
	name_input.text_submitted.connect(func(_value): _save_name())
	name_input.focus_entered.connect(_reveal_name_input)
	pseudo_label.text = PlayerData.player_name
	edit_row.visible = false
	_build_global_stats()
	_build_npc_progression()


func _begin_edit() -> void:
	name_input.text = PlayerData.player_name
	error_label.text = ""
	edit_row.visible = true
	edit_button.disabled = true
	name_input.grab_focus()
	name_input.select_all()


func _save_name() -> void:
	match PlayerData.set_player_name(name_input.text):
		PlayerData.ProfileChange.INVALID:
			error_label.text = "Le pseudo doit contenir entre 2 et 16 caractères."
			return
		PlayerData.ProfileChange.SAVE_FAILED:
			error_label.text = "Impossible d'enregistrer le pseudo. Réessaie."
			return
	pseudo_label.text = PlayerData.player_name
	_cancel_edit()


func _cancel_edit() -> void:
	edit_row.visible = false
	edit_button.disabled = false
	error_label.text = ""
	name_input.release_focus()


## Sur téléphone, le clavier virtuel peut recouvrir le champ. On remonte la
## ligne d'édition une fois la nouvelle mise en page stabilisée.
func _reveal_name_input() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(name_input):
		scroll.ensure_control_visible(name_input)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if edit_row.visible:
		_cancel_edit()
	else:
		_close()
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if edit_row.visible:
			_cancel_edit()
		else:
			_close()


func _close() -> void:
	Routes.go(get_tree(), Routes.MAIN_MENU)


func _build_global_stats() -> void:
	var s := PlayerData.stats
	var rows := [
		["Parties jouées", str(int(s.get("games_played", 0)))],
		["Victoires", str(int(s.get("wins", 0)))],
		["Défaites", str(int(s.get("losses", 0)))],
		["Égalités", str(int(s.get("draws", 0)))],
		["Taux de victoire", "%d %%" % PlayerData.win_rate()],
		["Série actuelle", str(int(s.get("current_streak", 0)))],
		["Meilleure série", str(int(s.get("best_streak", 0)))],
		["Captures totales", str(int(s.get("total_captures", 0)))]
	]
	for row in rows:
		global_stats.add_child(_make_stat_row(row[0], row[1]))


func _make_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	label.add_theme_color_override("font_color", UITheme.COL_TEXT)
	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override("font_color", UITheme.COL_ACCENT_LIGHT)
	value.add_theme_font_size_override("font_size", UITheme.FONT_SUBTITLE)
	row.add_child(label)
	row.add_child(value)
	return row


## Un chemin par dieu et pour Pr.Stone. Le compteur suit la même règle
## linéaire que le serpentin : seuls les niveaux gagnés dans l'ordre comptent.
func _build_npc_progression() -> void:
	for source in OpponentCatalogModel.sources():
		var levels := OpponentCatalogModel.levels_for(str(source.get("id", "")))
		if levels.is_empty():
			continue
		var path := EncounterPathModel.states(levels, PlayerData.is_npc_beaten)
		var completed := EncounterPathModel.completed_count(path)
		var total := levels.size()
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)

		var status := Label.new()
		var status_color := UITheme.COL_TEXT_DIM
		if completed == total:
			status.text = "✔"
			status_color = UITheme.COL_SUCCESS
		elif completed > 0:
			status.text = "◆"
			status_color = UITheme.COL_ACCENT_LIGHT
		else:
			status.text = "◇"
		status.add_theme_color_override("font_color", status_color)
		status.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		status.custom_minimum_size = Vector2(50, 0)

		var name_label := Label.new()
		name_label.text = str(source.get("name", ""))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		name_label.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		var color_hex := str(source.get("color", ""))
		if color_hex != "":
			name_label.add_theme_color_override("font_color", Color(color_hex))

		var count_label := Label.new()
		count_label.text = "%d/%d" % [completed, total]
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.custom_minimum_size = Vector2(130, 0)
		count_label.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		count_label.add_theme_color_override("font_color", UITheme.COL_TEXT)

		row.add_child(status)
		row.add_child(name_label)
		row.add_child(count_label)
		npc_list.add_child(row)
