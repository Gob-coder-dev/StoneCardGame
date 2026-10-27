## Affiche seulement les emplacements du deck et relaie les appuis.
extends RefCounted
signal card_requested(stone_id: String, wrapper: VBoxContainer, source: int)
const Layout := preload("res://scripts/ui/collection/CardGridLayout.gd")
var deck_rows: VBoxContainer
var _current_deck: Array = []

func _init(rows: VBoxContainer) -> void:
	deck_rows = rows
	deck_rows.add_theme_constant_override("separation", UITheme.DECK_CARD_GAP)

func refresh(deck: Array) -> void:
	_current_deck = deck
	_refresh_deck()

func _refresh_deck() -> void:
	Layout.clear_children(deck_rows)
	var row: HBoxContainer = null
	for index in range(DeckRules.DECK_SIZE):
		if index % UITheme.DECK_COLUMNS == 0:
			row = Layout.make_card_row()
			row.add_theme_constant_override("separation", UITheme.DECK_CARD_GAP)
			deck_rows.add_child(row)
		row.add_child(_make_deck_slot(index, true))

func _make_deck_slot(index: int, expand: bool) -> Control:
	var wrapper := Layout.make_card_wrapper(expand, UITheme.CARD_DECK)
	# Les lames dépassent légèrement de la case ; le tiroir reste en dessous.
	wrapper.add_theme_constant_override("separation", UITheme.GAP_MEDIUM)
	wrapper.resized.connect(_fit_slot.bind(wrapper))
	if index < _current_deck.size():
		var stone_id: String = _current_deck[index]
		var card := Layout.make_stone_card(StoneLoader.get_stone(stone_id), StoneCard.OWNER_HUMAN, UITheme.CARD_DECK)
		card.set_edge_margin_ratio(UITheme.CARD_DECK_EDGE_MARGIN)
		card.set_marker_scale(StoneCard.BLADE_MARGIN / UITheme.CARD_DECK_EDGE_MARGIN)
		card.card_pressed.connect(card_requested.emit.bind(wrapper, CardActionDrawer.Source.DECK))
		wrapper.add_child(card)
		return wrapper
	wrapper.add_child(Layout.make_empty_deck_slot())
	return wrapper


## La case reste carrée, remplie ou vide, quand le conteneur répartit sa largeur.
## Le tiroir reste un second enfant : sa hauteur ne réduit jamais la carte.
func _fit_slot(wrapper: VBoxContainer) -> void:
	if wrapper.size.x <= 0 or wrapper.get_child_count() == 0:
		return
	var slot := wrapper.get_child(0) as Control
	if not is_equal_approx(slot.custom_minimum_size.y, wrapper.size.x):
		slot.custom_minimum_size.y = wrapper.size.x
