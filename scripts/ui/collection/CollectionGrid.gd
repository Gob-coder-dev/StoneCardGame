## Tri, construction et sélection de la collection, indépendants du contrôleur d'écran.
extends RefCounted
signal card_requested(stone_id: String, wrapper: VBoxContainer, source: int)
enum SortMode { ORIGINAL, COST, RARITY, NAME }
const CARDS_PER_ROW := 3
const Layout := preload("res://scripts/ui/collection/CardGridLayout.gd")
var collection_rows: VBoxContainer
var _current_deck: Array = []
var _sort_mode: SortMode = SortMode.ORIGINAL
var _god_id: String = ""

func _init(rows: VBoxContainer) -> void:
	collection_rows = rows

func rebuild(god_id: String, deck: Array, sorting: int) -> void:
	_god_id = god_id
	_current_deck = deck
	_sort_mode = sorting as SortMode
	_populate_collection()

## Une modification du deck conserve les cartes et la position de défilement.
func update_selection(deck: Array) -> void:
	_current_deck = deck
	for row in collection_rows.get_children():
		for wrapper in row.get_children():
			if wrapper.get_child_count() > 0 and wrapper.get_child(0) is StoneCard:
				var card: StoneCard = wrapper.get_child(0)
				card.set_selected(deck.has(card.get_stone_id()))

func _populate_collection() -> void:
	Layout.clear_children(collection_rows)
	var stones: Array = StoneLoader.get_stones_for_god(_god_id)
	match _sort_mode:
		SortMode.COST:
			stones.sort_custom(func(a, b): return StoneLoader.stone_cost(a["id"]) < StoneLoader.stone_cost(b["id"]))
		SortMode.RARITY:
			var rarity_order := {"legendary": 0, "epic": 1, "rare": 2, "uncommon": 3, "common": 4}
			stones.sort_custom(func(a, b): return rarity_order.get(a["rarity"], 9) < rarity_order.get(b["rarity"], 9))
		SortMode.NAME:
			stones.sort_custom(func(a, b): return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)

	for row_start in range(0, stones.size(), CARDS_PER_ROW):
		var row := Layout.make_card_row()
		collection_rows.add_child(row)
		for column in range(CARDS_PER_ROW):
			var index := row_start + column
			if index >= stones.size():
				var spacer := Control.new()
				spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
				spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(spacer)
				continue
			var stone: Dictionary = stones[index]
			var wrapper := Layout.make_card_wrapper(true, UITheme.CARD_COLLECTION)
			var card := Layout.make_stone_card(stone, StoneCard.OWNER_NONE, UITheme.CARD_COLLECTION)
			card.name = "c_" + str(stone["id"])
			card.set_selected(_current_deck.has(stone["id"]))
			card.card_pressed.connect(card_requested.emit.bind(wrapper, CardActionDrawer.Source.COLLECTION))
			wrapper.add_child(card)
			row.add_child(wrapper)
