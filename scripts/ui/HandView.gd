## HandView.gd
## Vue de la main du joueur humain : affiche les cartes, gère la surbrillance
## de sélection. Aucune logique de jeu — émet juste quelle carte a été touchée.
class_name HandView
extends GridContainer

## Émis quand le joueur touche une carte de sa main.
signal card_selected(stone_id: String)

var _cards: Array = []            ## StoneCard affichées
var _selected_id: String = ""


func _ready() -> void:
	columns = 3
	add_theme_constant_override("h_separation", UITheme.GAP_MEDIUM)
	add_theme_constant_override("v_separation", UITheme.GAP_MEDIUM)


## Reconstruit la main depuis la liste de stone_id.
func refresh(stone_ids: Array) -> void:
	for child in get_children():
		child.queue_free()
	_cards.clear()

	for stone_id in stone_ids:
		var wrapper := AspectRatioContainer.new()
		wrapper.ratio = 1.0  ## carré : les cartes sont 1:1
		wrapper.stretch_mode = AspectRatioContainer.STRETCH_FIT
		wrapper.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
		wrapper.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
		wrapper.custom_minimum_size = Vector2(0, 250)
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var card := StoneCard.new()
		card.setup(StoneLoader.get_stone(stone_id), StoneCard.OWNER_HUMAN)
		card.card_pressed.connect(_on_card_pressed)
		wrapper.add_child(card)

		add_child(wrapper)
		_cards.append(card)

	_apply_selection()


func _on_card_pressed(stone_id: String) -> void:
	emit_signal("card_selected", stone_id)


func set_selected(stone_id: String) -> void:
	_selected_id = stone_id
	_apply_selection()


func clear_selection() -> void:
	_selected_id = ""
	_apply_selection()


func _apply_selection() -> void:
	for card in _cards:
		card.set_selected(card.get_stone_id() == _selected_id and _selected_id != "")
