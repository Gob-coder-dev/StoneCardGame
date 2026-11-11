## Écran Quêtes : trois quotidiennes figées pour la journée et des objectifs à
## paliers cumulatifs. Les compteurs et les récompenses restent dans QuestService.
extends Control

const Routes := preload("res://scripts/ui/GameRoutes.gd")
const QuestServiceModel := preload("res://scripts/application/quests/QuestService.gd")
const Calendar := preload("res://scripts/domain/quests/QuestCalendar.gd")
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")
const TouchButtonScript := preload("res://scripts/ui/input/TouchButton.gd")
const SOUL_ICON := preload("res://assets/ui/soul-placeholder.svg")
const CANDLE_ICON := preload("res://assets/ui/candle-placeholder.svg")

@onready var background: MenuBackground = $Background
@onready var close_button: Button = $Root/Header/CloseButton
@onready var daily_reset: Label = $Root/Scroll/Content/DailyPanel/DailyContent/Reset
@onready var daily_list: VBoxContainer = $Root/Scroll/Content/DailyPanel/DailyContent/DailyList
@onready var unique_list: VBoxContainer = $Root/Scroll/Content/UniquePanel/UniqueList
@onready var status_label: Label = $Root/Status

var _service := QuestServiceModel.new()


func _ready() -> void:
	background.set_god(GodIdentityModel.player(PlayerData.player_god_id))
	close_button.pressed.connect(_close)
	_build()
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(_update_countdown)
	add_child(tick)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_close()


func _close() -> void:
	Routes.go(get_tree(), Routes.MAIN_MENU)


## ─── Construction ────────────────────────────────────────────────────────────

func _build() -> void:
	_clear(daily_list)
	_clear(unique_list)
	var view := _service.view()
	if not bool(view.get("ok", false)):
		daily_reset.text = ""
		_show_status(str(view.get("reason", "Quêtes indisponibles.")), true)
		return
	_show_status("")
	for entry in view.get("daily", []):
		daily_list.add_child(_quest_card(entry, true))
	for entry in view.get("unique", []):
		unique_list.add_child(_quest_card(entry, false))
	_update_countdown()


func _update_countdown() -> void:
	var seconds := Calendar.seconds_to_reset()
	var hours := floori(seconds / 3600.0)
	var minutes := floori(float(seconds % 3600) / 60.0)
	daily_reset.text = "Nouvelles quêtes dans %d h %02d" % [hours, minutes]


func _quest_card(entry: Dictionary, daily: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(
		UITheme.COL_PANEL_BG,
		UITheme.COL_WARNING if bool(entry["claimable"]) else UITheme.COL_BORDER, 3, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	row.add_child(content)
	content.add_child(_label(str(entry["title"]), UITheme.FONT_SUBTITLE - 6,
		UITheme.COL_ACCENT_LIGHT))
	var description := _label(str(entry["description"]), UITheme.FONT_SMALL - 4,
		UITheme.COL_TEXT_DIM)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	content.add_child(_gauge(entry))
	if int(entry["souls"]) > 0 or int(entry["candles"]) > 0:
		content.add_child(_reward_row(int(entry["souls"]), int(entry["candles"])))

	var action := VBoxContainer.new()
	action.custom_minimum_size = Vector2(240, 0)
	action.add_theme_constant_override("separation", 8)
	row.add_child(action)
	var button := TouchButtonScript.new() as Button
	button.custom_minimum_size = Vector2(240, 92)
	button.add_theme_font_size_override("font_size", 30)
	if bool(entry["claimable"]):
		button.text = "RÉCOLTER"
	elif bool(entry["finished"]):
		button.text = "TERMINÉ"
	else:
		button.text = "EN COURS"
	button.disabled = not bool(entry["claimable"])
	button.pressed.connect(_claim.bind(str(entry["id"])))
	action.add_child(button)
	if int(entry["tiers"]) > 1 and not bool(entry["finished"]):
		action.add_child(_label("Palier %d / %d" % [int(entry["tier_index"]) + 1,
			int(entry["tiers"])], UITheme.FONT_SMALL - 8, UITheme.COL_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER))
	return panel


func _gauge(entry: Dictionary) -> HBoxContainer:
	var gauge := HBoxContainer.new()
	gauge.add_theme_constant_override("separation", 12)
	var threshold := maxi(1, int(entry["threshold"]))
	var current := mini(maxi(0, int(entry["value"])), threshold)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 30)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.max_value = threshold
	bar.value = current
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#111016")
	background.border_color = UITheme.COL_BORDER
	background.set_border_width_all(2)
	background.set_corner_radius_all(9)
	bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.COL_SUCCESS if bool(entry["claimable"]) else UITheme.COL_ACCENT
	fill.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("fill", fill)
	gauge.add_child(bar)
	gauge.add_child(_label("%d / %d" % [current, threshold], UITheme.FONT_SMALL - 6,
		UITheme.COL_TEXT))
	return gauge


func _reward_row(souls: int, candles: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if souls > 0:
		row.add_child(_icon(SOUL_ICON))
		row.add_child(_label("%d âmes" % souls, UITheme.FONT_SMALL - 4,
			UITheme.COL_ACCENT_LIGHT))
	if candles > 0:
		row.add_child(_icon(CANDLE_ICON))
		row.add_child(_label("%d bougies" % candles, UITheme.FONT_SMALL - 4,
			UITheme.COL_WARNING))
	return row


func _label(text: String, size: int, color: Color,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	return label


func _icon(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(34, 34)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _clear(node: Node) -> void:
	# Détacher avant de libérer permet de reconstruire la liste depuis le signal
	# du bouton lui-même sans détruire l'émetteur en pleine notification.
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## ─── Réclamation ─────────────────────────────────────────────────────────────

func _claim(quest_id: String) -> void:
	var result := _service.claim(quest_id)
	if not bool(result.get("ok", false)):
		_build()
		_show_status(str(result.get("reason", "Récompense indisponible.")), true)
		return
	var parts: Array[String] = []
	if int(result.get("souls", 0)) > 0:
		parts.append("%d âmes" % int(result["souls"]))
	if int(result.get("candles", 0)) > 0:
		parts.append("%d bougies" % int(result["candles"]))
	var message := "Récompense déjà versée."
	if not parts.is_empty():
		message = "Récompense reçue : %s." % ", ".join(parts)
	_build()
	_show_status(message)


func _show_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.visible = message != ""
	status_label.add_theme_color_override("font_color",
		UITheme.COL_ERROR if is_error else UITheme.COL_SUCCESS)
