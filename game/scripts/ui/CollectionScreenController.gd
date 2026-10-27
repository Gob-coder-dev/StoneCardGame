## Coordonne l'écran Cartes. Les règles du deck et les panneaux complexes
## vivent dans des composants séparés.
extends Control

const SortMode = CollectionGridView.SortMode
const Gesture := preload("res://scripts/ui/input/TapGesture.gd")

## Dans l'ordre de SortMode et des boutons du menu de tri.
const SORT_LABELS: Array[String] = ["FAMILLE", "COÛT", "RARETÉ", "NOM"]
const ACTION_DRAWER_SCENE := preload("res://scenes/ui/CardActionDrawer.tscn")
const DeckPanelView := preload("res://scripts/ui/collection/DeckPanel.gd")
const CollectionGridView := preload("res://scripts/ui/collection/CollectionGrid.gd")
const GodSelectorView := preload("res://scripts/ui/collection/GodSelector.gd")
const NumberedSelector := preload("res://scripts/ui/collection/NumberedSelector.gd")
var _deck_panel: RefCounted
var _collection_grid: RefCounted
var _god_selector: RefCounted
var _deck_slot_selector: NumberedSelector
var _level_selector: NumberedSelector
var _preview_level := 1

@onready var scroll: ScrollContainer = $Content/Scroll
@onready var god_button: Button = $Content/Scroll/Page/GodDeckPanel/GodDeckContent/GodDeckRow/GodButton
@onready var god_portrait: GodPortrait = $Content/Scroll/Page/GodDeckPanel/GodDeckContent/GodDeckRow/GodButton/Portrait
@onready var god_name: Label = $Content/Scroll/Page/GodDeckPanel/GodDeckContent/GodDeckRow/IdentityDeck/GodName
@onready var god_title: Label = $Content/Scroll/Page/GodDeckPanel/GodDeckContent/GodDeckRow/IdentityDeck/GodTitle
@onready var god_family: Label = $Content/Scroll/Page/GodDeckPanel/GodDeckContent/GodDeckRow/IdentityDeck/GodFamily
@onready var god_change_label: Label = $Content/Scroll/Page/GodDeckPanel/GodDeckContent/GodDeckRow/GodButton/ChangeLabel
@onready var god_description: Label = $Content/Scroll/Page/GodDeckPanel/GodDeckContent/GodDescription
@onready var god_menu: PanelContainer = $Content/Scroll/Page/GodMenu
@onready var god_options: GridContainer = $Content/Scroll/Page/GodMenu/GodOptions
@onready var deck_rows: VBoxContainer = $Content/Scroll/Page/DeckPanel/DeckContent/DeckRows
@onready var deck_count_label: Label = $Content/Scroll/Page/DeckPanel/DeckContent/DeckHeader/DeckCount
@onready var collection_rows: VBoxContainer = $Content/Scroll/Page/CollectionRows
@onready var sort_button: Button = $Content/Scroll/Page/CollectionHeader/SortButton
@onready var sort_menu: PanelContainer = $Content/Scroll/Page/SortMenu
@onready var sort_options: VBoxContainer = $Content/Scroll/Page/SortMenu/SortOptions
@onready var status_label: Label = $Content/StatusLabel
@onready var info_sheet: StoneInfoSheet = $StoneInfoSheet
@onready var replacement_panel: ReplacementPanel = $ReplacementPanel
@onready var level_button: Button = $Content/Scroll/Page/LevelButton
@onready var level_menu: PanelContainer = $Content/Scroll/Page/LevelMenu

var _current_deck: Array = []
var _sort_mode: int = SortMode.FAMILY
var _action_drawer: CardActionDrawer = null
var _action_card: StoneCard = null
var _action_stone_id: String = ""
var _action_source: int = -1
var _replacement_stone_id: String = ""
var _scroll_tap := Gesture.new()
var _suppress_scroll_tap: bool = false
var _clearing_scroll_tap: bool = false


