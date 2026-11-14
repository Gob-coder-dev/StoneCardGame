## DialogueOverlay.gd
## Boîte de dialogue de type visual novel. Elle affiche une séquence fournie par
## StoryService, révèle le texte au rythme d'une machine à écrire et avance au
## toucher. Elle ne décide jamais quel dialogue jouer.
class_name DialogueOverlay
extends Control

signal closed

const Gesture := preload("res://scripts/ui/input/TapGesture.gd")
const SIDE_DIM := Color(0.52, 0.50, 0.56, 1.0)
const BOX_BG := Color("#121016")
const TEXT_SPEED := 52.0

var _session: StorySession = null
var _lines: Array = []
var _characters: Dictionary = {}
var _character_sides: Dictionary = {}
var _index := 0
var _typing := false
var _total_chars := 0
var _visible_chars := 0.0
var _tap := Gesture.new()

var _backdrop: ColorRect
var _portrait_layer: Control
var _left_portrait: Control
var _right_portrait: Control
var _left_image: TextureRect
var _right_image: TextureRect
var _box: PanelContainer
var _name_label: Label
var _divider: ColorRect
var _text: RichTextLabel
var _hint: Label


func _ready() -> void:
	set_process(false)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	visible = false
	_build()


func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.015, 0.03, 0.76)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	_portrait_layer = Control.new()
	_portrait_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_layer)

	var left := _make_portrait_slot(false)
	_left_portrait = left["slot"]
	_left_image = left["image"]
	_portrait_layer.add_child(_left_portrait)

	var right := _make_portrait_slot(true)
	_right_portrait = right["slot"]
	_right_image = right["image"]
	_portrait_layer.add_child(_right_portrait)

	_box = PanelContainer.new()
	_box.name = "DialogueBox"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_box.offset_left = 36.0
	_box.offset_top = -470.0
	_box.offset_right = -36.0
	_box.offset_bottom = -48.0
	_box.add_theme_stylebox_override("panel",
		UITheme.panel_style(BOX_BG, UITheme.COL_BORDER, 4, 18))
	add_child(_box)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	_box.add_child(content)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override("font_size", 32)
	_name_label.add_theme_color_override("font_color", UITheme.COL_TEXT)
	content.add_child(_name_label)

	_divider = ColorRect.new()
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_divider.custom_minimum_size = Vector2(0, 2)
	_divider.color = UITheme.COL_BORDER
	content.add_child(_divider)

	_text = RichTextLabel.new()
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(0, 250)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", UITheme.FONT_BODY)
	_text.add_theme_constant_override("line_separation", 8)
	_text.add_theme_color_override("default_color", UITheme.COL_TEXT)
	content.add_child(_text)

	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.text = "▼"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 30)
	_hint.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	content.add_child(_hint)


func _make_portrait_slot(right_side: bool) -> Dictionary:
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT if right_side
		else Control.PRESET_BOTTOM_LEFT)
	if right_side:
		slot.anchor_left = 0.51
		slot.anchor_right = 1.0
		slot.offset_left = 0.0
		slot.offset_top = -1450.0
		slot.offset_right = -24.0
		slot.offset_bottom = -486.0
	else:
		slot.anchor_left = 0.0
		slot.anchor_right = 0.49
		slot.offset_left = 24.0
		slot.offset_top = -1450.0
		slot.offset_right = 0.0
		slot.offset_bottom = -486.0
	# Le cadre réserve un carré et le portrait garde ses proportions à
	# l'intérieur. Aucun clip : une image entière ne peut plus être rognée.
	var fit := AspectRatioContainer.new()
	fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit.ratio = 1.0
	fit.stretch_mode = AspectRatioContainer.STRETCH_FIT
	fit.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	fit.alignment_vertical = AspectRatioContainer.ALIGNMENT_END
	fit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(fit)
	var image := TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fit.add_child(image)
	slot.visible = false
	return {"slot": slot, "image": image}


