## Fiche détaillée d'un monstre, indépendante de l'écran de collection.
class_name MonsterInfoSheet
extends Control
signal use_requested(monster_id: String)
signal upgrade_requested(lineage_id: String)
const NumberedSelector := preload("res://scripts/ui/collection/NumberedSelector.gd")
const PowerHelp := preload("res://scripts/ui/PowerHelp.gd")
const PowerHelpPopover := preload("res://scripts/ui/PowerHelpPopover.gd")
const Symbols := preload("res://scripts/ui/MonsterSymbols.gd")

@onready var title_label: Label = $InfoPanel/InfoContent/Header/Title
@onready var summary_label: Label = $InfoPanel/InfoContent/Scroll/Page/Summary
@onready var description_label: Label = $InfoPanel/InfoContent/Scroll/Page/Description
@onready var power_row: HBoxContainer = $InfoPanel/InfoContent/Scroll/Page/PowerRow
@onready var power_badges: HBoxContainer = $InfoPanel/InfoContent/Scroll/Page/PowerRow/Badges
@onready var power_label: Label = $InfoPanel/InfoContent/Scroll/Page/PowerRow/Power
@onready var stats_label: Label = $InfoPanel/InfoContent/Scroll/Page/Stats
@onready var card_container: MarginContainer = $InfoPanel/InfoContent/Scroll/Page/Card
@onready var close_button: Button = $InfoPanel/InfoContent/Header/CloseButton
@onready var use_button: UpgradePriceButton = $InfoPanel/InfoContent/UseButton
@onready var error_label: Label = $InfoPanel/InfoContent/Error
@onready var _power_help := PowerHelpPopover.new()

const Gesture := preload("res://scripts/ui/input/TapGesture.gd")
var _backdrop_tap := Gesture.new()
var _selector: NumberedSelector
var _card: MonsterCard
var _lineage := ""
var _shown_variant := ""
var _deck: Array = []
var _god_help: VBoxContainer
var _god_label: Label
var _power_button: Button


func _ready() -> void:
	close_button.pressed.connect(close_sheet)
	$Backdrop.gui_input.connect(_on_backdrop_input)
	use_button.pressed.connect(_on_primary_pressed)
	_card = MonsterCard.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card.set_edge_margin_ratio(UITheme.CARD_PREVIEW_EDGE_MARGIN)
	_card.set_power_badge_scale(UITheme.CARD_PREVIEW_POWER_BADGE_SCALE)
	_card.set_show_cost(true)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_container.add_child(_card)
	card_container.resized.connect(_fit_card)
	_fit_card.call_deferred()
	_build_god_help()
	add_child(_power_help)
	_power_help.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _build_god_help() -> void:
	_god_help = VBoxContainer.new()
	_god_help.alignment = BoxContainer.ALIGNMENT_CENTER
	_god_help.add_theme_constant_override("separation", 4)
	power_row.add_child(_god_help)
	_god_label = Label.new()
	_god_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_god_label.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	_god_help.add_child(_god_label)
	_power_button = PowerHelpPopover.make_button()
	_power_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_power_button.pressed.connect(_open_power_help)
	_god_help.add_child(_power_button)


## La hauteur participe réellement au VBox et au défilement de la fiche.
func _fit_card() -> void:
	var side := card_container.size.x
	if side > 0 and not is_equal_approx(card_container.custom_minimum_size.y, side):
		card_container.custom_minimum_size.y = side


func open_for(monster_id: String, deck: Array = []) -> void:
	if not MonsterLoader.has_monster(monster_id):
		return
	_lineage = MonsterLoader.monster_lineage(monster_id)
	_deck = deck.duplicate()
	var row: HBoxContainer = $InfoPanel/InfoContent/Levels
	for button in row.get_children():
		row.remove_child(button)
		button.queue_free()
	_selector = NumberedSelector.new(row, MonsterLoader.lineage_max_level(_lineage))
	_selector.value_selected.connect(_select_level)
	_selector.show_unlocked_through(int(PlayerData.card_entry(_lineage).get("unlocked_level", 0)))
	_refresh_form(monster_id)
	$InfoPanel/InfoContent/Scroll.scroll_vertical = 0
	visible = true


func _select_level(level: int) -> void:
	var id := MonsterLoader.variant_id(_lineage, level)
	if id != "":
		_refresh_form(id)


