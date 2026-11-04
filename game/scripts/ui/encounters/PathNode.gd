## PathNode.gd
## Rond d'un niveau sur le chemin. La couleur et la forme distinguent les
## états : terminé (✓), disponible (numéro cerclé), verrouillé (cadenas).
extends "res://scripts/ui/input/TouchButton.gd"

const EncounterPathModel := preload("res://scripts/domain/EncounterPath.gd")

var level_index: int = 0
var state: int = EncounterPathModel.State.LOCKED
var chosen: bool = false

var _accent := UITheme.COL_NEON_PINK
var _pulse := 0.0
var _pulse_tween: Tween = null


func _ready() -> void:
	set_process(false)
	resized.connect(_refresh)
	_refresh()


func configure(level: Dictionary, accent: Color, is_chosen: bool) -> void:
	level_index = int(level.get("index", level_index))
	_accent = accent
	chosen = is_chosen
	tooltip_text = "%s • %s" % [
		str(level.get("bracket_label", "")),
		str(level.get("difficulty_label", "")),
	]
	state = int(level.get("state", EncounterPathModel.State.LOCKED))
	disabled = state == EncounterPathModel.State.LOCKED
	match state:
		EncounterPathModel.State.COMPLETED:
			text = "✓"
		EncounterPathModel.State.AVAILABLE:
			text = str(level_index + 1)
		_:
			text = ""
	_set_pulse(state == EncounterPathModel.State.AVAILABLE)
	_refresh()


func set_chosen(value: bool) -> void:
	if chosen == value:
		return
	chosen = value
	_refresh()


func _process(_delta: float) -> void:
	queue_redraw()


func _set_pulse(enabled: bool) -> void:
	if enabled:
		set_process(true)
		if _pulse_tween == null:
			_pulse_tween = create_tween().set_loops()
			_pulse_tween.tween_property(self, "_pulse", 1.0, 1.3) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_pulse_tween.tween_property(self, "_pulse", 0.0, 1.3) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		return
	set_process(false)
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	_pulse = 0.0
	queue_redraw()


func _refresh() -> void:
	var diameter := maxf(minf(size.x, size.y), float(UITheme.PATH_NODE_SIZE) * 0.5)
	var radius := int(diameter * 0.5)
	var fill := UITheme.COL_NODE_LOCKED_BG
	var border := UITheme.COL_NODE_LOCKED_BORDER
	var border_width := 3
	var text_color := UITheme.COL_NODE_LOCKED_TEXT
	match state:
		EncounterPathModel.State.COMPLETED:
			fill = _accent.darkened(0.55)
			border = _accent
			border_width = 5
			text_color = UITheme.COL_TEXT
		EncounterPathModel.State.AVAILABLE:
			fill = UITheme.COL_SELECTED
			border = _accent.lightened(0.15)
			border_width = 4
			text_color = UITheme.COL_TEXT
	if chosen:
		border = UITheme.COL_ACCENT_LIGHT
		border_width += 3

	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.06, 0.02, 0.07, 0.55)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 6.0)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = fill.lightened(0.07)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = fill.darkened(0.12)
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed)
	add_theme_stylebox_override("hover_pressed", pressed)
	add_theme_stylebox_override("disabled", style)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_font_size_override("font_size", int(diameter * 0.36))
	add_theme_color_override("font_color", text_color)
	add_theme_color_override("font_hover_color", text_color)
	add_theme_color_override("font_pressed_color", text_color)
	add_theme_color_override("font_disabled_color", text_color)
	queue_redraw()


## Dessine les signes qui ne dépendent pas d'une police : l'anneau pulsé du
## niveau ouvert et le cadenas du niveau verrouillé.
func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	if state == EncounterPathModel.State.AVAILABLE:
		var ring := _accent
		ring.a = 0.16 + 0.22 * (1.0 - _pulse)
		draw_arc(center, radius + 7.0 + 12.0 * _pulse, 0.0, TAU, 56, ring, 3.0, true)
	elif state == EncounterPathModel.State.LOCKED:
		_draw_lock(center, radius)


func _draw_lock(center: Vector2, radius: float) -> void:
	var ink := UITheme.COL_NODE_LOCKED_TEXT
	var body := Rect2(
		center + Vector2(-radius * 0.26, radius * 0.02),
		Vector2(radius * 0.52, radius * 0.38))
	draw_rect(body, UITheme.COL_NODE_LOCKED_BG, true)
	draw_rect(body, ink, false, 3.0)
	var shackle_center := center + Vector2(0.0, radius * 0.02 - radius * 0.20)
	draw_arc(shackle_center, radius * 0.18, PI, TAU, 24, ink, 3.0, true)
	draw_circle(center + Vector2(0.0, radius * 0.17), radius * 0.045, ink)
