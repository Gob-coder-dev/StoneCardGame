## Tri, construction et filtrage de la collection, indépendants du contrôleur d'écran.
## Les cartes du deck n'apparaissent pas dans la collection : elles restent
## construites mais masquées, et la grille referme les trous sans recréer de carte.
extends RefCounted
signal card_requested(stone_id: String, wrapper: VBoxContainer, source: int)
enum SortMode { ORIGINAL, COST, RARITY, NAME }
const CARDS_PER_ROW := 3
## Espace entre deux cartes, horizontalement et verticalement.
const CARD_SPACING := 18
const Layout := preload("res://scripts/ui/collection/CardGridLayout.gd")
var collection_rows: VBoxContainer
var _grid: GridContainer = null
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

## Une modification du deck masque ou réaffiche seulement les cartes concernées.
## Les nœuds et la position de défilement sont conservés.
func update_deck(deck: Array) -> void:
	_current_deck = deck
	if not is_instance_valid(_grid):
		return
	for wrapper in _grid.get_children():
		var card: StoneCard = wrapper.get_child(0) as StoneCard if wrapper.get_child_count() > 0 else null
		if card != null:
			wrapper.visible = not deck.has(card.get_stone_id())

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

	# Une grille ignore ses cartes masquées : les suivantes remontent à leur place.
	_grid = GridContainer.new()
	_grid.columns = CARDS_PER_ROW
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", CARD_SPACING)
	_grid.add_theme_constant_override("v_separation", CARD_SPACING)
	collection_rows.add_child(_grid)
	for stone in stones:
		var wrapper := Layout.make_card_wrapper(true, UITheme.CARD_COLLECTION)
		var card := Layout.make_stone_card(stone, StoneCard.OWNER_NONE, UITheme.CARD_COLLECTION)
		card.name = "c_" + str(stone["id"])
		card.card_pressed.connect(card_requested.emit.bind(wrapper, CardActionDrawer.Source.COLLECTION))
		wrapper.add_child(card)
		wrapper.visible = not _current_deck.has(stone["id"])
		_grid.add_child(wrapper)
