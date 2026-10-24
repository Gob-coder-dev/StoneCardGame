## Affiche seulement les emplacements du deck et relaie les appuis.
extends RefCounted
signal card_requested(stone_id: String, wrapper: VBoxContainer, source: int)
const Layout := preload("res://scripts/ui/collection/CardGridLayout.gd")
## Emplacements du deck par rangée : deux rangées de 4 pour un deck de 8.
const SLOTS_PER_ROW := 4
var deck_rows: VBoxContainer
var _current_deck: Array = []

func _init(rows: VBoxContainer) -> void:
	deck_rows = rows

func refresh(deck: Array) -> void:
	_current_deck = deck
	_refresh_deck()

func _refresh_deck() -> void:
	Layout.clear_children(deck_rows)
	var row: HBoxContainer = null
	for index in range(DeckRules.DECK_SIZE):
		if index % SLOTS_PER_ROW == 0:
			row = Layout.make_card_row()
			deck_rows.add_child(row)
		row.add_child(_make_deck_slot(index, true))

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
