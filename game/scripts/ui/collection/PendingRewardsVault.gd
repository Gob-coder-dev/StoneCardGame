## Fenêtre de consultation des cartes divines gagnées avant leur dieu.
class_name PendingRewardsVault
extends Control

signal shop_requested

const Presenter := preload("res://scripts/ui/collection/PendingRewardsPresenter.gd")
const CardLayout := preload("res://scripts/ui/collection/CardGridLayout.gd")

@onready var groups_container: VBoxContainer = $Margin/Panel/Content/Scroll/Groups
@onready var empty_label: Label = $Margin/Panel/Content/Scroll/Groups/Empty
@onready var shop_button: Button = $Margin/Panel/Content/Actions/ShopButton
@onready var close_button: Button = $Margin/Panel/Content/Actions/CloseButton


func _ready() -> void:
	close_button.pressed.connect(close)
	shop_button.pressed.connect(shop_requested.emit)
	visibility_changed.connect(_on_visibility_changed)
	visible = false


func open() -> void:
	rebuild()
	visible = true


func close() -> void:
	visible = false


func rebuild() -> void:
	for child in groups_container.get_children():
		if child != empty_label:
			groups_container.remove_child(child)
			child.queue_free()
	var groups := Presenter.groups()
	empty_label.visible = groups.is_empty()
	shop_button.visible = not groups.is_empty()
	for group in groups:
		groups_container.add_child(_make_god_section(group))


func _make_god_section(group: Dictionary) -> PanelContainer:
	var god: Dictionary = group.get("god", {})
	var color := Color(str(god.get("color", UITheme.COL_BORDER.to_html())))
	var panel := PanelContainer.new()
	panel.set_meta("god_id", str(god.get("id", "")))
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(
		UITheme.COL_PANEL_BG, color, 3, 16))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	panel.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	content.add_child(header)
	var portrait := GodPortrait.new()
	portrait.custom_minimum_size = Vector2(96, 96)
	portrait.setup(god)
	header.add_child(portrait)
	var title := Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text = "DÉBLOQUER %s" % str(god.get("name", "")).to_upper()
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", color.lightened(0.22))
	header.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	content.add_child(grid)
	for card_reward in group.get("cards", []):
		grid.add_child(_make_reward_card(card_reward))
	return panel


func _make_reward_card(reward: Dictionary) -> VBoxContainer:
	var lineage_id := str(reward.get("lineage_id", ""))
	var stone_id := StoneLoader.variant_id(lineage_id, 1)
	var wrapper := CardLayout.make_card_wrapper(true, 220)
	var card := CardLayout.make_stone_card(
		StoneLoader.get_stone(stone_id), StoneCard.OWNER_NONE, 220)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_show_cost(false)
	card.modulate = Color(0.64, 0.64, 0.70, 0.9)
	wrapper.add_child(card)
	var quantity := Label.new()
	quantity.name = "Quantity"
	quantity.text = "×%d" % int(reward.get("copies", 0))
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity.add_theme_font_size_override("font_size", 28)
	quantity.add_theme_color_override("font_color", UITheme.COL_WARNING)
	wrapper.add_child(quantity)
	return wrapper


func _on_visibility_changed() -> void:
	if visible:
		close_button.grab_focus()
