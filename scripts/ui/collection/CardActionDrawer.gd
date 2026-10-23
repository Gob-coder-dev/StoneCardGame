## Tiroir d'actions affiché directement sous une carte de la collection.
class_name CardActionDrawer
extends PanelContainer

signal info_requested(stone_id: String)
signal primary_requested(stone_id: String, source: Source)

enum Source { DECK, COLLECTION }

@onready var info_button: Button = $Actions/InfoButton
@onready var primary_button: Button = $Actions/PrimaryButton

var _stone_id: String = ""
var _source: Source = Source.COLLECTION
var _is_in_deck: bool = false


func _ready() -> void:
	info_button.pressed.connect(_on_info_pressed)
	primary_button.pressed.connect(_on_primary_pressed)
	_refresh()


func setup(stone_id: String, source: Source, is_in_deck: bool) -> void:
	_stone_id = stone_id
	_source = source
	_is_in_deck = is_in_deck
	if is_node_ready():
		_refresh()


func _refresh() -> void:
	if _source == Source.DECK:
		primary_button.text = "RETIRER"
		primary_button.disabled = false
	elif _is_in_deck:
		primary_button.text = "DANS LE DECK"
		primary_button.disabled = true
	else:
		primary_button.text = "UTILISER"
		primary_button.disabled = false


func _on_info_pressed() -> void:
	info_requested.emit(_stone_id)


func _on_primary_pressed() -> void:
	primary_requested.emit(_stone_id, _source)
