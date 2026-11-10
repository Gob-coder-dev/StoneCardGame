## Ressource commune construite depuis la palette unique de UITheme.
@tool
extends Theme


func _init() -> void:
	default_font_size = UITheme.FONT_BODY
	set_color("font_color", "Label", UITheme.COL_TEXT)
	set_color("default_color", "RichTextLabel", UITheme.COL_TEXT)
	set_font_size("normal_font_size", "RichTextLabel", UITheme.FONT_BODY)
	set_font_size("bold_font_size", "RichTextLabel", UITheme.FONT_BODY)
	set_type_variation("ScreenTitle", "Label")
	set_color("font_color", "ScreenTitle", UITheme.COL_TEXT)
	set_font_size("font_size", "ScreenTitle", UITheme.FONT_TITLE)
	set_type_variation("SectionTitle", "Label")
	set_color("font_color", "SectionTitle", UITheme.COL_ACCENT_LIGHT)
	set_font_size("font_size", "SectionTitle", UITheme.FONT_SUBTITLE)
	set_stylebox("panel", "PanelContainer", UITheme.panel_style())
	set_type_variation("DeckPanel", "PanelContainer")
	var deck_panel := UITheme.panel_style()
	deck_panel.content_margin_bottom = UITheme.GAP_MEDIUM
	set_stylebox("panel", "DeckPanel", deck_panel)
	set_stylebox("panel", "Panel", UITheme.panel_style())
	_buttons("Button", false)
	set_type_variation("PrimaryButton", "Button")
	_buttons("PrimaryButton", true)
	set_type_variation("UpgradeButton", "Button")
	_upgrade_button()
	set_type_variation("DangerButton", "Button")
	var danger := UITheme.button_style()
	danger.bg_color = UITheme.COL_DANGER
	danger.border_color = UITheme.COL_ERROR.darkened(0.2)
	set_stylebox("normal", "DangerButton", danger)
	var danger_hover := danger.duplicate() as StyleBoxFlat
	danger_hover.bg_color = UITheme.COL_DANGER.lightened(0.1)
	set_stylebox("hover", "DangerButton", danger_hover)
	set_stylebox("pressed", "DangerButton", danger)
	# Le mode PVP reste secondaire par rapport à CAMPAGNE : ardoise plus sombre
	# et liseré néon, jamais le fond d'action principale.
	set_type_variation("PvpButton", "Button")
	_buttons("PvpButton", false)
	var pvp := UITheme.button_style()
	pvp.bg_color = UITheme.COL_SURFACE.darkened(0.22)
	pvp.border_color = UITheme.COL_NEON
	pvp.set_border_width_all(3)
	set_stylebox("normal", "PvpButton", pvp)
	var pvp_hover := pvp.duplicate() as StyleBoxFlat
	pvp_hover.bg_color = UITheme.COL_SURFACE.darkened(0.05)
	pvp_hover.border_color = UITheme.COL_ACCENT_LIGHT
	set_stylebox("hover", "PvpButton", pvp_hover)
	var pvp_pressed := pvp.duplicate() as StyleBoxFlat
	pvp_pressed.bg_color = UITheme.COL_SURFACE.darkened(0.35)
	set_stylebox("pressed", "PvpButton", pvp_pressed)
	set_stylebox("hover_pressed", "PvpButton", pvp_pressed)
	set_color("font_color", "PvpButton", UITheme.COL_ACCENT_LIGHT)
	set_stylebox("normal", "LineEdit", UITheme.panel_style(UITheme.COL_TAB_IDLE))
	set_stylebox("focus", "LineEdit", UITheme.panel_style(Color.TRANSPARENT, UITheme.COL_ACCENT))
	set_color("font_color", "LineEdit", UITheme.COL_TEXT)
	set_color("font_placeholder_color", "LineEdit", UITheme.COL_TEXT_DIM)
	set_color("caret_color", "LineEdit", UITheme.COL_ACCENT_LIGHT)
	set_color("selection_color", "LineEdit", UITheme.COL_SELECTED.lightened(0.2))
	_dropdowns()
	for type in ["VScrollBar", "HScrollBar"]:
		set_stylebox("scroll", type, _scroll_style(UITheme.COL_BG))
		set_stylebox("grabber", type, _scroll_style(UITheme.COL_BORDER))
		set_stylebox("grabber_highlight", type, _scroll_style(UITheme.COL_TEXT_DIM))
		set_stylebox("grabber_pressed", type, _scroll_style(UITheme.COL_ACCENT))


