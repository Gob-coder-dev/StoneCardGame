## Sélection immédiate de la pierre du deck à remplacer.
class_name ReplacementPanel
extends Control

signal replacement_requested(old_id: String)

@onready var deck_grid: GridContainer = $Panel/Content/DeckGrid
@onready var candidate: CenterContainer = $Panel/Content/Candidate
@onready var status_label: Label = $Panel/Content/Status
@onready var cancel_button: Button = $Panel/Content/CancelButton

var _deck: Array = []
var _incoming_id: String = ""


func _ready() -> void:
	cancel_button.pressed.connect(close_panel)
	deck_grid.columns = UITheme.DECK_COLUMNS
	visible = false


func open_for(deck: Array, incoming_id: String) -> void:
	_deck = deck.duplicate()
	_incoming_id = incoming_id
	_rebuild()
	visible = true


func close_panel() -> void:
	visible = false
	_deck.clear()
	_incoming_id = ""


func show_budget_error(cost: float) -> void:
	status_label.text = "Ce remplacement dépasse le budget : %s/%d points." % [
		UIFormat.cost(cost), DeckRules.DECK_BUDGET
	]
	status_label.add_theme_color_override("font_color", UITheme.COL_ERROR)


func _rebuild() -> void:
	_clear_children(deck_grid)
	_clear_children(candidate)
	var current_cost := DeckRules.deck_cost(_deck)
	var incoming_cost := StoneLoader.stone_cost(_incoming_id)

	for old_id in _deck:
		var wrapper := VBoxContainer.new()
		wrapper.custom_minimum_size = Vector2(UITheme.CARD_REPLACEMENT + 8.0, UITheme.CARD_REPLACEMENT + 70.0)
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrapper.add_theme_constant_override("separation", 6)
		var card := _make_card(StoneLoader.get_stone(old_id), StoneCard.OWNER_HUMAN, UITheme.CARD_REPLACEMENT)
		card.card_pressed.connect(_on_target_pressed)
		var new_cost := DeckRules.replacement_cost(_deck, old_id, _incoming_id)
		var valid := DeckRules.can_replace(_deck, old_id, _incoming_id, PlayerData.player_god_id)
		if not valid:
			card.modulate = Color(0.55, 0.55, 0.55)
		var formula := Label.new()
		formula.text = "%s − %s + %s = %s/%d" % [
			UIFormat.cost(current_cost), UIFormat.cost(StoneLoader.stone_cost(old_id)),
			UIFormat.cost(incoming_cost), UIFormat.cost(new_cost), DeckRules.DECK_BUDGET
		]
		formula.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Quatre colonnes étroites : le calcul passe à la ligne au besoin.
		formula.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		formula.add_theme_font_size_override("font_size", 22)
		formula.add_theme_color_override("font_color", UITheme.COL_SUCCESS if valid else UITheme.COL_ERROR)
		wrapper.add_child(card)
		wrapper.add_child(formula)
		deck_grid.add_child(wrapper)

	var incoming_card := _make_card(StoneLoader.get_stone(_incoming_id), StoneCard.OWNER_NONE, 290.0)
	incoming_card.custom_minimum_size.x = 290
	incoming_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	candidate.add_child(incoming_card)
	status_label.text = "Choisis une pierre du deck à remplacer."
	status_label.add_theme_color_override("font_color", UITheme.COL_WARNING)


func _make_card(stone: Dictionary, owner: int, height: float) -> StoneCard:
	var card := StoneCard.new()
	card.custom_minimum_size = Vector2(0, height)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.setup(stone, owner)
	card.set_show_cost(true)
	return card


func _on_target_pressed(old_id: String) -> void:
	var operation := DeckRules.try_replace(_deck, old_id, _incoming_id, PlayerData.player_god_id)
	if not operation["success"]:
		if operation["reason"] == DeckRules.REASON_BUDGET:
			show_budget_error(operation["cost"])
		return
	replacement_requested.emit(old_id)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
