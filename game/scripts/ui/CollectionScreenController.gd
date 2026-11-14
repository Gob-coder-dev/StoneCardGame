## Coordonne l'écran Cartes. Les règles du deck et les panneaux complexes
## vivent dans des composants séparés.
extends Control

const Routes := preload("res://scripts/ui/GameRoutes.gd")
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")

const SortMode = CollectionGridView.SortMode
const Gesture := preload("res://scripts/ui/input/TapGesture.gd")

## Dans l'ordre de SortMode et des boutons du menu de tri.
const SORT_LABELS: Array[String] = ["FAMILLE", "COÛT", "RARETÉ", "NOM"]
const ACTION_DRAWER_SCENE := preload("res://scenes/ui/CardActionDrawer.tscn")
const DeckPanelView := preload("res://scripts/ui/collection/DeckPanel.gd")
const CollectionGridView := preload("res://scripts/ui/collection/CollectionGrid.gd")
const GodSelectorView := preload("res://scripts/ui/collection/GodSelector.gd")
const NumberedSelector := preload("res://scripts/ui/collection/NumberedSelector.gd")
const ActionPlacement := preload("res://scripts/ui/collection/CardActionPlacement.gd")
const EconomyServiceModel := preload("res://scripts/application/economy/EconomyService.gd")
const ACTION_DRAWER_GAP := 10.0
const ACTION_DRAWER_MARGIN := 24.0
const BOTTOM_SPACER_DEFAULT := 30.0
const CLEAR_DECK_CONFIRMATION: String = "Voulez-vous vraiment supprimer complètement ce deck ?"
var _deck_panel: RefCounted
var _collection_grid: RefCounted
var _god_selector: RefCounted
var _deck_slot_selector: NumberedSelector
var _level_selector: NumberedSelector
var _preview_level := 1

@onready var scroll: ScrollContainer = $Content/Scroll
@onready var background: MenuBackground = $Background
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
@onready var clear_deck_button: Button = \
	$Content/Scroll/Page/DeckPanel/DeckContent/DeckHeader/ClearDeckButton
@onready var collection_rows: VBoxContainer = $Content/Scroll/Page/CollectionRows
@onready var locked_collection_rows: VBoxContainer = $Content/Scroll/Page/LockedCollectionRows
@onready var locked_collection_title: Label = $Content/Scroll/Page/LockedCollectionTitle
@onready var pending_rewards_button: Button = \
	$Content/Scroll/Page/CollectionTitle/PendingRewardsButton
@onready var pending_rewards_badge: Label = \
	$Content/Scroll/Page/CollectionTitle/PendingRewardsButton/Badge
@onready var pending_rewards_vault: PendingRewardsVault = $PendingRewardsVault
@onready var sort_button: Button = $Content/Scroll/Page/CollectionHeader/SortButton
@onready var sort_menu: PanelContainer = $Content/Scroll/Page/SortMenu
@onready var sort_options: VBoxContainer = $Content/Scroll/Page/SortMenu/SortOptions
@onready var status_label: Label = $Content/StatusLabel
@onready var info_sheet: StoneInfoSheet = $StoneInfoSheet
@onready var replacement_panel: ReplacementPanel = $ReplacementPanel
@onready var confirm_popup: ConfirmPopup = $ConfirmPopup
@onready var level_button: Button = $Content/Scroll/Page/LevelButton
@onready var level_menu: PanelContainer = $Content/Scroll/Page/LevelMenu
@onready var action_drawer_layer: Control = $ActionDrawerLayer
@onready var bottom_spacer: Control = $Content/Scroll/Page/BottomSpacer

var _current_deck: Array = []
var _sort_mode: int = SortMode.FAMILY
var _action_drawer: CardActionDrawer = null
var _action_card: StoneCard = null
var _action_wrapper: Control = null
var _action_stone_id: String = ""
var _action_source: int = -1
var _replacement_stone_id: String = ""
var _scroll_tap := Gesture.new()
var _outside_pointer: int = -1
var _outside_origin := Vector2.ZERO
var _outside_canceled: bool = false
var _adjusting_drawer_scroll: bool = false
var _suppress_scroll_tap: bool = false
var _clearing_scroll_tap: bool = false