func _scroll_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _buttons(type: String, primary: bool) -> void:
	set_font_size("font_size", type, 38)
	var text_color := UITheme.COL_INK if primary else UITheme.COL_TEXT
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		set_color(state, type, text_color)
	set_color("font_disabled_color", type, Color("#898e9b"))
	set_stylebox("normal", type, UITheme.button_style(primary))
	set_stylebox("hover", type, UITheme.button_style(primary, false, true))
	set_stylebox("pressed", type, UITheme.button_style(primary, true))
	set_stylebox("hover_pressed", type, UITheme.button_style(primary, true, true))
	set_stylebox("disabled", type, UITheme.panel_style(UITheme.COL_TAB_IDLE, UITheme.COL_TAB_BORDER))
	var focus := UITheme.panel_style(Color.TRANSPARENT, UITheme.COL_NEON_PINK, 3, 14)
	focus.shadow_size = 0
	set_stylebox("focus", type, focus)


## L'amélioration est une dépense, pas l'action principale de navigation : son
## violet minéral et son liseré doré la distinguent du bouton orange UTILISER.
func _upgrade_button() -> void:
	set_font_size("font_size", "UpgradeButton", UITheme.FONT_BODY)
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color"]:
		set_color(state, "UpgradeButton", Color.TRANSPARENT)
	set_color("font_disabled_color", "UpgradeButton", Color.TRANSPARENT)
	var normal := UITheme.button_style()
	normal.bg_color = UITheme.COL_SELECTED
	normal.border_color = UITheme.COL_WARNING
	set_stylebox("normal", "UpgradeButton", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = UITheme.COL_SELECTED.lightened(0.10)
	set_stylebox("hover", "UpgradeButton", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = UITheme.COL_SELECTED.darkened(0.16)
	pressed.border_width_bottom = 3
	set_stylebox("pressed", "UpgradeButton", pressed)
	set_stylebox("hover_pressed", "UpgradeButton", pressed)
	var disabled := UITheme.panel_style(
		UITheme.COL_TAB_IDLE, UITheme.COL_WARNING.darkened(0.48), 2, 14)
	set_stylebox("disabled", "UpgradeButton", disabled)
	var focus := UITheme.panel_style(Color.TRANSPARENT, UITheme.COL_WARNING, 3, 14)
	focus.shadow_size = 0
	set_stylebox("focus", "UpgradeButton", focus)


## Les OptionButton ouvrent un PopupMenu dans une fenêtre séparée : les deux
## types doivent être stylés explicitement, sinon le menu natif de Godot fuit
## au milieu de l'identité visuelle du jeu.
func _dropdowns() -> void:
	_buttons("OptionButton", false)
	set_font_size("font_size", "OptionButton", UITheme.FONT_SMALL)
	set_color("font_color", "OptionButton", UITheme.COL_TEXT)
	set_color("font_hover_color", "OptionButton", UITheme.COL_ACCENT_LIGHT)
	set_color("font_pressed_color", "OptionButton", UITheme.COL_ACCENT_LIGHT)
	set_color("font_disabled_color", "OptionButton", UITheme.COL_TEXT_DIM.darkened(0.25))
	set_color("modulate_arrow", "OptionButton", UITheme.COL_ACCENT_LIGHT)
	set_constant("arrow_margin", "OptionButton", UITheme.GAP_SMALL)

	var popup_panel := UITheme.panel_style(
		UITheme.COL_BG.lightened(0.025), UITheme.COL_NEON, 3, 14)
	popup_panel.content_margin_left = 8
	popup_panel.content_margin_right = 8
	popup_panel.content_margin_top = 8
	popup_panel.content_margin_bottom = 8
	set_stylebox("panel", "PopupMenu", popup_panel)
	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = UITheme.COL_SELECTED
	popup_hover.border_color = UITheme.COL_ACCENT_LIGHT
	popup_hover.set_border_width_all(2)
	popup_hover.set_corner_radius_all(10)
	popup_hover.content_margin_top = 10
	popup_hover.content_margin_bottom = 10
	set_stylebox("hover", "PopupMenu", popup_hover)
	var separator := StyleBoxLine.new()
	separator.color = UITheme.COL_BORDER
	separator.thickness = 2
	separator.grow_begin = -UITheme.GAP_SMALL
	separator.grow_end = -UITheme.GAP_SMALL
	set_stylebox("separator", "PopupMenu", separator)
	set_color("font_color", "PopupMenu", UITheme.COL_TEXT)
	set_color("font_hover_color", "PopupMenu", UITheme.COL_ACCENT_LIGHT)
	set_color("font_disabled_color", "PopupMenu", UITheme.COL_TEXT_DIM.darkened(0.25))
	set_color("font_separator_color", "PopupMenu", UITheme.COL_TEXT_DIM)
	set_font_size("font_size", "PopupMenu", UITheme.FONT_SMALL)
	set_constant("v_separation", "PopupMenu", 10)
	set_constant("item_start_padding", "PopupMenu", UITheme.GAP_MEDIUM)
	set_constant("item_end_padding", "PopupMenu", UITheme.GAP_MEDIUM)