func _ready() -> void:
	_current_deck = PlayerData.get_active_deck()
	scroll.gui_input.connect(_on_scroll_gui_input)
	god_button.pressed.connect(_toggle_god_menu)
	_deck_panel = DeckPanelView.new(deck_rows)
	_collection_grid = CollectionGridView.new(collection_rows)
	_god_selector = GodSelectorView.new(
		god_button, god_portrait, god_name, god_title, god_family,
		god_description, god_change_label, god_menu, god_options
	)
	_deck_slot_selector = NumberedSelector.new(
		$Content/Scroll/Page/GodDeckPanel/GodDeckContent/GodDeckRow/IdentityDeck/DeckSlots,
		DeckRules.DECKS_PER_GOD, 0
	)
	_level_selector = NumberedSelector.new($Content/Scroll/Page/LevelMenu/Levels, StoneEvolutionRules.MAX_PREVIEW_LEVEL)
	_deck_panel.card_requested.connect(_open_card_actions)
	_collection_grid.card_requested.connect(_open_card_actions)
	_god_selector.god_selected.connect(_select_god)
	_deck_slot_selector.value_selected.connect(_select_deck)
	_level_selector.value_selected.connect(_select_preview_level)
	_level_selector.refresh(_preview_level)
	level_button.pressed.connect(_toggle_level_menu)
	info_sheet.use_requested.connect(_request_use)
	_setup_sort()
	sort_button.pressed.connect(_toggle_sort_menu)
	replacement_panel.replacement_requested.connect(_on_replacement_requested)
	sort_menu.visible = false
	_refresh_all(false, true)


func _toggle_level_menu() -> void:
	_suppress_scroll_tap_once()
	_close_action_drawer()
	god_menu.visible = false
	sort_menu.visible = false
	_update_sort_labels()
	_refresh_god_panel()
	level_menu.visible = not level_menu.visible


func _select_preview_level(level: int) -> void:
	_close_action_drawer()
	_preview_level = level
	level_menu.visible = false
	level_button.text = "AFFICHER : NIVEAU %d ▼" % level
	_level_selector.refresh(level)
	_collection_grid.set_preview_level(level)


func _toggle_god_menu() -> void:
	_suppress_scroll_tap_once()
	_close_action_drawer()
	level_menu.visible = false
	sort_menu.visible = false
	_update_sort_labels()
	god_menu.visible = not god_menu.visible
	_refresh_god_panel()


func _select_god(next_god_id: String) -> void:
	if next_god_id == "" or next_god_id == PlayerData.player_god_id:
		god_menu.visible = false
		_refresh_god_panel()
		return
	if not PlayerData.set_player_god(next_god_id):
		_show_error("Impossible de changer de dieu : la sauvegarde a échoué.")
		return
	_close_card_panels()
	_current_deck = PlayerData.get_active_deck()
	god_menu.visible = false
	sort_menu.visible = false
	_update_sort_labels()
	_clear_status()
	_refresh_all(true, true)


func _select_deck(slot: int) -> void:
	if not PlayerData.set_selected_deck(slot):
		_show_error("Impossible de changer de deck : la sauvegarde a échoué.")
		_refresh_god_panel()
		return
	_close_card_panels()
	_current_deck = PlayerData.get_active_deck()
	god_menu.visible = false
	sort_menu.visible = false
	_update_sort_labels()
	_clear_status()
	_refresh_all()


func _close_card_panels() -> void:
	_close_action_drawer()
	info_sheet.close_sheet()
	replacement_panel.close_panel()
	_replacement_stone_id = ""
	level_menu.visible = false


## Les menus de dieu, de tri et de niveau sont posés dans le défilement.
## Le retour Android les referme avant de quitter l'écran.
func _close_inline_menus() -> void:
	god_menu.visible = false
	sort_menu.visible = false
	level_menu.visible = false
	_update_sort_labels()
	_refresh_god_panel()


