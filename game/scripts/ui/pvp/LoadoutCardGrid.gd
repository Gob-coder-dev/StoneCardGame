## LoadoutCardGrid.gd
## Grille de cartes illustrées réutilisable par les préparations campagne/PVP.
##
## Elle ne contient aucune règle de draft ni de série : elle reçoit des
## `stone_id`, réutilise ses `StoneCard` et laisse le contrôleur décider si les
## cartes sont sélectionnables. Les cartes non sélectionnables ignorent les
## gestes pour laisser le défilement au ScrollContainer parent.
class_name LoadoutCardGrid
extends GridContainer

signal card_chosen(stone_id: String)

var _cards: Array[StoneCard] = []
var _selectable := false
var _selected_id := ""
var _desired_card_size := UITheme.CARD_HAND
var _max_card_size := UITheme.CARD_HAND
var _card_size := UITheme.CARD_HAND


func _ready() -> void:
	add_theme_constant_override("h_separation", UITheme.GAP_MEDIUM)
	add_theme_constant_override("v_separation", UITheme.GAP_MEDIUM)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not resized.is_connected(_relayout):
		resized.connect(_relayout)


func show_cards(stone_ids: Array, card_size: int, columns_count: int,
		selectable: bool, selected_id: String = "", max_card_size: int = -1) -> void:
	columns = columns_count
	_desired_card_size = card_size
	_max_card_size = max_card_size if max_card_size > 0 else card_size
	_card_size = card_size
	_selectable = selectable
	_selected_id = selected_id
	_resize_pool(stone_ids.size(), card_size)
	for index in range(stone_ids.size()):
		var raw_id: Variant = stone_ids[index]
		var stone_id := str(raw_id)
		var card := _cards[index]
		if card.get_stone_id() != stone_id:
			card.setup(StoneLoader.get_stone(stone_id), StoneCard.OWNER_NONE)
		var wrapper := card.get_parent() as AspectRatioContainer
		wrapper.custom_minimum_size = Vector2(0, card_size)
		wrapper.mouse_filter = Control.MOUSE_FILTER_PASS if selectable else Control.MOUSE_FILTER_IGNORE
		card.custom_minimum_size = Vector2(0, card_size)
		card.mouse_filter = Control.MOUSE_FILTER_PASS if selectable else Control.MOUSE_FILTER_IGNORE
	_apply_selection()
	_relayout.call_deferred()


func _resize_pool(target: int, card_size: int) -> void:
	while _cards.size() > target:
		var card := _cards.pop_back() as StoneCard
		var wrapper := card.get_parent()
		if wrapper != null:
			remove_child(wrapper)
			wrapper.queue_free()
	while _cards.size() < target:
		var wrapper := AspectRatioContainer.new()
		wrapper.ratio = 1.0
		wrapper.stretch_mode = AspectRatioContainer.STRETCH_FIT
		wrapper.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
		wrapper.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
		# Aucune largeur minimale : la grille peut rétrécir avant son relayout.
		wrapper.custom_minimum_size = Vector2(0, card_size)
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card := StoneCard.new()
		card.card_pressed.connect(_on_card_pressed)
		wrapper.add_child(card)
		add_child(wrapper)
		_cards.append(card)


## Taille calculée depuis la largeur réellement offerte par le parent : les
## cartes remplissent la largeur disponible, réduisent si nécessaire pour
## éviter tout défilement horizontal, et s'arrêtent au plafond fourni par le
## contrôleur. Sans plafond explicite, `card_size` reste la borne historique.
func _relayout() -> void:
	if columns <= 0 or _cards.is_empty():
		return
	var available := size.x
	if available <= 0.0:
		return
	var separation := float(get_theme_constant("h_separation")) * float(maxi(0, columns - 1))
	var computed := floorf((available - separation) / float(columns))
	if computed <= 0.0:
		return
	var cap := float(_max_card_size if _max_card_size > 0 else _desired_card_size)
	_card_size = int(minf(computed, cap))
	for card in _cards:
		card.custom_minimum_size = Vector2(0, _card_size)
		var wrapper := card.get_parent() as Control
		if wrapper != null:
			wrapper.custom_minimum_size = Vector2(0, _card_size)


func lock(selected_id: String) -> void:
	_selectable = false
	_selected_id = selected_id
	for card in _cards:
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wrapper := card.get_parent() as Control
		if wrapper != null:
			wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_selection()


func selected_id() -> String:
	return _selected_id


func _on_card_pressed(stone_id: String) -> void:
	if not _selectable or _selected_id != "":
		return
	if not _cards.any(func(card: StoneCard) -> bool: return card.get_stone_id() == stone_id):
		return
	Audio.play_sfx(AudioCatalog.SFX_BUTTON)
	_selectable = false
	_selected_id = stone_id
	for card in _cards:
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wrapper := card.get_parent() as Control
		if wrapper != null:
			wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_selection()
	card_chosen.emit(stone_id)


func _apply_selection() -> void:
	for card in _cards:
		card.set_selected(_selected_id != "" and card.get_stone_id() == _selected_id)
