## Profil local et statistiques du joueur.
extends Control

const Routes := preload("res://scripts/ui/GameRoutes.gd")
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")

const StatsRules := preload("res://scripts/domain/ProfileStatsRules.gd")

@onready var background: MenuBackground = $Background
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
var _scope := ""
var _sections: Array[Control] = []


func _ready() -> void:
	background.set_god(GodIdentityModel.player(PlayerData.player_god_id))
	close_button.pressed.connect(_close)
	edit_button.pressed.connect(_begin_edit)
	save_name_button.pressed.connect(_save_name)
	cancel_name_button.pressed.connect(_cancel_edit)
	name_input.text_submitted.connect(func(_value): _save_name())
	name_input.focus_entered.connect(_reveal_name_input)
	pseudo_label.text = PlayerData.player_name
	edit_row.visible = false
	_build_scope_picker()
	_refresh_stats()


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
	var s := _scope_stats()
	var rows := [
		["Manches jouées", str(int(s.get("games_played", 0)))],
		["Victoires", str(int(s.get("wins", 0)))],
		["Défaites", str(int(s.get("losses", 0)))],
		["Égalités", str(int(s.get("draws", 0)))],
		["Taux de victoire", "%d %%" % StatsRules.win_rate(s)],
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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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


func _build_scope_picker() -> void:
	var picker := OptionButton.new()
	picker.name = "StatsScope"
	picker.custom_minimum_size.y = 88
	for title in ["Tous les combats", "Campagne", "PVP local"]:
		picker.add_item(title)
	picker.item_selected.connect(func(index: int):
		_scope = ["", "campaign", "pvp"][index]
		_refresh_stats())
	$Root/Scroll/Content.add_child(picker)
	$Root/Scroll/Content.move_child(picker, 1)


func _scope_stats() -> Dictionary:
	return PlayerData.stats if _scope == "" else PlayerData.stats.get("by_scope", {}).get(_scope, {})


func _refresh_stats() -> void:
	for child in global_stats.get_children():
		global_stats.remove_child(child)
		child.queue_free()
	for section in _sections:
		section.get_parent().remove_child(section)
		section.queue_free()
	_sections.clear()
	_build_global_stats()
	_build_progression()
	_build_collection()
	_build_affinities()
	_build_modes()
	var records := _add_section("RECORDS DE COMBAT")
	var stats := _scope_stats()
	for row in [["Captures en un coup", "best_move_captures"],
			["Captures en une manche", "best_round_captures"],
			["Contrôles totaux du plateau", "perfect_rounds"]]:
		records.add_child(_make_stat_row(row[0], str(int(stats.get(row[1], 0)))))


func _add_section(title: String) -> VBoxContainer:
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.theme_type_variation = &"SectionTitle"
	heading.add_theme_font_size_override("font_size", UITheme.FONT_SUBTITLE)
	$Root/Scroll/Content.add_child(heading)
	_sections.append(heading)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	$Root/Scroll/Content.add_child(panel)
	_sections.append(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 18)
	panel.add_child(rows)
	return rows


func _build_progression() -> void:
	var rows := _add_section("PROGRESSION DE CAMPAGNE")
	var service := CampaignContext.get_service()
	if service == null or not service.is_ready():
		rows.add_child(_make_stat_row("Campagne", "Indisponible"))
		return
	var completed := 0
	var bosses := 0
	var boss_total := 0
	var mini_bosses := 0
	var mini_total := 0
	for node in service.graph().nodes():
		var done := service.is_completed(node.id)
		completed += 1 if done else 0
		if node.is_boss():
			boss_total += 1
			bosses += 1 if done else 0
		if node.is_mini_boss():
			mini_total += 1
			mini_bosses += 1 if done else 0
	rows.add_child(_make_stat_row("Niveaux terminés", "%d / %d" % [completed, service.graph().nodes().size()]))
	rows.add_child(_make_stat_row("Boss vaincus", "%d / %d" % [bosses, boss_total]))
	rows.add_child(_make_stat_row("Mini-boss vaincus", "%d / %d" % [mini_bosses, mini_total]))


func _build_collection() -> void:
	var rows := _add_section("COLLECTION")
	var owned := 0
	var evolved := 0
	var evolvable := 0
	var lineages := MonsterLoader.lineage_ids()
	for lineage_id in lineages:
		var level := int(PlayerData.card_entry(lineage_id).get("unlocked_level", 0))
		var maximum := MonsterLoader.lineage_max_level(lineage_id)
		owned += 1 if level > 0 else 0
		if maximum > 1:
			evolvable += 1
			evolved += 1 if level >= maximum else 0
	rows.add_child(_make_stat_row("Lignées obtenues", "%d / %d" % [owned, lineages.size()]))
	rows.add_child(_make_stat_row("Dieux débloqués", "%d / %d" % [PlayerData.unlocked_god_ids().size(), MonsterLoader.get_all_gods().size()]))
	rows.add_child(_make_stat_row("Lignées entièrement évoluées", "%d / %d" % [evolved, evolvable]))


func _build_affinities() -> void:
	var rows := _add_section("AFFINITÉ AVEC LES DIEUX")
	var gods := MonsterLoader.get_all_gods()
	gods.append({"id": "godless", "name": "Sans dieu"})
	for god in gods:
		_add_combat_summary(rows, str(god.get("name", "")), "by_god", str(god.get("id", "")))


func _build_modes() -> void:
	var rows := _add_section("RÉSULTATS PAR MODE")
	for mode in GameModeRules.MODES:
		_add_combat_summary(rows, GameModeRules.mode_label(mode), "by_mode", mode)


func _add_combat_summary(rows: VBoxContainer, title: String, group: String, id: String) -> void:
	var key := id if _scope == "" else "%s:%s" % [_scope, id]
	var stats: Dictionary = PlayerData.stats.get(group, {}).get(key, {})
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	name_label.add_theme_color_override("font_color", UITheme.COL_ACCENT_LIGHT)
	rows.add_child(name_label)
	var games := int(stats.get("games_played", 0))
	var detail := Label.new()
	detail.text = "%d manches · %d victoires · %s" % [games, int(stats.get("wins", 0)),
		"%d %%" % StatsRules.win_rate(stats) if games > 0 else "—"]
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	rows.add_child(detail)
