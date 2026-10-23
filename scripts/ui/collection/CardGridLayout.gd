## Fabrique visuelle partagée par le deck et la grille de collection.
extends RefCounted

static func make_card_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	return row

static func make_card_wrapper(expand: bool, card_size: float) -> VBoxContainer:
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size = Vector2(card_size, 0)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_SHRINK_CENTER
	wrapper.add_theme_constant_override("separation", 0)
	return wrapper

static func make_stone_card(stone: Dictionary, owner: int, card_size: float) -> StoneCard:
	var card := StoneCard.new()
	card.custom_minimum_size = Vector2(0, card_size)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.setup(stone, owner)
	card.set_show_cost(true)
	return card

static func make_empty_deck_slot() -> Panel:
	var empty := Panel.new()
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty.custom_minimum_size = Vector2(UITheme.CARD_DECK, UITheme.CARD_DECK)
	empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#160e08")
	style.border_color = Color("#58452a")
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	empty.add_theme_stylebox_override("panel", style)
	var plus := Label.new()
	plus.text = "+"
	plus.set_anchors_preset(Control.PRESET_FULL_RECT)
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.add_theme_font_size_override("font_size", 72)
	plus.add_theme_color_override("font_color", Color("#6c5938"))
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty.add_child(plus)
	return empty

static func clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
