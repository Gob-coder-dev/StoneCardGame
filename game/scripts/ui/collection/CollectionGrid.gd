## Tri, construction et filtrage de la collection, indépendants du contrôleur d'écran.
## Les cartes du deck n'apparaissent pas dans la collection : elles restent
## construites mais masquées, et la grille referme les trous sans recréer de carte.
extends RefCounted
signal card_requested(stone_id: String, wrapper: VBoxContainer, source: int)
const CardProgressView := preload("res://scripts/ui/economy/CardProgressBar.gd")
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
var locked_collection_rows: VBoxContainer
var locked_collection_title: Label
var _owned_grid: GridContainer = null
var _locked_grid: GridContainer = null
var _current_deck: Array = []
var _sort_mode: SortMode = SortMode.FAMILY
var _god_id: String = ""
var _preview_level := 1
var _wrappers: Dictionary = {}


## Expose les cartes visibles comme cibles de surbrillance. Le scénario ne
## manipule jamais la grille : il ne connaît que l'identifiant de la carte.
func register_story_anchors() -> void:
	for raw_lineage in _wrappers.keys():
		var wrapper: VBoxContainer = _wrappers[raw_lineage]
		if not is_instance_valid(wrapper) or wrapper.get_child_count() == 0:
			continue
		if not wrapper.visible:
			continue
		var card := wrapper.get_child(0) as StoneCard
		if card != null:
			StoryService.register_anchor("collection.card.%s" % card.get_stone_id(), wrapper)

func _init(rows: VBoxContainer, locked_rows: VBoxContainer, locked_title: Label) -> void:
	collection_rows = rows
	locked_collection_rows = locked_rows
	locked_collection_title = locked_title

func rebuild(god_id: String, deck: Array, sorting: int) -> void:
	_god_id = god_id
	_current_deck = deck
	_sort_mode = sorting as SortMode
	_populate_collection()

## Une modification du deck masque ou réaffiche seulement les cartes concernées.
## Les nœuds et la position de défilement sont conservés.
func update_deck(deck: Array) -> void:
	_current_deck = deck
	if not is_instance_valid(_owned_grid):
		return
	for grid in [_owned_grid, _locked_grid]:
		for wrapper in grid.get_children():
			var card: StoneCard = wrapper.get_child(0) as StoneCard if wrapper.get_child_count() > 0 else null
			if card != null:
				wrapper.visible = DeckRules.lineage_index(deck, StoneLoader.stone_lineage(card.get_stone_id())) < 0


func set_preview_level(level: int) -> void:
	_preview_level = level
	if not is_instance_valid(_owned_grid):
		return
	_populate_collection()

func _populate_collection() -> void:
	var stones := _displayed_stones()
	stones.sort_custom(_sorts_before)
	_ensure_grids()
	var desired := {}
	for stone in stones:
		desired[StoneLoader.stone_lineage(str(stone["id"]))] = stone
	var reusable := _detach_obsolete_wrappers(desired)
	var owned_ordered: Array[VBoxContainer] = []
	var locked_ordered: Array[VBoxContainer] = []
	for stone in stones:
		var lineage := StoneLoader.stone_lineage(str(stone["id"]))
		var wrapper: VBoxContainer = _wrappers.get(lineage)
		if wrapper == null:
			wrapper = reusable.pop_back() if not reusable.is_empty() else _make_wrapper()
			_wrappers[lineage] = wrapper
		var card := wrapper.get_child(0) as StoneCard
		if card.get_stone_id() != str(stone["id"]):
			card.setup(stone, StoneCard.OWNER_NONE)
			card.name = "c_" + str(stone["id"])
		_update_progress(wrapper, lineage, str(stone["id"]))
		wrapper.visible = DeckRules.lineage_index(_current_deck, lineage) < 0
		# La section décrit exactement la variante actuellement affichée. Posséder
		# la N1 ne rend donc pas sa N2 possédée tant que cette évolution est verrouillée.
		var unlocked_level := int(PlayerData.card_entry(lineage).get("unlocked_level", 0))
		var displayed_level := StoneLoader.stone_level(str(stone["id"]))
		if unlocked_level >= displayed_level:
			owned_ordered.append(wrapper)
		else:
			locked_ordered.append(wrapper)
	for wrapper in reusable:
		if wrapper.get_parent() != null:
			wrapper.get_parent().remove_child(wrapper)
		wrapper.queue_free()
	_place_ordered(_owned_grid, owned_ordered)
	_place_ordered(_locked_grid, locked_ordered)
	locked_collection_rows.visible = not locked_ordered.is_empty()
	locked_collection_title.visible = not locked_ordered.is_empty()


func _displayed_stones() -> Array:
	var stones: Array = []
	var lineages := StoneLoader.get_neutral_lineages() if _god_id == "" \
		else StoneLoader.get_lineages_for_god(_god_id)
	for base in lineages:
		var stone_id := StoneLoader.preview_variant(str(base["id"]), _preview_level)
		stones.append(StoneLoader.get_stone(stone_id))
	return stones


func _ensure_grids() -> void:
	if is_instance_valid(_owned_grid):
		return
	_owned_grid = _make_grid("OwnedGrid")
	_locked_grid = _make_grid("LockedGrid")
	collection_rows.add_child(_owned_grid)
	locked_collection_rows.add_child(_locked_grid)


func _make_grid(grid_name: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = grid_name
	grid.columns = CARDS_PER_ROW
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", CARD_SPACING)
	grid.add_theme_constant_override("v_separation", CARD_SPACING)
	return grid


func _place_ordered(grid: GridContainer, ordered: Array[VBoxContainer]) -> void:
	for index in range(ordered.size()):
		var wrapper := ordered[index]
		if wrapper.get_parent() != grid:
			if wrapper.get_parent() != null:
				wrapper.get_parent().remove_child(wrapper)
			grid.add_child(wrapper)
		grid.move_child(wrapper, index)


func _detach_obsolete_wrappers(desired: Dictionary) -> Array[VBoxContainer]:
	var reusable: Array[VBoxContainer] = []
	for raw_lineage in _wrappers.keys():
		var lineage := str(raw_lineage)
		if desired.has(lineage):
			continue
		reusable.append(_wrappers[lineage])
		_wrappers.erase(lineage)
	return reusable


func _make_wrapper() -> VBoxContainer:
	var wrapper := Layout.make_card_wrapper(true, UITheme.CARD_COLLECTION)
	var card := Layout.make_stone_card({}, StoneCard.OWNER_NONE, UITheme.CARD_COLLECTION)
	card.card_pressed.connect(card_requested.emit.bind(wrapper, CardActionDrawer.Source.COLLECTION))
	wrapper.add_child(card)
	var progress := CardProgressView.new()
	progress.name = "Progress"
	wrapper.add_child(progress)
	return wrapper


func _update_progress(wrapper: VBoxContainer, lineage_id: String, shown_stone_id: String) -> void:
	var card := wrapper.get_child(0) as StoneCard
	var progress := wrapper.get_node("Progress") as CardProgressBar
	var entry := PlayerData.card_entry(lineage_id)
	var unlocked := int(entry.get("unlocked_level", 0))
	var shown_owned := unlocked >= StoneLoader.stone_level(shown_stone_id)
	card.modulate = Color.WHITE if shown_owned else Color(0.38, 0.38, 0.43, 0.72)
	progress.setup(lineage_id)


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
