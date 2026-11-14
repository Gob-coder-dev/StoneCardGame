## Fabrique du thème depuis la palette unique, appelée après création de l'arbre.
## La ressource de thème est constituée de données, sans constructeur GDScript :
## `gui/theme/custom` peut ainsi la charger avant le SceneTree et le débogueur.
extends RefCounted

const Palette := preload("res://scripts/ui/UITheme.gd")


## Remplit `theme` avec tous les styles du jeu. Appelé une seule fois.
static func apply(theme: Theme) -> void:
	theme.default_font_size = Palette.FONT_BODY
	theme.set_color("font_color", "Label", Palette.COL_TEXT)
	theme.set_color("default_color", "RichTextLabel", Palette.COL_TEXT)
	theme.set_font_size("normal_font_size", "RichTextLabel", Palette.FONT_BODY)
	theme.set_font_size("bold_font_size", "RichTextLabel", Palette.FONT_BODY)
	theme.set_type_variation("ScreenTitle", "Label")
	theme.set_color("font_color", "ScreenTitle", Palette.COL_TEXT)
	theme.set_font_size("font_size", "ScreenTitle", Palette.FONT_TITLE)
	theme.set_type_variation("SectionTitle", "Label")
	theme.set_color("font_color", "SectionTitle", Palette.COL_ACCENT_LIGHT)
	theme.set_font_size("font_size", "SectionTitle", Palette.FONT_SUBTITLE)
	theme.set_stylebox("panel", "PanelContainer", Palette.panel_style())
	theme.set_type_variation("DeckPanel", "PanelContainer")
	var deck_panel := Palette.panel_style()
	deck_panel.content_margin_bottom = Palette.GAP_MEDIUM
	theme.set_stylebox("panel", "DeckPanel", deck_panel)
	theme.set_stylebox("panel", "Panel", Palette.panel_style())
	_buttons(theme, "Button", false)
	theme.set_type_variation("PrimaryButton", "Button")
	_buttons(theme, "PrimaryButton", true)
	theme.set_type_variation("UpgradeButton", "Button")
	_upgrade_button(theme)
	theme.set_type_variation("DangerButton", "Button")
	var danger := Palette.button_style()
	danger.bg_color = Palette.COL_DANGER
	danger.border_color = Palette.COL_ERROR.darkened(0.2)
	theme.set_stylebox("normal", "DangerButton", danger)
	var danger_hover := danger.duplicate() as StyleBoxFlat
	danger_hover.bg_color = Palette.COL_DANGER.lightened(0.1)
	theme.set_stylebox("hover", "DangerButton", danger_hover)
	theme.set_stylebox("pressed", "DangerButton", danger)
	# Le mode PVP reste secondaire par rapport à CAMPAGNE : ardoise plus sombre
	# et liseré néon, jamais le fond d'action principale.
	theme.set_type_variation("PvpButton", "Button")
	_buttons(theme, "PvpButton", false)
	var pvp := Palette.button_style()
	pvp.bg_color = Palette.COL_SURFACE.darkened(0.22)
	pvp.border_color = Palette.COL_NEON
	pvp.set_border_width_all(3)
	theme.set_stylebox("normal", "PvpButton", pvp)
	var pvp_hover := pvp.duplicate() as StyleBoxFlat
	pvp_hover.bg_color = Palette.COL_SURFACE.darkened(0.05)
	pvp_hover.border_color = Palette.COL_ACCENT_LIGHT
	theme.set_stylebox("hover", "PvpButton", pvp_hover)
	var pvp_pressed := pvp.duplicate() as StyleBoxFlat
	pvp_pressed.bg_color = Palette.COL_SURFACE.darkened(0.35)
	theme.set_stylebox("pressed", "PvpButton", pvp_pressed)
	theme.set_stylebox("hover_pressed", "PvpButton", pvp_pressed)
	theme.set_color("font_color", "PvpButton", Palette.COL_ACCENT_LIGHT)
	theme.set_stylebox("normal", "LineEdit", Palette.panel_style(Palette.COL_TAB_IDLE))
	theme.set_stylebox("focus", "LineEdit", Palette.panel_style(Color.TRANSPARENT, Palette.COL_ACCENT))
	theme.set_color("font_color", "LineEdit", Palette.COL_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Palette.COL_TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", Palette.COL_ACCENT_LIGHT)
	theme.set_color("selection_color", "LineEdit", Palette.COL_SELECTED.lightened(0.2))
	_dropdowns(theme)
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, _scroll_style(Palette.COL_BG))
		theme.set_stylebox("grabber", type, _scroll_style(Palette.COL_BORDER))
		theme.set_stylebox("grabber_highlight", type, _scroll_style(Palette.COL_TEXT_DIM))
		theme.set_stylebox("grabber_pressed", type, _scroll_style(Palette.COL_ACCENT))


static func _scroll_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


