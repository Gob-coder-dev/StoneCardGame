## Vue du sélecteur de dieu. La modification du profil reste au contrôleur.
extends RefCounted

signal god_selected(god_id: String)

const TouchButtonScript := preload("res://scripts/ui/input/TouchButton.gd")
const GodPortraitView := preload("res://scripts/ui/GodPortrait.gd")

var god_button: Button
var selected_portrait: GodPortrait
var god_name: Label
var god_title: Label
var god_family: Label
var god_description: Label
var change_label: Label
var god_menu: PanelContainer
var god_options: GridContainer
var _option_buttons: Dictionary = {}
var _option_gods: Dictionary = {}
var _shown_god_id := ""


func _init(button: Button, portrait: GodPortrait, name_label: Label, title_label: Label,
		family_label: Label, description: Label, change: Label,
		menu: PanelContainer, options: GridContainer) -> void:
	god_button = button
	selected_portrait = portrait
	god_name = name_label
	god_title = title_label
	god_family = family_label
	god_description = description
	change_label = change
	god_menu = menu
	god_options = options
	_setup_god_menu()


## Les six choix tiennent dans une grille 3 × 2. Chaque bouton reste le seul
## récepteur tactile ; son contenu décoratif ignore les événements.
func _setup_god_menu() -> void:
	for child in god_options.get_children():
		god_options.remove_child(child)
		child.queue_free()
	_option_buttons.clear()
	_option_gods.clear()
	for god in StoneLoader.get_all_gods():
		var option: Button = TouchButtonScript.new()
		option.custom_minimum_size = Vector2(0, UITheme.GOD_DRAWER_TILE_HEIGHT)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.tooltip_text = "Équiper %s" % str(god.get("name", "ce dieu"))
		option.set_meta("god_id", str(god.get("id", "")))
		option.add_child(_make_option_content(god))
		option.pressed.connect(god_selected.emit.bind(str(god.get("id", ""))))
		god_options.add_child(option)
		_option_buttons[str(god.get("id", ""))] = option
		_option_gods[str(god.get("id", ""))] = god


func _make_option_content(god: Dictionary) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.name = "Content"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_top = 12
	content.offset_right = -12
	content.offset_bottom = -12
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 5)

	var portrait := GodPortraitView.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(0, 198)
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.setup(god)
	content.add_child(portrait)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = str(god.get("name", "Dieu")).to_upper()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 31)
	content.add_child(name_label)

	var family_label := Label.new()
	family_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	family_label.text = str(god.get("family_name", "Famille"))
	family_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	family_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	family_label.add_theme_font_size_override("font_size", 24)
	family_label.add_theme_color_override("font_color", Color(str(god.get("color", UITheme.COL_TEXT.to_html()))))
	content.add_child(family_label)
	return content


func refresh(god_id: String) -> void:
	var god := StoneLoader.get_god(god_id)
	change_label.text = "CHANGER  %s" % ("▲" if god_menu.visible else "▼")
	if god_id == _shown_god_id:
		return
	_shown_god_id = god_id
	selected_portrait.setup(god)
	god_name.text = str(god.get("name", "Dieu")).to_upper()
	god_title.text = str(god.get("title", "")).capitalize()
	god_family.text = str(god.get("family_name", "Famille"))
	god_description.text = str(god.get("description", ""))
	var god_color := Color(str(god.get("color", UITheme.COL_TEXT.to_html())))
	god_family.add_theme_color_override("font_color", god_color)
	god_description.add_theme_color_override("font_color", god_color.lightened(0.16))
	for option_id in _option_buttons:
		_style_option(_option_buttons[option_id], _option_gods[option_id], option_id == god_id)


func _style_option(button: Button, god: Dictionary, selected: bool) -> void:
	var family_color := Color(str(god.get("color", UITheme.COL_BORDER.to_html())))
	var border_color := UITheme.COL_ACCENT_LIGHT if selected else family_color.darkened(0.12)
	var background := UITheme.COL_SELECTED if selected else UITheme.COL_TAB_IDLE
	var normal := UITheme.panel_style(background, border_color, 6 if selected else 3, 14)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = background.lightened(0.08)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = background.darkened(0.10)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	var portrait := button.get_node("Content/Portrait") as GodPortrait
	if portrait != null:
		portrait.set_emphasized(selected)
