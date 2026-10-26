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
	set_type_variation("DangerButton", "Button")
	var danger := UITheme.button_style()
	danger.bg_color = UITheme.COL_DANGER
	danger.border_color = UITheme.COL_ERROR.darkened(0.2)
	set_stylebox("normal", "DangerButton", danger)
	var danger_hover := danger.duplicate() as StyleBoxFlat
	danger_hover.bg_color = UITheme.COL_DANGER.lightened(0.1)
	set_stylebox("hover", "DangerButton", danger_hover)
	set_stylebox("pressed", "DangerButton", danger)
	set_stylebox("normal", "LineEdit", UITheme.panel_style(UITheme.COL_TAB_IDLE))
	set_stylebox("focus", "LineEdit", UITheme.panel_style(Color.TRANSPARENT, UITheme.COL_ACCENT))
	set_color("font_color", "LineEdit", UITheme.COL_TEXT)
	set_color("font_placeholder_color", "LineEdit", UITheme.COL_TEXT_DIM)
	set_color("caret_color", "LineEdit", UITheme.COL_ACCENT_LIGHT)
	set_color("selection_color", "LineEdit", UITheme.COL_SELECTED.lightened(0.2))
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
	var focus := UITheme.panel_style(Color.TRANSPARENT, UITheme.COL_ACCENT_LIGHT, 3, 14)
	focus.shadow_size = 0
	set_stylebox("focus", type, focus)
