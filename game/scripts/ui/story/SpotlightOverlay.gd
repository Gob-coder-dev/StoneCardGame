## SpotlightOverlay.gd
## Voile d'action guidée : assombrit tout l'écran sauf une cible, bloque les
## gestes autour d'elle et affiche la consigne. La cible reste un vrai Control
## du jeu : le tutoriel ne simule aucun clic.
##
## Deux usages coexistent :
##   - cible interactive : le joueur touche la carte ou la case réelle ;
##   - cible expliquée : un bouton SUIVANT fait avancer la présentation et la
##     cible est neutralisée pour éviter d'ouvrir un écran par erreur.
class_name SpotlightOverlay
extends Control

signal advance_requested

const DIM := Color(0.015, 0.01, 0.025, 0.82)
const ACCENT := UITheme.COL_ACCENT_LIGHT
const BANNER_SIDE_MARGIN := 36.0
const BANNER_TARGET_GAP := 28.0
# Sur les téléphones très allongés, placer la consigne au bord opposé de la
# cible la rendait artificiellement lointaine. Cette bande garde le texte dans
# la partie utile de l'écran, tout en laissant la cible entièrement dégagée.
const BANNER_CENTER_MIN_RATIO := 0.24
const BANNER_CENTER_MAX_RATIO := 0.76

var _target: Control = null
var _hole := Rect2()
var _time := 0.0
var _banner: PanelContainer
var _prompt: Label
var _advance_button: Button
var _target_blocker: Control
var _blockers: Array[Control] = []


func _ready() -> void:
	set_process(false)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	for index in range(4):
		var blocker := Control.new()
		blocker.name = "Blocker%d" % index
		blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		blocker.focus_mode = Control.FOCUS_NONE
		add_child(blocker)
		_blockers.append(blocker)
	# Ce bloqueur couvre la cible quand l'étape est purement explicative. Il est
	# ajouté après les quatre bandes et avant la bannière, qui reste cliquable.
	_target_blocker = Control.new()
	_target_blocker.name = "TargetBlocker"
	_target_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_target_blocker.focus_mode = Control.FOCUS_NONE
	_target_blocker.visible = false
	add_child(_target_blocker)

	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("#121016"), ACCENT, 3, 14))
	add_child(_banner)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_banner.add_child(margin)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	_prompt = Label.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.add_theme_font_size_override("font_size", 32)
	_prompt.add_theme_color_override("font_color", UITheme.COL_TEXT)
	content.add_child(_prompt)
	_advance_button = Button.new()
	_advance_button.name = "AdvanceButton"
	_advance_button.text = "SUIVANT"
	_advance_button.custom_minimum_size = Vector2(0, 82)
	_advance_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_advance_button.theme_type_variation = &"PrimaryButton"
	_advance_button.add_theme_font_size_override("font_size", 30)
	_advance_button.visible = false
	_advance_button.pressed.connect(func() -> void: advance_requested.emit())
	content.add_child(_advance_button)


## `show_advance` transforme la cible en illustration : un bouton SUIVANT
## apparaît et les gestes sur la cible sont interceptés.
func show_target(target: Control, prompt: String, show_advance: bool = false) -> void:
	if target == null:
		return
	_target = target
	_prompt.text = prompt
	_prompt.visible = prompt != ""
	_advance_button.visible = show_advance
	_banner.visible = prompt != "" or show_advance
	_target_blocker.visible = show_advance
	visible = true
	set_process(true)
	_time = 0.0
	_update_geometry()
	queue_redraw()
	move_to_front()


func hide_spotlight() -> void:
	_target = null
	_target_blocker.visible = false
	_advance_button.visible = false
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not visible:
		return
	if _target != null and not is_instance_valid(_target):
		hide_spotlight()
		return
	if _target == null:
		return
	_time += delta
	_update_geometry()
	queue_redraw()


