## Bouton de réinitialisation payante de la boutique. Il ne décide d'aucune
## dépense : le contrôleur consulte l'état du service et ouvre la confirmation.
class_name ShopRefreshButton
extends "res://scripts/ui/input/TouchButton.gd"

const CandleIcon := preload("res://assets/ui/candle-placeholder.svg")
const RefreshIcon := preload("res://assets/ui/refresh.svg")
const MIN_SIZE := Vector2(164, 72)

var glyph_icon: TextureRect
var price_label: Label
var candle_icon: TextureRect


func _ready() -> void:
	Audio.set_button_sfx(self, AudioCatalog.SFX_BUTTON_2)
	text = ""
	custom_minimum_size = MIN_SIZE
	add_theme_stylebox_override("normal", _button_style(
		UITheme.COL_SURFACE, UITheme.COL_BORDER))
	add_theme_stylebox_override("hover", _button_style(
		UITheme.COL_SURFACE.lightened(0.05), UITheme.COL_ACCENT_LIGHT))
	add_theme_stylebox_override("pressed", _button_style(
		UITheme.COL_SURFACE.darkened(0.08), UITheme.COL_ACCENT))
	add_theme_stylebox_override("disabled", _button_style(
		UITheme.COL_PANEL_BG, UITheme.COL_BORDER))
	var content := HBoxContainer.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT,
		Control.PRESET_MODE_MINSIZE, 8)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 5)
	add_child(content)
	glyph_icon = TextureRect.new()
	glyph_icon.name = "Glyph"
	glyph_icon.custom_minimum_size = Vector2(38, 38)
	glyph_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_icon.texture = RefreshIcon
	glyph_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(glyph_icon)
	price_label = Label.new()
	price_label.name = "Price"
	price_label.text = "—"
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_label.add_theme_font_size_override("font_size", 30)
	price_label.add_theme_color_override("font_color", UITheme.COL_WARNING)
	content.add_child(price_label)
	candle_icon = TextureRect.new()
	candle_icon.name = "Candle"
	candle_icon.custom_minimum_size = Vector2(32, 32)
	candle_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	candle_icon.texture = CandleIcon
	candle_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	candle_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(candle_icon)
	setup(0, false, "Boutique indisponible.")


func setup(price: int, available: bool, reason: String = "") -> void:
	var safe_price := maxi(0, price)
	if price_label != null:
		price_label.text = UIFormat.integer(safe_price) if safe_price > 0 else "—"
	disabled = not available
	modulate = Color(1, 1, 1, 1) if available else Color(0.62, 0.62, 0.62, 0.62)
	if available and safe_price > 0:
		tooltip_text = "Réinitialiser la boutique pour %s bougie%s." % [
			UIFormat.integer(safe_price), "" if safe_price == 1 else "s"]
	else:
		tooltip_text = reason if reason != "" else "Réinitialisation indisponible."
	accessibility_name = tooltip_text


static func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := UITheme.panel_style(bg, border, 2, 14)
	style.content_margin_left = 10
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