## Un appui sur une zone vide referme le tiroir ou les menus ouverts. Les
## boutons et les cartes laissent passer leur relâchement jusqu'au défilement :
## on ignore donc le premier appui qui suit l'ouverture d'un panneau.
func _on_scroll_gui_input(event: InputEvent) -> void:
	if _scroll_tap.update(event, scroll) != Gesture.Result.TAP:
		return
	if _suppress_scroll_tap:
		return
	if info_sheet.visible or replacement_panel.visible:
		return
	if is_instance_valid(_action_drawer):
		_close_action_drawer()
	elif god_menu.visible or sort_menu.visible or level_menu.visible:
		_close_inline_menus()


func _suppress_scroll_tap_once() -> void:
	_suppress_scroll_tap = true
	if _clearing_scroll_tap:
		return
	_clearing_scroll_tap = true
	_clear_scroll_tap_deferred()


func _clear_scroll_tap_deferred() -> void:
	await get_tree().process_frame
	_suppress_scroll_tap = false
	_clearing_scroll_tap = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _go_back() -> void:
	if info_sheet.visible:
		info_sheet.close_sheet()
		return
	if replacement_panel.visible:
		replacement_panel.close_panel()
		_replacement_stone_id = ""
		return
	if is_instance_valid(_action_drawer):
		_close_action_drawer()
		return
	if god_menu.visible or sort_menu.visible or level_menu.visible:
		_close_inline_menus()
		return
	get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")


func _setup_sort() -> void:
	for index in range(sort_options.get_child_count()):
		var option := sort_options.get_child(index) as Button
		if option != null:
			option.pressed.connect(_select_sort.bind(index))
	_update_sort_labels()


func _toggle_sort_menu() -> void:
	_suppress_scroll_tap_once()
	_close_action_drawer()
	level_menu.visible = false
	god_menu.visible = false
	_refresh_god_panel()
	sort_menu.visible = not sort_menu.visible
	sort_button.text = "TRIER : %s %s" % [
		SORT_LABELS[_sort_mode], "▲" if sort_menu.visible else "▼"
	]


func _select_sort(index: int) -> void:
	_sort_mode = index
	_update_sort_labels()
	sort_menu.visible = false
	_populate_collection()


func _update_sort_labels() -> void:
	sort_button.text = "TRIER : %s ▼" % SORT_LABELS[_sort_mode]
	for index in range(sort_options.get_child_count()):
		var option := sort_options.get_child(index) as Button
		if option != null:
			option.text = "%s  %s" % ["✓" if index == _sort_mode else "  ", SORT_LABELS[index]]


func _refresh_all(preserve_scroll: bool = true, rebuild_collection: bool = false) -> void:
	var previous_scroll := scroll.scroll_vertical
	_close_action_drawer()
	_refresh_deck()
	if rebuild_collection:
		_populate_collection()
	else:
		_collection_grid.update_deck(_current_deck)
	_refresh_god_panel()
	var cost := DeckRules.deck_cost(_current_deck)
	deck_count_label.text = "%d/%d  •  %s/%d pts" % [
		_current_deck.size(), DeckRules.DECK_SIZE, UIFormat.cost(cost), DeckRules.DECK_BUDGET
	]
	deck_count_label.add_theme_color_override(
		"font_color",
		UITheme.COL_SUCCESS if DeckRules.is_deck_valid(_current_deck, PlayerData.player_god_id) else UITheme.COL_WARNING
	)
	if preserve_scroll:
		_restore_scroll_deferred(previous_scroll)


func _refresh_god_panel() -> void:
	_god_selector.refresh(PlayerData.player_god_id)
	_deck_slot_selector.refresh(PlayerData.get_selected_deck())


func _refresh_deck() -> void:
	_deck_panel.refresh(_current_deck)


func _populate_collection() -> void:
	_close_action_drawer()
	_collection_grid.rebuild(PlayerData.player_god_id, _current_deck, _sort_mode)