func _update_geometry() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var viewport_size := size if size.x > 0.0 and size.y > 0.0 else get_viewport_rect().size
	var target_rect := _target.get_global_rect()
	_hole = target_rect.grow(14.0).intersection(Rect2(Vector2.ZERO, viewport_size))
	var width := viewport_size.x
	var height := viewport_size.y
	_set_blocker(0, Rect2(0.0, 0.0, width, maxf(0.0, _hole.position.y)))
	_set_blocker(1, Rect2(0.0, _hole.end.y, width,
		maxf(0.0, height - _hole.end.y)))
	_set_blocker(2, Rect2(0.0, _hole.position.y, maxf(0.0, _hole.position.x),
		maxf(0.0, _hole.size.y)))
	_set_blocker(3, Rect2(_hole.end.x, _hole.position.y,
		maxf(0.0, width - _hole.end.x), maxf(0.0, _hole.size.y)))
	if _target_blocker.visible:
		_target_blocker.position = _hole.position
		_target_blocker.size = _hole.size
	_place_banner(viewport_size)


func _set_blocker(index: int, rect: Rect2) -> void:
	var blocker := _blockers[index]
	blocker.position = rect.position
	blocker.size = rect.size
	blocker.visible = rect.size.x > 0.0 and rect.size.y > 0.0


func _place_banner(viewport_size: Vector2) -> void:
	if not _banner.visible:
		return
	_banner.custom_minimum_size.x = viewport_size.x - BANNER_SIDE_MARGIN * 2.0
	_banner.size.x = viewport_size.x - BANNER_SIDE_MARGIN * 2.0
	_banner.reset_size()
	var banner_height := _banner.size.y
	var target_is_low := _hole.get_center().y > viewport_size.y * 0.5
	var desired_center_y: float
	if target_is_low:
		desired_center_y = _hole.position.y - BANNER_TARGET_GAP - banner_height * 0.5
	else:
		desired_center_y = _hole.end.y + BANNER_TARGET_GAP + banner_height * 0.5
	var min_center_y := viewport_size.y * BANNER_CENTER_MIN_RATIO
	var max_center_y := viewport_size.y * BANNER_CENTER_MAX_RATIO
	var banner_center_y := clampf(desired_center_y, min_center_y, max_center_y)
	_banner.position = Vector2(
		BANNER_SIDE_MARGIN,
		banner_center_y - banner_height * 0.5
	)


func _draw() -> void:
	if _target == null:
		return
	var width := size.x if size.x > 0.0 else get_viewport_rect().size.x
	var height := size.y if size.y > 0.0 else get_viewport_rect().size.y
	draw_rect(Rect2(0.0, 0.0, width, _hole.position.y), DIM, true)
	draw_rect(Rect2(0.0, _hole.end.y, width, height - _hole.end.y), DIM, true)
	draw_rect(Rect2(0.0, _hole.position.y, _hole.position.x, _hole.size.y), DIM, true)
	draw_rect(Rect2(_hole.end.x, _hole.position.y, width - _hole.end.x, _hole.size.y),
		DIM, true)
	var pulse := 0.55 + 0.25 * sin(_time * 5.0)
	draw_rect(_hole.grow(7.0), Color(ACCENT, 0.20), false, 12.0)
	draw_rect(_hole, Color(ACCENT, pulse), false, 4.0)
	var corner := minf(28.0, minf(_hole.size.x, _hole.size.y) * 0.22)
	var color := Color(ACCENT, 0.95)
	for point in [_hole.position, Vector2(_hole.end.x, _hole.position.y),
			Vector2(_hole.position.x, _hole.end.y), _hole.end]:
		var horizontal := 1.0 if point.x == _hole.position.x else -1.0
		var vertical := 1.0 if point.y == _hole.position.y else -1.0
		draw_line(point, point + Vector2(corner * horizontal, 0.0), color, 5.0, true)
		draw_line(point, point + Vector2(0.0, corner * vertical), color, 5.0, true)
