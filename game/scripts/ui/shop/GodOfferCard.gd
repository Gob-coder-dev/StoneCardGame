## Fiche tactile d'un dieu. Comme les Rituels, elle ne fait qu'ouvrir la modale
## de confirmation et laisse la transaction au contrôleur de boutique.
class_name GodOfferCard
extends "res://scripts/ui/input/TouchButton.gd"

signal selection_requested(god_id: String)

const SoulIcon := preload("res://assets/ui/soul-placeholder.svg")


func setup(god: Dictionary, owned: bool, price: int) -> void:
	var god_id := str(god.get("id", ""))
	custom_minimum_size = Vector2(0, 190)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text = ""
	var accent := Color(str(god.get("color", UITheme.COL_BORDER.to_html())))
	add_theme_stylebox_override("normal", UITheme.panel_style(
		UITheme.COL_PANEL_BG, accent, 3, 14))
	add_theme_stylebox_override("hover", UITheme.panel_style(
		UITheme.COL_PANEL_BG.lightened(0.04), accent.lightened(0.18), 4, 14))
	add_theme_stylebox_override("pressed", UITheme.panel_style(
		UITheme.COL_PANEL_BG.darkened(0.08), accent, 4, 14))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var portrait := GodPortrait.new()
	portrait.custom_minimum_size = Vector2(150, 150)
	portrait.setup(god)
	row.add_child(portrait)
	var labels := VBoxContainer.new()
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(labels)
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = str(god.get("name", god_id)).to_upper()
	title.add_theme_font_size_override("font_size", 29)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels.add_child(title)
	if owned:
		var owned_label := Label.new()
		owned_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		owned_label.text = "DÉBLOQUÉ"
		owned_label.add_theme_font_size_override("font_size", 21)
		owned_label.add_theme_color_override("font_color", UITheme.COL_SUCCESS)
		owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		labels.add_child(owned_label)
	else:
		labels.add_child(_price_row(SoulIcon, price, 52, 31))
	disabled = owned
	if not owned:
		pressed.connect(selection_requested.emit.bind(god_id))


static func _price_row(icon_texture: Texture2D, amount: int,
		icon_size: int, font_size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Price"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = maxi(icon_size, 58)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.texture = icon_texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var value := Label.new()
	value.name = "Amount"
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.text = UIFormat.integer(amount)
	value.add_theme_font_size_override("font_size", font_size)
	value.add_theme_color_override("font_color", UITheme.COL_WARNING)
	row.add_child(value)
	return row
