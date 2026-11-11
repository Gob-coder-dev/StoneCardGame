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
const RITUAL_ICONS := {
	"triangle": preload("res://assets/ui/ritual-triangle.svg"),
	"pentagram": preload("res://assets/ui/ritual-pentagram.svg"),
	"heptagram": preload("res://assets/ui/ritual-heptagram.svg"),
	"demon_heptagram": preload("res://assets/ui/ritual-demon.svg"),
}

@onready var background: MenuBackground = $Background
@onready var close_button: Button = $Root/Header/CloseButton
@onready var content: VBoxContainer = $Root/Scroll/Content
@onready var scroll: ScrollContainer = $Root/Scroll
@onready var daily_panel: PanelContainer = $Root/Scroll/Content/DailyPanel
@onready var unique_panel: PanelContainer = $Root/Scroll/Content/UniquePanel
@onready var daily_list: VBoxContainer = $Root/Scroll/Content/DailyPanel/DailyContent/DailyList
@onready var unique_list: VBoxContainer = $Root/Scroll/Content/UniquePanel/UniqueList
@onready var status_label: Label = $Root/Status

var _service := QuestServiceModel.new()
var _daily_subtitle: Label
var _unique_subtitle: Label
## Vignettes en attente de leur illustration, par chemin d'asset.
var _card_art: Dictionary = {}


func _ready() -> void:
	background.set_god(GodIdentityModel.player(PlayerData.player_god_id))
	close_button.pressed.connect(_close)
	_style_sections()
	_build_headers()
	CardArtCache.texture_ready.connect(_on_card_art_ready)
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


## ─── Sections ────────────────────────────────────────────────────────────────

## Chaque famille a sa couleur et son cadre : les deux listes ne se confondent
## plus, alors que les cartes gardent exactement le même langage visuel.
func _style_sections() -> void:
	daily_panel.add_theme_stylebox_override("panel",
		_section_style(UITheme.COL_ACCENT))
	unique_panel.add_theme_stylebox_override("panel",
		_section_style(UITheme.COL_NEON))


func _section_style(accent: Color) -> StyleBoxFlat:
	var style := UITheme.panel_style(UITheme.COL_PANEL_BG, accent, 3, 18)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	return style


## Un seul constructeur pour les deux en-têtes : alignement et typographie
## restent identiques, seule la couleur distingue les familles.
func _build_headers() -> void:
	var daily := _make_header("QUÊTES QUOTIDIENNES", UITheme.COL_ACCENT)
	var daily_root := daily["root"] as Control
	content.add_child(daily_root)
	content.move_child(daily_root, daily_panel.get_index())
	_daily_subtitle = daily["subtitle"] as Label

	var unique := _make_header("QUÊTES UNIQUES", UITheme.COL_NEON)
	var unique_root := unique["root"] as Control
	content.add_child(unique_root)
	content.move_child(unique_root, unique_panel.get_index())
	_unique_subtitle = unique["subtitle"] as Label


func _make_header(title: String, accent: Color) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	root.add_child(row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", UITheme.FONT_SUBTITLE)
	label.add_theme_color_override("font_color", accent)
	row.add_child(label)
	var rule := ColorRect.new()
	rule.color = Color(accent, 0.45)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rule)
	var subtitle := Label.new()
	subtitle.add_theme_font_size_override("font_size", UITheme.FONT_SMALL - 6)
	subtitle.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	root.add_child(subtitle)
	return {"root": root, "subtitle": subtitle}


## ─── Construction ────────────────────────────────────────────────────────────

func _build() -> void:
	_card_art.clear()
	_clear(daily_list)
	_clear(unique_list)
	var view := _service.view()
	if not bool(view.get("ok", false)):
		_daily_subtitle.text = ""
		_unique_subtitle.text = ""
		_show_status(str(view.get("reason", "Quêtes indisponibles.")), true)
		return
	_show_status("")
	var daily: Array = view.get("daily", [])
	var unique: Array = view.get("unique", [])
	for entry in daily:
		daily_list.add_child(_quest_card(entry, true))
	for entry in unique:
		unique_list.add_child(_quest_card(entry, false))
	var finished := 0
	for entry in unique:
		if bool(entry.get("finished", false)):
			finished += 1
	_unique_subtitle.text = "%d / %d terminées" % [finished, unique.size()]
	_update_countdown()


func _update_countdown() -> void:
	if _daily_subtitle == null:
		return
	var seconds := Calendar.seconds_to_reset()
	var hours := floori(seconds / 3600.0)
	var minutes := floori(float(seconds % 3600) / 60.0)
	_daily_subtitle.text = "Nouvelles quêtes dans %d h %02d" % [hours, minutes]


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
	var rewards := _reward_row(entry)
	if rewards.get_child_count() > 0:
		content.add_child(rewards)

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


## Les récompenses tiennent sur une seule ligne compacte : une puce par lot,
## qui passe à la ligne plutôt que d'élargir la carte de quête.
func _reward_row(entry: Dictionary) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 18)
	row.add_theme_constant_override("v_separation", 8)
	var souls := int(entry.get("souls", 0))
	if souls > 0:
		row.add_child(_chip(SOUL_ICON, "%d âmes" % souls, UITheme.COL_ACCENT_LIGHT))
	var candles := int(entry.get("candles", 0))
	if candles > 0:
		row.add_child(_chip(CANDLE_ICON, "%d bougies" % candles, UITheme.COL_WARNING))
	for raw_card in entry.get("cards", []):
		if raw_card is Dictionary:
			row.add_child(_card_chip(raw_card))
	var ritual: Dictionary = entry.get("ritual", {})
	if not ritual.is_empty():
		row.add_child(_ritual_chip(ritual))
	return row


