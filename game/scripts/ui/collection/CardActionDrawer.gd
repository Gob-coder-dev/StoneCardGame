## Tiroir d'actions superposé près d'une carte, hors des conteneurs de layout.
class_name CardActionDrawer
extends PanelContainer

signal info_requested(stone_id: String)
signal primary_requested(stone_id: String, source: Source)
signal upgrade_requested(lineage_id: String)

enum Source { DECK, COLLECTION }

@onready var info_button: Button = $Actions/InfoButton
@onready var primary_button: Button = $Actions/PrimaryButton
@onready var upgrade_button: UpgradePriceButton = $Actions/UpgradeButton

var _stone_id: String = ""
var _source: Source = Source.COLLECTION


func _ready() -> void:
	info_button.pressed.connect(_on_info_pressed)
	primary_button.pressed.connect(_on_primary_pressed)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	_refresh()


## Une carte de la collection n'est jamais dans le deck : elle peut toujours être utilisée.
func setup(stone_id: String, source: Source) -> void:
	_stone_id = stone_id
	_source = source
	if is_node_ready():
		_refresh()


func _refresh() -> void:
	primary_button.text = "RETIRER" if _source == Source.DECK else "UTILISER"
	primary_button.theme_type_variation = &"DangerButton" if _source == Source.DECK else &"PrimaryButton"
	var lineage_id := StoneLoader.stone_lineage(_stone_id)
	var upgrade := PlayerData.card_upgrade_state(lineage_id)
	var requirement: Dictionary = upgrade.get("requirement", {})
	upgrade_button.visible = not requirement.is_empty()
	if upgrade_button.visible:
		upgrade_button.disabled = not bool(upgrade.get("can_upgrade", false))
		upgrade_button.set_content("AMÉLIORER", true,
			int(requirement.get("souls", 0)), UITheme.COL_WARNING)


func _on_info_pressed() -> void:
	info_requested.emit(_stone_id)


func _on_primary_pressed() -> void:
	primary_requested.emit(_stone_id, _source)


func _on_upgrade_pressed() -> void:
	upgrade_requested.emit(StoneLoader.stone_lineage(_stone_id))
