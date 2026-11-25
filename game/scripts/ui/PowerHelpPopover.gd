## Bulle partagée entre combat et fiche. Elle consomme l’appui extérieur pour
## que la fermeture ne joue aucune carte et ne déclenche aucune action derrière.
extends Control

const PowerHelp := preload("res://scripts/ui/PowerHelp.gd")
const TouchButton := preload("res://scripts/ui/input/TouchButton.gd")
const Gesture := preload("res://scripts/ui/input/TapGesture.gd")
const MAX_WIDTH := 840.0

var _anchor: Button
var _panel: PanelContainer
var _rows: VBoxContainer
var _title: Label
var _close_button: Button
var _outside_tap := Gesture.new()


static func make_button() -> Button:
	var button := TouchButton.new()
	button.name = "PowerHelpButton"
	button.text = "?"
	button.tooltip_text = "Voir les pouvoirs du dieu"
	button.custom_minimum_size = Vector2(68, 68)
	button.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	button.add_theme_color_override("font_color", UITheme.COL_ACCENT_LIGHT)
	for state in ["normal", "hover", "pressed"]:
		var style := UITheme.panel_style(UITheme.COL_BG, UITheme.COL_BORDER, 2, 32)
		if state != "normal":
			style.bg_color = UITheme.COL_SELECTED
			style.border_color = UITheme.COL_ACCENT_LIGHT
		style.set_content_margin_all(0.0)
		style.shadow_size = 0
		button.add_theme_stylebox_override(state, style)
	return button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 60
	hide()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.035, 0.05, 0.22)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(_on_outside_input.bind(backdrop))

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.COL_PANEL_BG, UITheme.COL_ACCENT_LIGHT))
	add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", UITheme.GAP_SMALL)
	_panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_title = _make_label("", UITheme.FONT_BODY)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_title)
	_close_button = make_button()
	_close_button.name = "CloseButton"
	_close_button.text = "×"
	_close_button.tooltip_text = "Fermer l’aide"
	header.add_child(_close_button)
	_close_button.pressed.connect(close)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", UITheme.GAP_SMALL)
	content.add_child(_rows)
	_panel.resized.connect(_position_panel)
	_panel.minimum_size_changed.connect(_fit_height, CONNECT_DEFERRED)
	resized.connect(_fit_panel)


func open_for_god(god_id: String, anchor: Button) -> void:
	var powers: Array = PowerHelp.BY_GOD.get(god_id, [])
	if powers.is_empty():
		return
	_anchor = anchor
	var god := MonsterLoader.get_god(god_id)
	_title.text = str(god["name"])
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var tint := Color(str(god["color"]))
	_title.add_theme_color_override("font_color", tint.lightened(0.3))
	for kind in powers:
		_add_power(kind, tint)
	show()
	_fit_panel()
	_close_button.grab_focus()


func close(restore_focus: bool = true) -> bool:
	if not visible:
		return false
	hide()
	_outside_tap.reset()
	if restore_focus and is_instance_valid(_anchor) and _anchor.is_visible_in_tree():
		_anchor.grab_focus()
	_anchor = null
	return true


func _add_power(kind: String, tint: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_SMALL)
	row.add_child(PowerHelp.make_badge(kind, tint, 0, 64.0))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _make_label(PowerHelp.title(kind), UITheme.FONT_SMALL)
	title.add_theme_color_override("font_color", UITheme.COL_ACCENT_LIGHT)
	text.add_child(title)
	text.add_child(_make_label(PowerHelp.description(kind), UITheme.FONT_BODY))
	row.add_child(text)
	_rows.add_child(row)


func _make_label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _fit_panel() -> void:
	if not visible:
		return
	_panel.size.x = minf(MAX_WIDTH, size.x - 2.0 * UITheme.GAP_SMALL)
	_position_panel()


## Le retour à la ligne est calculé après la distribution de la largeur.
## Le panneau doit pouvoir rétrécir lorsque cette hauteur minimale est connue.
func _fit_height() -> void:
	_panel.size.y = _panel.get_combined_minimum_size().y


func _position_panel() -> void:
	if not visible or not is_instance_valid(_anchor):
		return
	var transform := get_global_transform_with_canvas().affine_inverse() * _anchor.get_global_transform_with_canvas()
	var top := transform * Vector2.ZERO
	var bottom := transform * _anchor.size
	var gap := float(UITheme.GAP_SMALL)
	var below := bottom.y + gap
	var above := top.y - gap - _panel.size.y
	var preferred_y := below if below + _panel.size.y <= size.y - gap else above
	_panel.position = Vector2(
		clampf((top.x + bottom.x - _panel.size.x) * 0.5, gap, maxf(gap, size.x - _panel.size.x - gap)),
		clampf(preferred_y, gap, maxf(gap, size.y - _panel.size.y - gap)))


func _on_outside_input(event: InputEvent, backdrop: Control) -> void:
	if _outside_tap.update(event, backdrop) == Gesture.Result.TAP:
		backdrop.accept_event()
		close()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif preload("res://scripts/ui/input/FocusScope.gd").navigation_step(event) != 0:
		_close_button.grab_focus()
		get_viewport().set_input_as_handled()
