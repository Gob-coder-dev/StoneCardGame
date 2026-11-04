## GodCardTile.gd
## Case d'un dieu (ou de Pr.Stone) sur l'écran des Rencontres : portrait,
## nom, famille, cadre de famille et motif de fond. La vue ne connaît ni la
## navigation ni le profil ; elle émet seulement `pressed`.
extends "res://scripts/ui/input/TouchButton.gd"

const GodPortraitView := preload("res://scripts/ui/GodPortrait.gd")
const GodSigilView := preload("res://scripts/ui/encounters/GodSigil.gd")

var god_id: String = ""
var neutral: bool = false

var _god: Dictionary = {}
var _family_color := UITheme.COL_BORDER
var _sigil: GodSigilView
var _portrait: GodPortraitView = null
var _name_label: Label
var _family_label: Label


func setup(god: Dictionary, is_neutral: bool = false) -> void:
	_god = god
	god_id = str(god.get("id", ""))
	neutral = is_neutral
	_family_color = Color(str(god.get("color", UITheme.COL_BORDER.to_html())))
	_build_content()
	_apply_style()


func has_portrait() -> bool:
	return _portrait != null and _portrait.has_portrait()


func god_name_text() -> String:
	return _name_label.text


func family_text_value() -> String:
	return _family_label.text


func _build_content() -> void:
	text = ""
	autowrap_mode = TextServer.AUTOWRAP_OFF
	tooltip_text = "Choisir %s" % str(_god.get("name", "cet adversaire"))
	custom_minimum_size = Vector2(0, UITheme.GOD_TILE_NEUTRAL_HEIGHT if neutral \
		else UITheme.GOD_TILE_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_FILL

	_sigil = GodSigilView.new()
	_sigil.name = "Sigil"
	add_child(_sigil)
	_sigil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sigil.setup(god_id, _family_color, 0.20 if neutral else 0.15)

	var margin := MarginContainer.new()
	margin.name = "Content"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	if not neutral:
		_portrait = GodPortraitView.new()
		_portrait.name = "Portrait"
		_portrait.custom_minimum_size = Vector2(0, UITheme.GOD_TILE_PORTRAIT_HEIGHT)
		_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var frame := UITheme.panel_style(
			UITheme.COL_BG.darkened(0.18), _family_color.darkened(0.25), 2, 12)
		frame.content_margin_left = 6
		frame.content_margin_right = 6
		frame.content_margin_top = 6
		frame.content_margin_bottom = 6
		_portrait.add_theme_stylebox_override("panel", frame)
		_portrait.setup(_god)
		column.add_child(_portrait)

	_name_label = Label.new()
	_name_label.name = "Name"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.text = str(_god.get("name", "Adversaire")).to_upper()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 40 if neutral else 36)
	column.add_child(_name_label)

	_family_label = Label.new()
	_family_label.name = "Family"
	_family_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_family_label.text = str(_god.get("family_name", "Famille")).to_upper()
	_family_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_family_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_family_label.add_theme_font_size_override("font_size", 25 if neutral else 24)
	_family_label.add_theme_color_override("font_color", _family_color)
	column.add_child(_family_label)


func _apply_style() -> void:
	var background := UITheme.COL_TAB_IDLE if neutral else UITheme.COL_PANEL_BG
	var normal := UITheme.panel_style(background, _family_color.darkened(0.15), 3, 18)
	normal.content_margin_left = 0
	normal.content_margin_right = 0
	normal.content_margin_top = 0
	normal.content_margin_bottom = 0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = background.lightened(0.07)
	hover.border_color = _family_color.lightened(0.18)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = background.darkened(0.12)
	var focus := UITheme.panel_style(Color.TRANSPARENT, UITheme.COL_ACCENT_LIGHT, 3, 18)
	focus.shadow_size = 0
	focus.content_margin_left = 0
	focus.content_margin_right = 0
	focus.content_margin_top = 0
	focus.content_margin_bottom = 0
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed)
	add_theme_stylebox_override("hover_pressed", pressed)
	add_theme_stylebox_override("disabled", normal)
	add_theme_stylebox_override("focus", focus)
