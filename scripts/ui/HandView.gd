## HandView.gd
## Vue de la main du joueur humain : affiche les cartes, gère la surbrillance
## de sélection. Aucune logique de jeu — émet juste quelle carte a été touchée.
class_name HandView
extends GridContainer

## Émis quand le joueur touche une carte de sa main.
signal card_selected(stone_id: String)
## Émis dès qu'un doigt ou la souris appuie sur une carte : l'appui peut devenir
## un glissement vers le plateau (voir CardDragController).
signal card_press_started(stone_id: String, card: StoneCard, pointer: int, canvas_position: Vector2)

const DragGesture := preload("res://scripts/ui/input/DragGesture.gd")

## La main complète tient sur deux rangées (4 colonnes pour un deck de 8).
const ROWS := 2
## Côté d'une carte de la main, en pixels du canevas 1080 de large.
const CARD_SIZE := 220

var _cards: Array[StoneCard] = []  ## cartes affichées, dans l'ordre de la main
var _selected_id: String = ""


func _ready() -> void:
	columns = ceili(float(DeckRules.DECK_SIZE) / ROWS)
	add_theme_constant_override("h_separation", UITheme.GAP_MEDIUM)
	add_theme_constant_override("v_separation", UITheme.GAP_MEDIUM)
	# La hauteur suit la taille du deck : le plateau garde tout le reste de l'écran.
	custom_minimum_size.y = ROWS * CARD_SIZE + (ROWS - 1) * UITheme.GAP_MEDIUM


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
		wrapper.custom_minimum_size = Vector2(0, CARD_SIZE)
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var card := StoneCard.new()
		card.setup(StoneLoader.get_stone(str(stone_id)), StoneCard.OWNER_HUMAN)
		card.card_pressed.connect(_on_card_pressed)
		card.gui_input.connect(_on_card_input.bind(card))
		wrapper.add_child(card)

		add_child(wrapper)
		_cards.append(card)
	_apply_selection()


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
