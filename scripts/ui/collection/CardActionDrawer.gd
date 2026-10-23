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


func _ready() -> void:
	info_button.pressed.connect(_on_info_pressed)
	primary_button.pressed.connect(_on_primary_pressed)
	_refresh()


## Une carte de la collection n'est jamais dans le deck : elle peut toujours être utilisée.
func setup(stone_id: String, source: Source) -> void:
	_stone_id = stone_id
	_source = source
	if is_node_ready():
		_refresh()


func _refresh() -> void:
	primary_button.text = "RETIRER" if _source == Source.DECK else "UTILISER"


func _on_info_pressed() -> void:
	info_requested.emit(_stone_id)


func _on_primary_pressed() -> void:
	primary_requested.emit(_stone_id, _source)