func _open_card_actions(stone_id: String, wrapper: VBoxContainer, source: int) -> void:
	_suppress_scroll_tap_once()
	if not StoneLoader.has_stone(stone_id):
		return
	if _action_stone_id == stone_id and _action_source == source and is_instance_valid(_action_drawer):
		_close_action_drawer()
		return
	_close_action_drawer()
	level_menu.visible = false
	god_menu.visible = false
	_refresh_god_panel()
	sort_menu.visible = false
	_update_sort_labels()
	_action_stone_id = stone_id
	_action_source = source
	_action_card = wrapper.get_child(0) as StoneCard
	if _action_card != null:
		_action_card.set_selected(true)
	_action_drawer = ACTION_DRAWER_SCENE.instantiate() as CardActionDrawer
	wrapper.add_child(_action_drawer)
	_action_drawer.setup(stone_id, source)
	_action_drawer.info_requested.connect(_on_info_requested)
	_action_drawer.primary_requested.connect(_on_primary_requested)


func _close_action_drawer() -> void:
	if is_instance_valid(_action_card):
		_action_card.set_selected(false)
	if is_instance_valid(_action_drawer):
		var parent := _action_drawer.get_parent()
		if parent != null:
			parent.remove_child(_action_drawer)
		_action_drawer.queue_free()
	_action_drawer = null
	_action_card = null
	_action_stone_id = ""
	_action_source = -1


func _on_info_requested(stone_id: String) -> void:
	info_sheet.open_for(stone_id, _current_deck)


func _on_primary_requested(stone_id: String, source: CardActionDrawer.Source) -> void:
	if source == CardActionDrawer.Source.DECK:
		_commit_operation(DeckRules.try_remove(_current_deck, stone_id))
		return
	_request_use(stone_id)


func _request_use(stone_id: String) -> void:
	var lineage := StoneLoader.stone_lineage(stone_id)
	var index := DeckRules.lineage_index(_current_deck, lineage)
	var operation: Dictionary
	if index >= 0:
		operation = DeckRules.try_set_level(_current_deck, lineage, StoneLoader.stone_level(stone_id), PlayerData.player_god_id)
	else:
		operation = DeckRules.try_add(_current_deck, stone_id, PlayerData.player_god_id)
	if operation["success"]:
		if _commit_operation(operation):
			info_sheet.close_sheet()
		return
	match operation["reason"]:
		DeckRules.REASON_FULL:
			_close_action_drawer()
			info_sheet.close_sheet()
			_replacement_stone_id = stone_id
			replacement_panel.open_for(_current_deck, stone_id)
		DeckRules.REASON_BUDGET:
			_show_error("Budget dépassé : %s/%d points." % [
				UIFormat.cost(operation["cost"]), DeckRules.DECK_BUDGET
			])


func _on_replacement_requested(old_id: String) -> void:
	var operation := DeckRules.try_replace(_current_deck, old_id, _replacement_stone_id, PlayerData.player_god_id)
	if not operation["success"]:
		if operation["reason"] == DeckRules.REASON_BUDGET:
			replacement_panel.show_budget_error(operation["cost"])
		return
	if _commit_operation(operation):
		replacement_panel.close_panel()
		_replacement_stone_id = ""


func _commit_operation(operation: Dictionary) -> bool:
	if not operation.get("success", false):
		return false
	var new_deck: Array = operation["deck"]
	if not PlayerData.set_player_deck(new_deck):
		_show_error("Impossible de modifier ce deck : la sauvegarde a échoué.")
		return false
	_current_deck = new_deck.duplicate()
	_clear_status()
	_refresh_all()
	return true


func _show_error(message: String) -> void:
	if replacement_panel.visible:
		replacement_panel.show_error(message)
		return
	if info_sheet.visible:
		info_sheet.show_error(message)
		return
	status_label.text = message
	status_label.add_theme_color_override("font_color", UITheme.COL_ERROR)
	status_label.visible = true


func _clear_status() -> void:
	status_label.text = ""
	status_label.visible = false


func _restore_scroll_deferred(value: int) -> void:
	await get_tree().process_frame
	scroll.scroll_vertical = value