func _refresh_form(monster_id: String) -> void:
	_power_help.close(false)
	_shown_variant = monster_id
	var monster := MonsterLoader.get_monster(monster_id)
	var level := MonsterLoader.monster_level(monster_id)
	var owned := PlayerData.owns_monster(monster_id)
	var unlocked_level := int(PlayerData.card_entry(_lineage).get("unlocked_level", 0))
	var is_next_level := not owned and level == unlocked_level + 1
	_selector.refresh(level)
	if owned:
		_set_action_state("UTILISER", _deck.has(monster_id), false)
	elif is_next_level:
		var upgrade := PlayerData.card_upgrade_state(_lineage)
		var requirement: Dictionary = upgrade.get("requirement", {})
		_set_action_state("AMÉLIORER", not bool(upgrade.get("can_upgrade", false)),
			true, int(requirement.get("souls", 0)))
	else:
		_set_action_state("NIVEAU VERROUILLÉ", true, false)
	error_label.visible = false
	title_label.text = monster.get("name", monster_id)
	var god := MonsterLoader.get_god(str(monster.get("god_id", "neutral")))
	var family := "Neutre" if god.is_empty() else str(god.get("family_name", ""))
	summary_label.text = "%s • %s • Niv. %d • %s points" % [
		_rarity_label(monster.get("rarity", "")), family, level,
		UIFormat.cost(MonsterLoader.monster_cost(monster_id))
	]
	description_label.text = monster.get("description", "")
	_refresh_power_row(monster, god)
	var blades: Dictionary = monster.get("blades", {})
	stats_label.text = "H %d   •   B %d   •   G %d   •   D %d%s" % [
		blades.get("top", 0), blades.get("bottom", 0),
		blades.get("left", 0), blades.get("right", 0), _special_summary(monster)
	]
	_card.setup(monster, MonsterCard.OWNER_NONE)
	_card.modulate = Color.WHITE if owned else Color(0.38, 0.38, 0.43, 0.72)


func _set_action_state(title: String, disabled: bool, upgrading: bool,
		price: int = 0) -> void:
	# Le texte natif reste renseigné pour l'accessibilité et les contrôles, mais
	# son rendu est transparent : la composition sur deux lignes vit au-dessus.
	use_button.text = title
	use_button.disabled = disabled
	use_button.theme_type_variation = &"UpgradeButton" if upgrading else &"PrimaryButton"
	var title_color := UITheme.COL_WARNING if upgrading else (
		UITheme.COL_TEXT_DIM if disabled else UITheme.COL_INK)
	use_button.set_content(title, upgrading, price, title_color)


func _on_primary_pressed() -> void:
	if _shown_variant == "":
		return
	if PlayerData.owns_monster(_shown_variant):
		use_requested.emit(_shown_variant)
		return
	var shown_level := MonsterLoader.monster_level(_shown_variant)
	var unlocked_level := int(PlayerData.card_entry(_lineage).get("unlocked_level", 0))
	if shown_level == unlocked_level + 1 \
			and bool(PlayerData.card_upgrade_state(_lineage).get("can_upgrade", false)):
		upgrade_requested.emit(_lineage)


## Conserve le niveau consulté après la transaction et actualise son état.
func refresh_inventory_state() -> void:
	if _shown_variant == "" or _selector == null:
		return
	_selector.show_unlocked_through(
		int(PlayerData.card_entry(_lineage).get("unlocked_level", 0)))
	_refresh_form(_shown_variant)


func _refresh_power_row(monster: Dictionary, god: Dictionary) -> void:
	var family_color := Color(str(god.get("color", UITheme.COL_TEXT_DIM.to_html())))
	for child in power_badges.get_children():
		power_badges.remove_child(child)
		child.queue_free()
	var titles: Array[String] = []
	for definition in Symbols.badges_for(monster):
		var kind := str(definition["kind"])
		var count := int(definition.get("count", 0))
		titles.append(PowerHelp.title(kind))
		power_badges.add_child(PowerHelp.make_badge(kind, family_color, count, 96.0))
	power_label.text = "Sans pouvoir de famille." if titles.is_empty() else " • ".join(titles)
	power_label.add_theme_color_override("font_color", family_color.lightened(0.2))
	power_badges.visible = not titles.is_empty()
	_god_label.text = str(god.get("name", ""))
	_god_label.add_theme_color_override("font_color", family_color.lightened(0.2))
	_god_help.visible = PowerHelp.BY_GOD.has(str(god.get("id", "")))


func _open_power_help() -> void:
	_power_help.open_for_god(MonsterLoader.monster_affinity(_shown_variant), _power_button)


func close_power_help() -> bool:
	return _power_help.close()


func show_error(message: String) -> void:
	error_label.text = message
	error_label.visible = true


func close_sheet() -> void:
	_power_help.close(false)
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


func _special_summary(monster: Dictionary) -> String:
	var pieces: Array[String] = []
	var random_count := int(monster.get("random_blades", 0))
	if random_count > 0:
		pieces.append(_count_label(random_count, "hasard"))
	var shield_count := 0
	for value in monster.get("shields", {}).values():
		shield_count += int(value)
	if shield_count > 0:
		pieces.append(_count_label(shield_count, "bouclier"))
	var long_count := 0
	for value in monster.get("long_blades", {}).values():
		long_count += int(value)
	if long_count > 0:
		pieces.append(_count_label(long_count, "longue"))
	return "" if pieces.is_empty() else "   •   " + " / ".join(pieces)


## « 1 bouclier », « 2 boucliers ».
static func _count_label(count: int, word: String) -> String:
	return "%d %s%s" % [count, word, "s" if count > 1 else ""]
