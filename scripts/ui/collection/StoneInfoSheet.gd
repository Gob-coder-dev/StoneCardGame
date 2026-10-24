## Fiche détaillée d'une pierre, indépendante de l'écran de collection.
class_name StoneInfoSheet
extends Control
signal use_requested(stone_id: String)
const NumberedSelector := preload("res://scripts/ui/collection/NumberedSelector.gd")

@onready var title_label: Label = $InfoPanel/InfoContent/Header/Title
@onready var summary_label: Label = $InfoPanel/InfoContent/Scroll/Page/Summary
@onready var description_label: Label = $InfoPanel/InfoContent/Scroll/Page/Description
@onready var power_label: Label = $InfoPanel/InfoContent/Scroll/Page/Power
@onready var stats_label: Label = $InfoPanel/InfoContent/Scroll/Page/Stats
@onready var card_container: CenterContainer = $InfoPanel/InfoContent/Scroll/Page/Card
@onready var close_button: Button = $InfoPanel/InfoContent/Header/CloseButton
@onready var use_button: Button = $InfoPanel/InfoContent/UseButton
@onready var error_label: Label = $InfoPanel/InfoContent/Error

const Gesture := preload("res://scripts/ui/input/TapGesture.gd")
var _backdrop_tap := Gesture.new()
var _selector: NumberedSelector
var _card: StoneCard
var _lineage := ""
var _shown_variant := ""
var _deck: Array = []


func _ready() -> void:
	close_button.pressed.connect(close_sheet)
	$Backdrop.gui_input.connect(_on_backdrop_input)
	use_button.pressed.connect(func():
		if _shown_variant != "":
			use_requested.emit(_shown_variant))
	_card = StoneCard.new()
	_card.custom_minimum_size = Vector2(UITheme.CARD_INFO, UITheme.CARD_INFO)
	_card.set_show_cost(true)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_container.add_child(_card)
	visible = false


func open_for(stone_id: String, deck: Array = []) -> void:
	if not StoneLoader.has_stone(stone_id):
		return
	_lineage = StoneLoader.stone_lineage(stone_id)
	_deck = deck.duplicate()
	var row: HBoxContainer = $InfoPanel/InfoContent/Levels
	for button in row.get_children():
		row.remove_child(button)
		button.queue_free()
	_selector = NumberedSelector.new(row, StoneLoader.lineage_max_level(_lineage))
	_selector.value_selected.connect(_select_level)
	_refresh_form(stone_id)
	$InfoPanel/InfoContent/Scroll.scroll_vertical = 0
	visible = true


func _select_level(level: int) -> void:
	var id := StoneLoader.variant_id(_lineage, level)
	if id != "":
		_refresh_form(id)


func _refresh_form(stone_id: String) -> void:
	_shown_variant = stone_id
	var stone := StoneLoader.get_stone(stone_id)
	var level := StoneLoader.stone_level(stone_id)
	_selector.refresh(level)
	use_button.disabled = _deck.has(stone_id)
	error_label.visible = false
	title_label.text = stone.get("name", stone_id)
	var god := StoneLoader.get_god(str(stone.get("god_id", "neutral")))
	var family := "Neutre" if god.is_empty() else str(god.get("family_name", ""))
	summary_label.text = "%s • %s • Niv. %d • %s points" % [
		_rarity_label(stone.get("rarity", "")), family, level,
		UIFormat.cost(StoneLoader.stone_cost(stone_id))
	]
	description_label.text = stone.get("description", "")
	power_label.text = str(stone.get("power_text", "Aucun pouvoir de famille : cette pierre est neutre."))
	power_label.add_theme_color_override(
		"font_color", Color(str(god.get("color", "#c8b58c")))
	)
	var blades: Dictionary = stone.get("blades", {})
	stats_label.text = "H %d   •   B %d   •   G %d   •   D %d%s" % [
		blades.get("top", 0), blades.get("bottom", 0),
		blades.get("left", 0), blades.get("right", 0), _special_summary(stone)
	]
	_card.setup(stone, StoneCard.OWNER_NONE)


func show_error(message: String) -> void:
	error_label.text = message
	error_label.visible = true


func close_sheet() -> void:
	visible = false
	_backdrop_tap.reset()
	_shown_variant = ""
	_deck.clear()


func _on_backdrop_input(event: InputEvent) -> void:
	if _backdrop_tap.update(event, $Backdrop) == Gesture.Result.TAP:
		close_sheet()


func _rarity_label(rarity: String) -> String:
	match rarity:
		"common": return "Commune"
		"uncommon": return "Peu commune"
		"rare": return "Rare"
		"epic": return "Épique"
		"legendary": return "Légendaire"
		_: return ""


func _special_summary(stone: Dictionary) -> String:
	var pieces: Array[String] = []
	var random_count := int(stone.get("random_blades", 0))
	if random_count > 0:
		pieces.append(_count_label(random_count, "hasard"))
	var shield_count := 0
	for value in stone.get("shields", {}).values():
		shield_count += int(value)
	if shield_count > 0:
		pieces.append(_count_label(shield_count, "bouclier"))
	var long_count := 0
	for value in stone.get("long_blades", {}).values():
		long_count += int(value)
	if long_count > 0:
		pieces.append(_count_label(long_count, "longue"))
	return "" if pieces.is_empty() else "   •   " + " / ".join(pieces)


## « 1 bouclier », « 2 boucliers ».
static func _count_label(count: int, word: String) -> String:
	return "%d %s%s" % [count, word, "s" if count > 1 else ""]
