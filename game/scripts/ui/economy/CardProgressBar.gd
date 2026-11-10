## Jauge compacte des copies d'une lignée, partagée par le deck et la collection.
class_name CardProgressBar
extends ProgressBar

var lineage_id := ""
var count_label: Label


func _init() -> void:
	custom_minimum_size = Vector2(0, 36)
	show_percentage = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#111016")
	background.border_color = UITheme.COL_BORDER
	background.set_border_width_all(2)
	background.set_corner_radius_all(9)
	add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.COL_ACCENT
	fill.set_corner_radius_all(7)
	add_theme_stylebox_override("fill", fill)
	count_label = Label.new()
	count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 22)
	add_child(count_label)


func setup(card_lineage_id: String) -> void:
	lineage_id = card_lineage_id
	var upgrade := PlayerData.card_upgrade_state(lineage_id)
	var entry: Dictionary = upgrade.get("entry", {})
	var unlocked := int(entry.get("unlocked_level", 0))
	var requirement: Dictionary = upgrade.get("requirement", {})
	visible = unlocked > 0 and not requirement.is_empty()
	if not visible:
		return
	var copies := int(entry.get("copies", 0))
	var needed := maxi(1, int(requirement.get("copies", 1)))
	max_value = needed
	self.value = mini(copies, needed)
	count_label.text = "%d/%d" % [copies, needed]
	count_label.add_theme_color_override("font_color",
		UITheme.COL_TEXT if copies < needed else UITheme.COL_WARNING)
