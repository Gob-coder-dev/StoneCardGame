## Tri, construction et filtrage de la collection, indépendants du contrôleur d'écran.
## Les cartes du deck n'apparaissent pas dans la collection : elles restent
## construites mais masquées, et la grille referme les trous sans recréer de carte.
extends RefCounted
signal card_requested(stone_id: String, wrapper: VBoxContainer, source: int)
## FAMILY : les cartes du dieu, puis les neutres, chaque groupe du moins cher
## au plus cher. Chaque tri départage les
## ex aequo par le nom, pour un ordre toujours identique.
enum SortMode { FAMILY, COST, RARITY, NAME }
const RARITY_ORDER := {"legendary": 0, "epic": 1, "rare": 2, "uncommon": 3, "common": 4}
const CARDS_PER_ROW := 3
## Espace entre deux cartes, horizontalement et verticalement.
const CARD_SPACING := 18
const Layout := preload("res://scripts/ui/collection/CardGridLayout.gd")
var collection_rows: VBoxContainer
var _grid: GridContainer = null
var _current_deck: Array = []
var _sort_mode: SortMode = SortMode.FAMILY
var _god_id: String = ""
var _preview_level := 1
var _wrappers: Dictionary = {}

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
			wrapper.visible = DeckRules.lineage_index(deck, StoneLoader.stone_lineage(card.get_stone_id())) < 0


func set_preview_level(level: int) -> void:
	_preview_level = level
	if not is_instance_valid(_grid):
		return
	var displayed: Array = []
	for lineage in _wrappers:
		var id := StoneLoader.variant_id(lineage, StoneEvolutionRules.preview_level(level, StoneLoader.lineage_max_level(lineage)))
		var card: StoneCard = _wrappers[lineage].get_child(0)
		var definition := StoneLoader.get_stone(id)
		if card.get_stone_id() != id:
			card.setup(definition, StoneCard.OWNER_NONE)
		displayed.append(definition)
	displayed.sort_custom(_sorts_before)
	for index in range(displayed.size()):
		_grid.move_child(_wrappers[StoneLoader.stone_lineage(str(displayed[index]["id"]))], index)

func _populate_collection() -> void:
	Layout.clear_children(collection_rows)
	_wrappers.clear()
	var stones: Array = []
	for base in StoneLoader.get_lineages_for_god(_god_id):
		stones.append(StoneLoader.get_stone(StoneLoader.preview_variant(str(base["id"]), _preview_level)))
	stones.sort_custom(_sorts_before)

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
		var lineage := StoneLoader.stone_lineage(str(stone["id"]))
		_wrappers[lineage] = wrapper
		wrapper.visible = DeckRules.lineage_index(_current_deck, lineage) < 0
		_grid.add_child(wrapper)


## Comparaison du tri choisi ; le nom départage les égalités.
func _sorts_before(a: Dictionary, b: Dictionary) -> bool:
	var key_a := 0.0
	var key_b := 0.0
	match _sort_mode:
		SortMode.FAMILY:
			# Les cartes du dieu avant les neutres, puis par coût dans chaque groupe.
			var neutral_a := str(a.get("god_id", "neutral")) == "neutral"
			var neutral_b := str(b.get("god_id", "neutral")) == "neutral"
			if neutral_a != neutral_b:
				return neutral_b
			key_a = StoneLoader.stone_cost(a["id"])
			key_b = StoneLoader.stone_cost(b["id"])
		SortMode.COST:
			key_a = StoneLoader.stone_cost(a["id"])
			key_b = StoneLoader.stone_cost(b["id"])
		SortMode.RARITY:
			key_a = RARITY_ORDER.get(a.get("rarity", ""), 9)
			key_b = RARITY_ORDER.get(b.get("rarity", ""), 9)
	if key_a != key_b:
		return key_a < key_b
	return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
