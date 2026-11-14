## Fiche tactile d'un Rituel. Elle ouvre seulement sa confirmation : aucun achat
## et aucun prix interactif ne vivent dans la grille de la boutique.
class_name RitualOfferCard
extends "res://scripts/ui/input/TouchButton.gd"

signal selection_requested(ritual_id: String)

const CandleIcon := preload("res://assets/ui/candle-placeholder.svg")

var definition: Dictionary = {}


func setup(value: Dictionary) -> void:
	definition = value.duplicate(true)
	custom_minimum_size = Vector2(0, 510)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text = ""
	var blood := Color(str(value.get("blood_color", "#a62f35")))
	add_theme_stylebox_override("normal", UITheme.panel_style(
		UITheme.COL_PANEL_BG, blood, 3, 18))
	add_theme_stylebox_override("hover", UITheme.panel_style(
		UITheme.COL_PANEL_BG.lightened(0.04), blood.lightened(0.16), 4, 18))
	add_theme_stylebox_override("pressed", UITheme.panel_style(
		UITheme.COL_PANEL_BG.darkened(0.08), blood.lightened(0.08), 4, 18))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = str(value.get("name", "Rituel")).to_upper()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 30)
	box.add_child(name_label)
	var sigil := RitualSigil.new()
	sigil.name = "Sigil"
	sigil.custom_minimum_size = Vector2(0, 330)
	sigil.setup(value)
	box.add_child(sigil)
	var price_row := HBoxContainer.new()
	price_row.name = "Price"
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.custom_minimum_size.y = 74
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	price_row.add_theme_constant_override("separation", 9)
	var portrait := TextureRect.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.texture = CandleIcon
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	price_row.add_child(portrait)
	var price := Label.new()
	price.name = "Amount"
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.text = UIFormat.integer(int(value.get("price_candles", 0)))
	price.add_theme_font_size_override("font_size", 40)
	price.add_theme_color_override("font_color", UITheme.COL_WARNING)
	price_row.add_child(price)
	box.add_child(price_row)
	pressed.connect(selection_requested.emit.bind(str(value.get("id", ""))))
