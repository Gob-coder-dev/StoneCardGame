## Tiroir d'actions superposé près d'une carte, hors des conteneurs de layout.
class_name CardActionDrawer
extends PanelContainer

signal info_requested(stone_id: String)
signal primary_requested(stone_id: String, source: Source)
signal upgrade_requested(lineage_id: String)

enum Source { DECK, COLLECTION }

const STANDARD_BUTTON_HEIGHT := 76.0
const STANDARD_UPGRADE_HEIGHT := 108.0
const DECK_BUTTON_HEIGHT := 60.0
const DECK_UPGRADE_HEIGHT := 86.0

@onready var info_button: Button = $Actions/InfoButton
@onready var primary_button: Button = $Actions/PrimaryButton
@onready var upgrade_button: UpgradePriceButton = $Actions/UpgradeButton

var _stone_id: String = ""
var _source: Source = Source.COLLECTION


func _ready() -> void:
	Audio.set_button_sfx(primary_button, AudioCatalog.SFX_BUTTON_2)
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
	_apply_density()
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


## La collection conserve ses dimensions historiques. Seul le deck, dont les
## cartes sont plus petites, emploie une variante compacte du même composant.
func _apply_density() -> void:
	var compact := _source == Source.DECK
	var action_height := DECK_BUTTON_HEIGHT if compact else STANDARD_BUTTON_HEIGHT
	info_button.custom_minimum_size = Vector2(0.0, action_height)
	primary_button.custom_minimum_size = Vector2(0.0, action_height)
	info_button.add_theme_font_size_override("font_size", 22 if compact else 28)
	primary_button.add_theme_font_size_override("font_size", 22 if compact else 27)
	upgrade_button.custom_minimum_size = Vector2(0.0,
		DECK_UPGRADE_HEIGHT if compact else STANDARD_UPGRADE_HEIGHT)
	upgrade_button.title_font_size = 19 if compact else 23
	upgrade_button.price_font_size = 20 if compact else 24
	upgrade_button.soul_icon_size = 28.0 if compact else 34.0
	upgrade_button.set_compact_layout(compact)


func _on_info_pressed() -> void:
	info_requested.emit(_stone_id)


func _on_primary_pressed() -> void:
	primary_requested.emit(_stone_id, _source)


func _on_upgrade_pressed() -> void:
	upgrade_requested.emit(StoneLoader.stone_lineage(_stone_id))