func _chip(texture: Texture2D, text: String, color: Color) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 6)
	chip.add_child(_icon(texture))
	chip.add_child(_label(text, UITheme.FONT_SMALL - 6, color))
	return chip


func _card_chip(card: Dictionary) -> HBoxContainer:
	var card_name := str(card.get("name", ""))
	var rarity := str(card.get("rarity", "common"))
	var maxed := bool(card.get("maxed", false))
	var deferred := bool(card.get("deferred", false))
	var suffix := ""
	if maxed:
		suffix = " · carte maximale"
	elif deferred:
		suffix = " · après %s" % _god_name(str(card.get("god_id", "")))
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 6)
	chip.tooltip_text = "%s · %s%s" % [card_name, _rarity_label(rarity), suffix]
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",
		_thumb_style(UITheme.rarity_color(rarity)))
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(44, 44)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if deferred:
		art.modulate = Color(0.7, 0.7, 0.78, 0.85)
	var asset := str(card.get("asset", ""))
	frame.add_child(art)
	chip.add_child(frame)
	if asset != "":
		if not _card_art.has(asset):
			_card_art[asset] = []
		(_card_art[asset] as Array).append(art)
		var loaded := CardArtCache.texture(asset)
		if loaded != null:
			art.texture = loaded
	var text := "×%d" % int(card.get("copies", 1))
	if maxed:
		text = "+%d âmes" % int(card.get("compensation_souls", 0))
	chip.add_child(_label(text, UITheme.FONT_SMALL - 6,
		UITheme.COL_WARNING if maxed or deferred else UITheme.COL_TEXT))
	return chip


func _ritual_chip(ritual: Dictionary) -> HBoxContainer:
	var sigil := str(ritual.get("sigil", "triangle"))
	var color := Color(str(ritual.get("color", "#a62f35"))).lightened(0.35)
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 6)
	chip.tooltip_text = "Rituel offert : %s" % str(ritual.get("name", "Rituel"))
	var icon := TextureRect.new()
	icon.texture = RITUAL_ICONS.get(sigil, RITUAL_ICONS.get("triangle")) as Texture2D
	icon.modulate = color
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(icon)
	chip.add_child(_label(str(ritual.get("name", "Rituel")),
		UITheme.FONT_SMALL - 8, color))
	return chip


func _thumb_style(color: Color) -> StyleBoxFlat:
	var style := UITheme.panel_style(UITheme.COL_BG, color, 2, 10)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_size = 0
	return style


func _rarity_label(rarity: String) -> String:
	match rarity:
		"rare": return "rare"
		"epic": return "épique"
		"legendary": return "légendaire"
		_: return "commune"


func _on_card_art_ready(path: String, texture: Texture2D) -> void:
	for node in _card_art.get(path, []):
		if is_instance_valid(node):
			(node as TextureRect).texture = texture


func _god_name(god_id: String) -> String:
	return str(StoneLoader.get_god(god_id).get("name", god_id))


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
	var offset := scroll.scroll_vertical
	var result := _service.claim(quest_id)
	if not bool(result.get("ok", false)):
		_build()
		_show_status(str(result.get("reason", "Récompense indisponible.")), true)
		await _restore_scroll(offset)
		return
	var opening: Dictionary = result.get("opening", {})
	if not opening.is_empty():
		if _open_ritual(opening):
			return
		_build()
		_show_status("La présentation du Rituel a échoué, mais les récompenses sont acquises.", true)
		await _restore_scroll(offset)
		return
	_build()
	_show_status(_reward_message(result))
	await _restore_scroll(offset)


func _open_ritual(opening: Dictionary) -> bool:
	if not RitualOpeningContext.begin(opening):
		return false
	if GameRoutes.go(get_tree(), Routes.RITUAL_OPENING) == OK:
		return true
	RitualOpeningContext.clear()
	return false


## Reconstruire la liste déplace les cartes : on rend au joueur la position de
## défilement qu'il avait avant de récolter.
func _restore_scroll(offset: int) -> void:
	await get_tree().process_frame
	scroll.scroll_vertical = offset


func _reward_message(result: Dictionary) -> String:
	var parts: Array[String] = []
	if int(result.get("souls", 0)) > 0:
		parts.append("%d âmes" % int(result["souls"]))
	if int(result.get("candles", 0)) > 0:
		parts.append("%d bougies" % int(result["candles"]))
	for raw_card in result.get("cards", []):
		if not raw_card is Dictionary:
			continue
		var card: Dictionary = raw_card
		if bool(card.get("maxed", false)):
			parts.append("%d âmes (carte maximale)" % int(card.get("compensation_souls", 0)))
		elif bool(card.get("deferred", false)):
			parts.append("%d copies de %s (après %s)" % [int(card.get("copies", 0)),
				str(card.get("name", "")), _god_name(str(card.get("god_id", "")))])
		else:
			parts.append("%d copies de %s" % [int(card.get("copies", 0)),
				str(card.get("name", ""))])
	if parts.is_empty():
		return "Récompense déjà versée."
	return "Récompense reçue : %s." % ", ".join(parts)


func _show_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.visible = message != ""
	status_label.add_theme_color_override("font_color",
		UITheme.COL_ERROR if is_error else UITheme.COL_SUCCESS)
