## Affiche seulement les emplacements du deck et relaie les appuis.
extends RefCounted
signal card_requested(stone_id: String, wrapper: VBoxContainer, source: int)
const Layout := preload("res://scripts/ui/collection/CardGridLayout.gd")
var deck_rows: VBoxContainer
var _current_deck: Array = []

func _init(rows: VBoxContainer) -> void:
	deck_rows = rows

func refresh(deck: Array) -> void:
	_current_deck = deck
	_refresh_deck()

func _refresh_deck() -> void:
	Layout.clear_children(deck_rows)
	var first_row := Layout.make_card_row()
	deck_rows.add_child(first_row)
	for index in range(3):
		first_row.add_child(_make_deck_slot(index, true))

	var second_row := Layout.make_card_row()
	deck_rows.add_child(second_row)
	var left_spacer := Control.new()
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	second_row.add_child(left_spacer)
	for index in range(3, DeckRules.DECK_SIZE):
		second_row.add_child(_make_deck_slot(index, false))
	var right_spacer := Control.new()
	right_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	second_row.add_child(right_spacer)

func _make_deck_slot(index: int, expand: bool) -> Control:
	var wrapper := Layout.make_card_wrapper(expand, UITheme.CARD_DECK)
	if index < _current_deck.size():
		var stone_id: String = _current_deck[index]
		var card := Layout.make_stone_card(StoneLoader.get_stone(stone_id), StoneCard.OWNER_HUMAN, UITheme.CARD_DECK)
		card.card_pressed.connect(card_requested.emit.bind(wrapper, CardActionDrawer.Source.DECK))
		wrapper.add_child(card)
		return wrapper
	wrapper.add_child(Layout.make_empty_deck_slot())
	return wrapper