static func _buttons(theme: Theme, type: String, primary: bool) -> void:
	theme.set_font_size("font_size", type, 38)
	var text_color := Palette.COL_INK if primary else Palette.COL_TEXT
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, type, text_color)
	theme.set_color("font_disabled_color", type, Color("#898e9b"))
	theme.set_stylebox("normal", type, Palette.button_style(primary))
	theme.set_stylebox("hover", type, Palette.button_style(primary, false, true))
	theme.set_stylebox("pressed", type, Palette.button_style(primary, true))
	theme.set_stylebox("hover_pressed", type, Palette.button_style(primary, true, true))
	theme.set_stylebox("disabled", type, Palette.panel_style(Palette.COL_TAB_IDLE, Palette.COL_TAB_BORDER))
	var focus := Palette.panel_style(Color.TRANSPARENT, Palette.COL_NEON_PINK, 3, 14)
	focus.shadow_size = 0
	theme.set_stylebox("focus", type, focus)


## L'amélioration est une dépense, pas l'action principale de navigation : son
## violet minéral et son liseré doré la distinguent du bouton orange UTILISER.
static func _upgrade_button(theme: Theme) -> void:
	theme.set_font_size("font_size", "UpgradeButton", Palette.FONT_BODY)
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color"]:
		theme.set_color(state, "UpgradeButton", Color.TRANSPARENT)
	theme.set_color("font_disabled_color", "UpgradeButton", Color.TRANSPARENT)
	var normal := Palette.button_style()
	normal.bg_color = Palette.COL_SELECTED
	normal.border_color = Palette.COL_WARNING
	theme.set_stylebox("normal", "UpgradeButton", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Palette.COL_SELECTED.lightened(0.10)
	theme.set_stylebox("hover", "UpgradeButton", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Palette.COL_SELECTED.darkened(0.16)
	pressed.border_width_bottom = 3
	theme.set_stylebox("pressed", "UpgradeButton", pressed)
	theme.set_stylebox("hover_pressed", "UpgradeButton", pressed)
	var disabled := Palette.panel_style(
		Palette.COL_TAB_IDLE, Palette.COL_WARNING.darkened(0.48), 2, 14)
	theme.set_stylebox("disabled", "UpgradeButton", disabled)
	var focus := Palette.panel_style(Color.TRANSPARENT, Palette.COL_WARNING, 3, 14)
	focus.shadow_size = 0
	theme.set_stylebox("focus", "UpgradeButton", focus)


## Les OptionButton ouvrent un PopupMenu dans une fenêtre séparée : les deux
## types doivent être stylés explicitement, sinon le menu natif de Godot fuit
## au milieu de l'identité visuelle du jeu.
static func _dropdowns(theme: Theme) -> void:
	_buttons(theme, "OptionButton", false)
	theme.set_font_size("font_size", "OptionButton", Palette.FONT_SMALL)
	theme.set_color("font_color", "OptionButton", Palette.COL_TEXT)
	theme.set_color("font_hover_color", "OptionButton", Palette.COL_ACCENT_LIGHT)
	theme.set_color("font_pressed_color", "OptionButton", Palette.COL_ACCENT_LIGHT)
	theme.set_color("font_disabled_color", "OptionButton", Palette.COL_TEXT_DIM.darkened(0.25))
	theme.set_color("modulate_arrow", "OptionButton", Palette.COL_ACCENT_LIGHT)
	theme.set_constant("arrow_margin", "OptionButton", Palette.GAP_SMALL)

	var popup_panel := Palette.panel_style(
		Palette.COL_BG.lightened(0.025), Palette.COL_NEON, 3, 14)
	popup_panel.content_margin_left = 8
	popup_panel.content_margin_right = 8
	popup_panel.content_margin_top = 8
	popup_panel.content_margin_bottom = 8
	theme.set_stylebox("panel", "PopupMenu", popup_panel)
	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = Palette.COL_SELECTED
	popup_hover.border_color = Palette.COL_ACCENT_LIGHT
	popup_hover.set_border_width_all(2)
	popup_hover.set_corner_radius_all(10)
	popup_hover.content_margin_top = 10
	popup_hover.content_margin_bottom = 10
	theme.set_stylebox("hover", "PopupMenu", popup_hover)
	var separator := StyleBoxLine.new()
	separator.color = Palette.COL_BORDER
	separator.thickness = 2
	separator.grow_begin = -Palette.GAP_SMALL
	separator.grow_end = -Palette.GAP_SMALL
	theme.set_stylebox("separator", "PopupMenu", separator)
	theme.set_color("font_color", "PopupMenu", Palette.COL_TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Palette.COL_ACCENT_LIGHT)
	theme.set_color("font_disabled_color", "PopupMenu", Palette.COL_TEXT_DIM.darkened(0.25))
	theme.set_color("font_separator_color", "PopupMenu", Palette.COL_TEXT_DIM)
	theme.set_font_size("font_size", "PopupMenu", Palette.FONT_SMALL)
	theme.set_constant("v_separation", "PopupMenu", 10)
	theme.set_constant("item_start_padding", "PopupMenu", Palette.GAP_MEDIUM)
	theme.set_constant("item_end_padding", "PopupMenu", Palette.GAP_MEDIUM)