func _ready() -> void:
	_current_deck = PlayerData.get_active_deck()
	_prepare_card_art()
	scroll.gui_input.connect(_on_scroll_gui_input)
	scroll.scroll_started.connect(_close_action_drawer)
	scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_value_changed)
	action_drawer_layer.resized.connect(_position_action_drawer)
	god_button.pressed.connect(_toggle_god_menu)
	_deck_panel = DeckPanelView.new(deck_rows)
	_collection_grid = CollectionGridView.new(collection_rows, locked_collection_rows,
		locked_collection_title)
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
	info_sheet.upgrade_requested.connect(_upgrade_card)
	_setup_sort()
	sort_button.pressed.connect(_toggle_sort_menu)
	replacement_panel.replacement_requested.connect(_on_replacement_requested)
	pending_rewards_button.pressed.connect(_open_pending_rewards)
	pending_rewards_vault.shop_requested.connect(_open_shop_from_vault)
	clear_deck_button.pressed.connect(_request_clear_deck)
	confirm_popup.confirmed.connect(_clear_deck)
	if not PlayerData.inventory_changed.is_connected(_on_inventory_changed):
		PlayerData.inventory_changed.connect(_on_inventory_changed)
	sort_menu.visible = false
	_refresh_all(false, true)
	StoryService.spotlight_requested.connect(_on_story_spotlight_requested)
	StoryService.notify_screen(Routes.COLLECTION)


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
	_prepare_card_art()
	level_menu.visible = false
	level_button.text = "AFFICHER : NIVEAU %d ▼" % level
	_level_selector.refresh(level)
	_collection_grid.set_preview_level(level)
	_register_story_anchors()


func _toggle_god_menu() -> void:
	_suppress_scroll_tap_once()
	_close_action_drawer()
	level_menu.visible = false
	sort_menu.visible = false
	_update_sort_labels()
	god_menu.visible = not god_menu.visible
	_refresh_god_panel()


func _select_god(next_god_id: String) -> void:
	if next_god_id == PlayerData.player_god_id:
		god_menu.visible = false
		_refresh_god_panel()
		return
	if not PlayerData.set_player_god(next_god_id):
		_show_error("Impossible de changer de dieu : la sauvegarde a échoué.")
		return
	_close_card_panels()
	_current_deck = PlayerData.get_active_deck()
	_prepare_card_art()
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
	_prepare_card_art()
	god_menu.visible = false
	sort_menu.visible = false
	_update_sort_labels()
	_clear_status()
	_refresh_all()


func _close_card_panels() -> void:
	_close_action_drawer()
	_dismiss_confirm_popup()
	info_sheet.close_sheet()
	replacement_panel.close_panel()
	_replacement_stone_id = ""
	level_menu.visible = false


## Le retour, un changement de dieu ou d'emplacement annulent la demande en
## cours : aucune confirmation ne doit survivre au deck qu'elle décrivait.
func _dismiss_confirm_popup() -> void:
	if confirm_popup.is_open():
		confirm_popup.dismiss()


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


## Les panneaux flottants ne doivent pas dépendre du contrôle situé sous le
## doigt : un Label ou un bouton peut consommer l'événement avant le Scroll.
## On ferme donc ici tout panneau touché depuis l'extérieur, au relâchement
## d'un véritable appui. Un glissement ou un geste annulé ne ferme rien.
func _input(event: InputEvent) -> void:
	if not _outside_tap_released(event):
		return
	if is_instance_valid(_action_drawer) \
			and not _event_hits_control(event, _action_drawer) \
			and not _event_hits_control(event, _action_card):
		_close_action_drawer()
	if sort_menu.visible \
			and not _event_hits_control(event, sort_menu) \
			and not _event_hits_control(event, sort_button):
		_close_inline_menus()
	elif level_menu.visible \
			and not _event_hits_control(event, level_menu) \
			and not _event_hits_control(event, level_button):
		_close_inline_menus()
	elif god_menu.visible \
			and not _event_hits_control(event, god_menu) \
			and not _event_hits_control(event, god_button):
		_close_inline_menus()


