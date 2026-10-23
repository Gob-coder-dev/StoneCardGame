## Fiche détaillée d'une pierre, indépendante de l'écran de collection.
class_name StoneInfoSheet
extends Control

@onready var title_label: Label = $InfoPanel/InfoContent/Header/Title
@onready var summary_label: Label = $InfoPanel/InfoContent/Summary
@onready var description_label: Label = $InfoPanel/InfoContent/Description
@onready var power_label: Label = $InfoPanel/InfoContent/Power
@onready var stats_label: Label = $InfoPanel/InfoContent/Stats
@onready var card_container: CenterContainer = $InfoPanel/InfoContent/Card
@onready var close_button: Button = $InfoPanel/InfoContent/Header/CloseButton

const Gesture := preload("res://scripts/ui/input/TapGesture.gd")
var _backdrop_tap := Gesture.new()


func _ready() -> void:
	close_button.pressed.connect(close_sheet)
	$Backdrop.gui_input.connect(_on_backdrop_input)
	visible = false


func open_for(stone: Dictionary) -> void:
	if stone.is_empty():
		return
	var stone_id := str(stone.get("id", ""))
	title_label.text = stone.get("name", stone_id)
	var god := StoneLoader.get_god(str(stone.get("god_id", "neutral")))
	var family := "Neutre" if god.is_empty() else str(god.get("family_name", ""))
	summary_label.text = "%s • %s • %s points" % [
		_rarity_label(stone.get("rarity", "")), family,
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
	_clear_card()
	var card := StoneCard.new()
	card.custom_minimum_size = Vector2(UITheme.CARD_INFO, UITheme.CARD_INFO)
	card.setup(stone, StoneCard.OWNER_NONE)
	card.set_show_cost(true)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_container.add_child(card)
	visible = true


func close_sheet() -> void:
	visible = false
	_backdrop_tap.reset()


func _clear_card() -> void:
	for child in card_container.get_children():
		card_container.remove_child(child)
		child.queue_free()


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
	if int(stone.get("random_blades", 0)) > 0:
		pieces.append("%d hasard" % int(stone["random_blades"]))
	var shield_count := 0
	for value in stone.get("shields", {}).values():
		shield_count += int(value)
	if shield_count > 0:
		pieces.append("%d bouclier" % shield_count)
	var long_count := 0
	for value in stone.get("long_blades", {}).values():
		long_count += int(value)
	if long_count > 0:
		pieces.append("%d longue" % long_count)
	return "" if pieces.is_empty() else "   •   " + " / ".join(pieces)
