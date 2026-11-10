## Modale de confirmation purement visuelle. Le contrôleur reste l'unique
## orchestrateur des achats et revalide toujours les données via les services.
class_name ShopPurchaseModal
extends Control

signal confirmed(kind: String, offer_id: String)

const SoulIcon := preload("res://assets/ui/soul-placeholder.svg")
const CandleIcon := preload("res://assets/ui/candle-placeholder.svg")

@onready var title_label: Label = $Center/Panel/Content/Title
@onready var visual: CenterContainer = $Center/Panel/Content/Visual
@onready var details_label: Label = $Center/Panel/Content/Details
@onready var cancel_button: Button = $Center/Panel/Content/Actions/Cancel
@onready var confirm_button: Button = $Center/Panel/Content/Actions/Confirm

var _kind := ""
var _offer_id := ""


func _ready() -> void:
	cancel_button.pressed.connect(close)
	confirm_button.pressed.connect(_confirm)


func show_ritual(definition: Dictionary, candle_balance: int) -> void:
	_reset_visual()
	_kind = "ritual"
	_offer_id = str(definition.get("id", ""))
	title_label.text = str(definition.get("name", "Rituel")).to_upper()
	var sigil := RitualSigil.new()
	sigil.custom_minimum_size = Vector2(470, 470)
	sigil.setup(definition)
	visual.add_child(sigil)
	details_label.text = _ritual_details(definition)
	var price := int(definition.get("price_candles", 0))
	_setup_confirm(price, CandleIcon, bool(definition.get("available", true)),
		candle_balance, str(definition.get("unavailable_reason", "")))
	visible = true
	cancel_button.grab_focus()


func show_god(god: Dictionary, price: int, soul_balance: int, gifts: Array) -> void:
	_reset_visual()
	_kind = "god"
	_offer_id = str(god.get("id", ""))
	title_label.text = str(god.get("name", _offer_id)).to_upper()
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 10)
	var portrait := GodPortrait.new()
	portrait.custom_minimum_size = Vector2(330, 330)
	portrait.setup(god)
	content.add_child(portrait)
	var gift_label := Label.new()
	gift_label.text = "CARTES OFFERTES"
	gift_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gift_label.add_theme_font_size_override("font_size", 22)
	content.add_child(gift_label)
	var gift_row := HBoxContainer.new()
	gift_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gift_row.add_theme_constant_override("separation", 18)
	for lineage_id in gifts:
		var stone_id := StoneLoader.variant_id(str(lineage_id), 1)
		var card := StoneCard.new()
		card.custom_minimum_size = Vector2(145, 145)
		card.set_show_cost(false)
		card.setup(StoneLoader.get_stone(stone_id), StoneCard.OWNER_NONE)
		gift_row.add_child(card)
	content.add_child(gift_row)
	visual.add_child(content)
	details_label.text = "Débloque définitivement ce dieu et libère toutes ses cartes déjà conservées dans le coffre."
	_setup_confirm(price, SoulIcon, true, soul_balance, "")
	visible = true
	cancel_button.grab_focus()


func set_busy(busy: bool) -> void:
	cancel_button.disabled = busy
	confirm_button.disabled = busy or bool(confirm_button.get_meta("unavailable", false))


func close() -> void:
	visible = false
	_kind = ""
	_offer_id = ""
	_reset_visual()


func _confirm() -> void:
	if _kind == "" or _offer_id == "" or confirm_button.disabled:
		return
	confirmed.emit(_kind, _offer_id)


func _setup_confirm(price: int, icon: Texture2D, available: bool,
		balance: int, unavailable_reason: String) -> void:
	confirm_button.text = UIFormat.integer(price)
	confirm_button.icon = icon
	confirm_button.add_theme_constant_override("icon_max_width", 48)
	confirm_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var unavailable := not available or balance < price
	confirm_button.set_meta("unavailable", unavailable)
	confirm_button.disabled = unavailable
	confirm_button.tooltip_text = unavailable_reason if not available \
		else ("Solde insuffisant" if balance < price else "Confirmer l'achat")
	if not available and unavailable_reason != "":
		details_label.text += "\n\n%s" % unavailable_reason


func _ritual_details(definition: Dictionary) -> String:
	if bool(definition.get("unique_missing", false)):
		return "Une nouvelle carte garantie parmi tout le catalogue. Une carte liée à un dieu verrouillé sera conservée dans votre coffre."
	var lines: Array[String] = []
	lines.append("Âmes : %d à %d" % [int(definition.get("souls_min", 0)),
		int(definition.get("souls_max", 0))])
	lines.append("Invocations : %s" % _groups_text(definition.get("normal", [])))
	var chance := int(round(float(definition.get("lucky_chance", 0.0)) * 100.0))
	if chance > 0:
		lines.append("%d %% exceptionnel : %s" % [chance,
			_groups_text(definition.get("lucky", []))])
	return "\n".join(lines)


func _groups_text(groups: Array) -> String:
	var parts: Array[String] = []
	for group in groups:
		var slots := int(group.get("slots", 0))
		var minimum := int(group.get("min_copies", 1))
		var maximum := int(group.get("max_copies", minimum))
		var amount := "×%d" % minimum if minimum == maximum else "×%d–%d" % [minimum, maximum]
		parts.append("%d %s %s" % [slots, _rarity_name(str(group.get("rarity", "")), slots), amount])
	return ", ".join(parts)


func _rarity_name(rarity: String, count: int) -> String:
	var names := {"common": "commune", "rare": "rare", "epic": "épique", "legendary": "légendaire"}
	var value := str(names.get(rarity, rarity))
	return value + ("s" if count > 1 else "")


func _reset_visual() -> void:
	if not is_node_ready():
		return
	for child in visual.get_children():
		visual.remove_child(child)
		child.queue_free()