func show_session(session: StorySession) -> void:
	if session == null:
		return
	_session = session
	_lines = session.sequence.get("lines", [])
	_characters = session.context.get("characters", {})
	_character_sides.clear()
	_prepare_portraits()
	_index = 0
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.16)
	grab_focus()
	if _lines.is_empty():
		_close()
		return
	_show_line()


func hide_overlay() -> void:
	visible = false
	_typing = false


func _prepare_portraits() -> void:
	var speakers: Array = []
	for value in _lines:
		if not value is Dictionary:
			continue
		var line: Dictionary = value
		var speaker := str(line.get("speaker", ""))
		if speaker != "" and not speakers.has(speaker) and _characters.has(speaker):
			speakers.append(speaker)
	var left_used := false
	var right_used := false
	for speaker_id in speakers:
		var character: Dictionary = _characters[speaker_id]
		var side := str(character.get("side", "left"))
		if side == "right" and not right_used:
			_character_sides[speaker_id] = "right"
			_set_portrait(_right_image, _right_portrait, character)
			right_used = true
		elif not left_used:
			_character_sides[speaker_id] = "left"
			_set_portrait(_left_image, _left_portrait, character)
			left_used = true
		elif not right_used:
			_character_sides[speaker_id] = "right"
			_set_portrait(_right_image, _right_portrait, character)
			right_used = true
	if not left_used:
		_left_portrait.visible = false
	if not right_used:
		_right_portrait.visible = false


func _set_portrait(image: TextureRect, slot: Control, character: Dictionary) -> void:
	var asset := str(character.get("asset", ""))
	if asset == "" or not ResourceLoader.exists(asset, "Texture2D"):
		slot.visible = false
		return
	image.texture = load(asset) as Texture2D
	slot.visible = true


func _show_line() -> void:
	if _index < 0 or _index >= _lines.size():
		_close()
		return
	var line: Dictionary = _lines[_index]
	var speaker := str(line.get("speaker", ""))
	var character: Dictionary = _characters.get(speaker, {})
	var side := str(_character_sides.get(speaker, "left"))
	_dim_portraits(side)
	var color := Color(str(character.get("color", UITheme.COL_TEXT.to_html())))
	var speaker_name := str(character.get("name", ""))
	_name_label.text = speaker_name.to_upper()
	_name_label.visible = speaker_name != ""
	_divider.color = color
	_box.add_theme_stylebox_override("panel",
		UITheme.panel_style(BOX_BG, color, 4, 18))
	_text.text = str(line.get("text", ""))
	_text.visible_characters = 0
	_total_chars = _text.get_total_character_count()
	_visible_chars = 0.0
	if _total_chars <= 0:
		_text.visible_characters = -1
		_typing = false
		_hint.visible = true
	else:
		_typing = true
		_hint.visible = false
	set_process(_typing)


func _dim_portraits(active_side: String) -> void:
	_left_portrait.modulate = Color.WHITE if active_side == "left" else SIDE_DIM
	_right_portrait.modulate = Color.WHITE if active_side == "right" else SIDE_DIM


func _process(delta: float) -> void:
	if not visible or not _typing:
		return
	_visible_chars = minf(float(_total_chars), _visible_chars + TEXT_SPEED * delta)
	_text.visible_characters = int(_visible_chars)
	if _visible_chars >= float(_total_chars):
		_finish_typing()


func _finish_typing() -> void:
	_typing = false
	set_process(false)
	_text.visible_characters = -1
	_hint.visible = true


func _advance() -> void:
	if not visible or _lines.is_empty():
		return
	Audio.play_sfx(AudioCatalog.SFX_BUTTON)
	if _typing:
		_finish_typing()
		return
	if _index + 1 < _lines.size():
		_index += 1
		_show_line()
		return
	_close()


func _close() -> void:
	if not visible and _session == null:
		return
	visible = false
	set_process(false)
	_typing = false
	_lines.clear()
	_session = null
	closed.emit()


func _gui_input(event: InputEvent) -> void:
	if _tap.update(event, self) == Gesture.Result.TAP:
		_advance()
		accept_event()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_EXIT_TREE \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_tap.reset()