func _outside_tap_released(event: InputEvent) -> bool:
	var pointer := -1
	var card_position := Vector2.ZERO
	var pressed := false
	var released := false
	var canceled := false
	if event is InputEventScreenTouch:
		pointer = event.index
		card_position = event.position
		pressed = event.pressed
		released = not event.pressed
		canceled = event.canceled
	elif event is InputEventScreenDrag:
		pointer = event.index
		card_position = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer = -2
		card_position = event.position
		pressed = event.pressed
		released = not event.pressed
		canceled = event.canceled
	elif event is InputEventMouseMotion and _outside_pointer == -2:
		pointer = -2
		card_position = event.position
	else:
		return false
	if pressed:
		if _outside_pointer == -1:
			_outside_pointer = pointer
			_outside_origin = card_position
			_outside_canceled = false
		return false
	if pointer != _outside_pointer:
		return false
	if card_position.distance_to(_outside_origin) > UITheme.TOUCH_SLOP:
		_outside_canceled = true
	if not released:
		return false
	var tapped := not canceled and not _outside_canceled
	_outside_pointer = -1
	_outside_canceled = false
	return tapped


func _event_hits_control(event: InputEvent, control: Control) -> bool:
	if not is_instance_valid(control) or not control.is_visible_in_tree():
		return false
	var local_event := control.make_input_local(event)
	return Rect2(Vector2.ZERO, control.size).has_point(local_event.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _go_back() -> void:
	if confirm_popup.is_open():
		confirm_popup.dismiss()
		return
	if pending_rewards_vault.visible:
		pending_rewards_vault.close()
		return
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
	Routes.go(get_tree(), Routes.MAIN_MENU)


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
	_refresh_pending_rewards()
	var cost := DeckRules.deck_cost(_current_deck)
	deck_count_label.text = "%d/%d  •  %s/%d pts" % [
		_current_deck.size(), DeckRules.DECK_SIZE, UIFormat.cost(cost), DeckRules.DECK_BUDGET
	]
	deck_count_label.add_theme_color_override(
		"font_color",
		UITheme.COL_SUCCESS if DeckRules.is_deck_valid(_current_deck, PlayerData.player_god_id) else UITheme.COL_WARNING
	)
	clear_deck_button.disabled = _current_deck.is_empty()
	if preserve_scroll:
		_restore_scroll_deferred(previous_scroll)
	_register_story_anchors()


func _open_pending_rewards() -> void:
	_close_card_panels()
	_close_inline_menus()
	pending_rewards_vault.open()


func _open_shop_from_vault() -> void:
	Routes.go(get_tree(), Routes.SHOP)


func _refresh_pending_rewards() -> void:
	var count := PlayerData.pending_card_reward_count()
	pending_rewards_badge.visible = count > 0
	pending_rewards_badge.text = str(count)
	pending_rewards_button.tooltip_text = "%d récompense%s en attente" % [
		count, "s" if count != 1 else ""] if count > 0 else "Aucune récompense en attente"
	if pending_rewards_vault.visible:
		pending_rewards_vault.rebuild()


func _on_inventory_changed() -> void:
	_refresh_pending_rewards()


func _refresh_god_panel() -> void:
	var god := GodIdentityModel.player(PlayerData.player_god_id)
	background.set_god(god)
	_god_selector.refresh(PlayerData.player_god_id)
	_deck_slot_selector.refresh(PlayerData.get_selected_deck())


func _refresh_deck() -> void:
	_deck_panel.refresh(_current_deck)


## Action destructive : elle ne modifie rien avant le OUI et ne concerne que
## l'emplacement affiché. Un deck déjà vide ne propose pas de confirmation.
func _request_clear_deck() -> void:
	if _current_deck.is_empty():
		return
	_close_card_panels()
	_close_inline_menus()
	confirm_popup.open(CLEAR_DECK_CONFIRMATION)


func _clear_deck() -> void:
	_commit_operation(DeckRules.try_clear(_current_deck))


func _populate_collection() -> void:
	_close_action_drawer()
	_collection_grid.rebuild(PlayerData.player_god_id, _current_deck, _sort_mode)
	_register_story_anchors()


func _register_story_anchors() -> void:
	StoryService.register_anchor("collection.deck_panel", $Content/Scroll/Page/DeckPanel)
	for row in deck_rows.get_children():
		for wrapper in row.get_children():
			if wrapper.get_child_count() == 0:
				continue
			var card := wrapper.get_child(0) as StoneCard
			if card != null:
				StoryService.register_anchor("collection.deck.%s" % card.get_stone_id(), wrapper)
	if _collection_grid != null:
		_collection_grid.register_story_anchors()


## Une cible de spotlight peut être plus bas que la zone visible (la nouvelle
## carte, par exemple). On la fait apparaître avant que le trou ne soit dessiné.
func _on_story_spotlight_requested(target: Control, _prompt: String, _show_advance: bool) -> void:
	if is_instance_valid(target) and scroll.is_ancestor_of(target):
		scroll.ensure_control_visible(target)


func _open_card_actions(stone_id: String, wrapper: VBoxContainer, source: int) -> void:
	_suppress_scroll_tap_once()
	if not StoneLoader.has_stone(stone_id):
		return
	if not PlayerData.owns_stone(stone_id):
		_show_error("Cette carte ou ce niveau n'est pas encore débloqué.")
		return
	Audio.play_sfx(AudioCatalog.SFX_BUTTON)
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
	_action_wrapper = wrapper
	_action_card = wrapper.get_child(0) as StoneCard
	if _action_card != null:
		_action_card.set_selected(true)
	_action_drawer = ACTION_DRAWER_SCENE.instantiate() as CardActionDrawer
	action_drawer_layer.add_child(_action_drawer)
	_action_drawer.setup(stone_id, source)
	_action_drawer.info_requested.connect(_on_info_requested)
	_action_drawer.primary_requested.connect(_on_primary_requested)
	_action_drawer.upgrade_requested.connect(_open_upgrade_preview)
	_action_drawer.visible = false
	StoryService.register_anchor("collection.action.primary", _action_drawer.primary_button)
	StoryService.register_anchor("collection.action.info", _action_drawer.info_button)
	StoryService.notify_event("collection_card_opened", {"stone_id": stone_id, "source": int(source)})
	_position_action_drawer_deferred()


func _position_action_drawer_deferred() -> void:
	await get_tree().process_frame
	if not _has_action_drawer_target():
		return
	var drawer_height := _action_drawer.get_combined_minimum_size().y
	_adjusting_drawer_scroll = true
	bottom_spacer.custom_minimum_size.y = maxf(BOTTOM_SPACER_DEFAULT,
		drawer_height + ACTION_DRAWER_GAP + ACTION_DRAWER_MARGIN)
	await get_tree().process_frame
	if not _has_action_drawer_target():
		_adjusting_drawer_scroll = false
		return
	var placement := _action_drawer_placement()
	var visible_rect := ActionPlacement.control_rect_in(action_drawer_layer, scroll)
	var overflow := float(placement.get("bottom", 0.0)) \
		+ ACTION_DRAWER_GAP + drawer_height \
		- (visible_rect.end.y - ACTION_DRAWER_MARGIN)
	if overflow > 0.0:
		scroll.scroll_vertical += ceili(overflow)
		await get_tree().process_frame
	_adjusting_drawer_scroll = false
	if not is_instance_valid(_action_drawer):
		return
	_position_action_drawer()
	_action_drawer.visible = true


## Le tiroir vit dans une couche superposée : il ne participe jamais au calcul
## des colonnes et ne peut donc modifier ni la carte ni la grille.
func _position_action_drawer() -> void:
	if not _has_action_drawer_target():
		return
	var placement := _action_drawer_placement()
	if placement.is_empty():
		return
	var minimum := _action_drawer.get_combined_minimum_size()
	var drawer_size := Vector2(maxf(1.0, float(placement["width"])), minimum.y)
	_action_drawer.custom_minimum_size = drawer_size
	_action_drawer.size = drawer_size
	_action_drawer.position = Vector2(float(placement["x"]),
		float(placement["bottom"]) + ACTION_DRAWER_GAP)


func _has_action_drawer_target() -> bool:
	return is_instance_valid(_action_drawer) and is_instance_valid(_action_wrapper) \
		and is_instance_valid(_action_card)


func _action_drawer_placement() -> Dictionary:
	if not _has_action_drawer_target():
		return {}
	return ActionPlacement.resolve(action_drawer_layer, _action_wrapper, _action_card,
		_action_source == CardActionDrawer.Source.COLLECTION)


func _on_scroll_value_changed(_value: float) -> void:
	# Une superposition ne doit jamais poursuivre sa carte pendant le scroll.
	# Le prochain appui la rouvrira à la bonne position.
	if not _adjusting_drawer_scroll:
		_close_action_drawer()


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
	_action_wrapper = null
	_action_stone_id = ""
	_action_source = -1
	bottom_spacer.custom_minimum_size.y = BOTTOM_SPACER_DEFAULT


func _on_info_requested(stone_id: String) -> void:
	_close_action_drawer()
	info_sheet.open_for(stone_id, _current_deck)


## Le tiroir conduit vers l'aperçu grisé du prochain niveau. La transaction
## reste exclusivement déclenchée depuis la fiche détaillée.
func _open_upgrade_preview(lineage_id: String) -> void:
	var unlocked_level := int(PlayerData.card_entry(lineage_id).get("unlocked_level", 0))
	var next_id := StoneLoader.variant_id(lineage_id, unlocked_level + 1)
	if next_id == "":
		_show_error("Cette carte est déjà au niveau maximal.")
		return
	_close_action_drawer()
	info_sheet.open_for(next_id, _current_deck)


func _on_primary_requested(stone_id: String, source: CardActionDrawer.Source) -> void:
	if source == CardActionDrawer.Source.DECK:
		_commit_operation(DeckRules.try_remove(_current_deck, stone_id))
		return
	_request_use(stone_id)


func _request_use(stone_id: String) -> void:
	if not PlayerData.owns_stone(stone_id):
		_show_error("Cette carte ou ce niveau n'est pas encore débloqué.")
		return
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
			_register_replacement_anchor(stone_id)
			StoryService.notify_event("replacement_opened", {"stone_id": stone_id})
		DeckRules.REASON_BUDGET:
			_show_error("Budget dépassé : %s/%d points." % [
				UIFormat.cost(operation["cost"]), DeckRules.DECK_BUDGET
			])


func _on_replacement_requested(old_id: String) -> void:
	var incoming_id := _replacement_stone_id
	var operation := DeckRules.try_replace(_current_deck, old_id, incoming_id, PlayerData.player_god_id)
	if not operation["success"]:
		if operation["reason"] == DeckRules.REASON_BUDGET:
			replacement_panel.show_budget_error(operation["cost"])
		return
	if _commit_operation(operation):
		replacement_panel.close_panel()
		_replacement_stone_id = ""
		StoryService.notify_event("deck_card_replaced", {
			"old_id": old_id, "new_id": incoming_id,
		})


## Le panneau de remplacement choisit la première carte du deck compatible
## avec le budget. Le scénario n'a pas à connaître son identifiant : il vise
## l'alias stable `collection.replace.first`.
func _register_replacement_anchor(incoming_id: String) -> void:
	var target_id := ""
	for old_id in _current_deck:
		if DeckRules.can_replace(_current_deck, str(old_id), incoming_id, PlayerData.player_god_id):
			target_id = str(old_id)
			break
	if target_id == "" and not _current_deck.is_empty():
		target_id = str(_current_deck[0])
	if target_id == "":
		return
	var wrapper: Control = replacement_panel.wrapper_for(target_id)
	if wrapper != null:
		StoryService.register_anchor("collection.replace.first", wrapper)


func _commit_operation(operation: Dictionary) -> bool:
	if not operation.get("success", false):
		return false
	var new_deck: Array = operation["deck"]
	if not PlayerData.set_player_deck(new_deck):
		_show_error("Impossible de modifier ce deck : la sauvegarde a échoué.")
		return false
	_current_deck = new_deck.duplicate()
	_prepare_card_art()
	_clear_status()
	_refresh_all()
	return true


func _prepare_card_art() -> void:
	CardArtCache.activate_god(PlayerData.player_god_id, _preview_level, _current_deck)


func _upgrade_card(lineage_id: String) -> void:
	var result := EconomyServiceModel.new().upgrade_card(lineage_id)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("reason", "Amélioration impossible.")))
		return
	_close_action_drawer()
	_clear_status()
	_populate_collection()
	_refresh_deck()
	info_sheet.refresh_inventory_state()


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
