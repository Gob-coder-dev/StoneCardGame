## HandView.gd
## Vue de la main du joueur humain : affiche les cartes, gère la surbrillance
## de sélection. Aucune logique de jeu — émet juste quelle carte a été touchée.
class_name HandView
extends Container

## Émis quand le joueur touche une carte de sa main.
signal card_selected(stone_id: String)
## Émis dès qu'un doigt ou la souris appuie sur une carte : l'appui peut devenir
## un glissement vers le plateau (voir CardDragController).
signal card_press_started(stone_id: String, card: StoneCard, pointer: int, canvas_position: Vector2)

const DragGesture := preload("res://scripts/ui/input/DragGesture.gd")

var _cards: Array[StoneCard] = []  ## cartes affichées, dans l'ordre de la main
var _selected_id: String = ""
var columns: int = UITheme.DECK_COLUMNS
var _card_size: float = UITheme.CARD_HAND


func _ready() -> void:
	configure(UITheme.DECK_COLUMNS, UITheme.CARD_HAND)


## La disposition est calculée par l'écran de combat avec la hauteur réelle
## disponible. La hauteur reste celle du deck complet afin qu'un coup joué ne
## fasse jamais bouger le plateau.
func configure(columns_count: int, card_size: float) -> void:
	columns = maxi(1, columns_count)
	_card_size = maxf(1.0, card_size)
	var rows := ceili(float(DeckRules.DECK_SIZE) / float(columns))
	custom_minimum_size.y = rows * _card_size \
		+ float(maxi(0, rows - 1)) * UITheme.GAP_MEDIUM
	for card in _cards:
		var wrapper := card.get_parent() as Control
		if wrapper != null:
			wrapper.custom_minimum_size = Vector2(_card_size, _card_size)
		card.custom_minimum_size = Vector2(_card_size, _card_size)
	queue_sort()


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var child_count := get_child_count()
	if child_count == 0:
		return
	var rows := ceili(float(child_count) / float(columns))
	for row in range(rows):
		var first := row * columns
		var count := mini(columns, child_count - first)
		var row_width := float(count) * _card_size \
			+ float(maxi(0, count - 1)) * UITheme.GAP_MEDIUM
		var start_x := maxf(0.0, (size.x - row_width) * 0.5)
		for column in range(count):
			var child := get_child(first + column) as Control
			if child == null:
				continue
			var position := Vector2(
				start_x + float(column) * (_card_size + UITheme.GAP_MEDIUM),
				float(row) * (_card_size + UITheme.GAP_MEDIUM))
			fit_child_in_rect(child, Rect2(position, Vector2.ONE * _card_size))


## Synchronise la main avec la liste de stone_id du moteur. Pendant un match,
## la main ne fait que perdre des cartes : seules les cartes jouées sont
## retirées. Une liste qui n'en découle pas reconstruit la main.
func refresh(stone_ids: Array) -> void:
	var played: Array[StoneCard] = []
	var next := 0
	for card in _cards:
		if next < stone_ids.size() and card.get_stone_id() == str(stone_ids[next]):
			next += 1
		else:
			played.append(card)
	if next < stone_ids.size():
		_rebuild(stone_ids)
		return
	for card in played:
		_cards.erase(card)
		var wrapper := card.get_parent()
		remove_child(wrapper)
		wrapper.queue_free()
	_apply_selection()


func _rebuild(stone_ids: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cards.clear()
	for stone_id in stone_ids:
		var wrapper := AspectRatioContainer.new()
		wrapper.ratio = 1.0  ## carré : les cartes sont 1:1
		wrapper.stretch_mode = AspectRatioContainer.STRETCH_FIT
		wrapper.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
		wrapper.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
		wrapper.custom_minimum_size = Vector2(_card_size, _card_size)

		var card := StoneCard.new()
		card.setup(StoneLoader.get_stone(str(stone_id)), StoneCard.OWNER_HUMAN)
		card.custom_minimum_size = Vector2(_card_size, _card_size)
		card.card_pressed.connect(_on_card_pressed)
		card.gui_input.connect(_on_card_input.bind(card))
		wrapper.add_child(card)

		add_child(wrapper)
		_cards.append(card)
	_apply_selection()
	queue_sort()


func _on_card_pressed(stone_id: String) -> void:
	emit_signal("card_selected", stone_id)


## Un appui peut devenir un glissement : la position est donnée dans le canevas.
func _on_card_input(event: InputEvent, card: StoneCard) -> void:
	var pointer := DragGesture.pressed_pointer(event)
	if pointer != DragGesture.NO_POINTER:
		card_press_started.emit(card.get_stone_id(), card, pointer,
			card.get_global_transform_with_canvas() * event.position)


func set_selected(stone_id: String) -> void:
	_selected_id = stone_id
	_apply_selection()


func clear_selection() -> void:
	_selected_id = ""
	_apply_selection()


func _apply_selection() -> void:
	for card in _cards:
		card.set_selected(card.get_stone_id() == _selected_id and _selected_id != "")
