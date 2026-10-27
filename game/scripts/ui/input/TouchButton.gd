extends Button
## Conserve les boutons natifs (souris, clavier, manette, tactile), mais
## annule définitivement leur appui dès que le doigt ou la souris glisse.

const Gesture := preload("res://scripts/ui/input/TapGesture.gd")
var _tap := Gesture.new()
var _touch_mode: bool = false
var _mouse_styles: Dictionary = {}
var _mouse_colors: Dictionary = {}
var _mouse_button_mask: int = MOUSE_BUTTON_MASK_LEFT


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE


func _gui_input(event: InputEvent) -> void:
	if _tap.update(event, self) == Gesture.Result.CANCELED:
		# Annule l'appui natif sans consommer l'événement : le ScrollContainer
		# doit encore recevoir le mouvement ET le relâchement du doigt.
		notification(Control.NOTIFICATION_SCROLL_BEGIN)


func _input(event: InputEvent) -> void:
	if (event is InputEventMouseMotion or event is InputEventMouseButton) and event.device == Gesture.EMULATED_DEVICE:
		_set_touch_mode(true)
	elif event is InputEventScreenTouch and event.pressed and event.device != Gesture.EMULATED_DEVICE:
		_set_touch_mode(true)
	elif (event is InputEventMouseMotion or event is InputEventMouseButton) and event.device != Gesture.EMULATED_DEVICE:
		_set_touch_mode(false)
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_set_touch_mode(false)


func _set_touch_mode(enabled: bool) -> void:
	if enabled == _touch_mode:
		return
	_touch_mode = enabled
	if enabled:
		# Godot 4.7 traite à la fois le toucher natif et son clic émulé.
		# Seul le toucher doit activer le bouton ; la souris émulée continue
		# à remonter au ScrollContainer pour son défilement natif.
		_mouse_button_mask = button_mask
		button_mask = 0
		# Le moteur a besoin de la souris émulée pour son défilement, mais
		# son survol ne doit pas illuminer les boutons traversés par le doigt.
		for key in ["hover", "hover_pressed", "focus"]:
			_mouse_styles[key] = get_theme_stylebox(key) if has_theme_stylebox_override(key) else null
		for key in ["font_hover_color", "font_hover_pressed_color"]:
			_mouse_colors[key] = get_theme_color(key) if has_theme_color_override(key) else null
		add_theme_stylebox_override("hover", get_theme_stylebox("normal"))
		add_theme_stylebox_override("hover_pressed", get_theme_stylebox("pressed"))
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		add_theme_color_override("font_hover_color", get_theme_color("font_color"))
		add_theme_color_override("font_hover_pressed_color", get_theme_color("font_pressed_color"))
	else:
		button_mask = _mouse_button_mask
		for key in _mouse_styles:
			if _mouse_styles[key] == null:
				remove_theme_stylebox_override(key)
			else:
				add_theme_stylebox_override(key, _mouse_styles[key])
		for key in _mouse_colors:
			if _mouse_colors[key] == null:
				remove_theme_color_override(key)
			else:
				add_theme_color_override(key, _mouse_colors[key])
		_mouse_styles.clear()
		_mouse_colors.clear()


func _notification(what: int) -> void:
	if what == Control.NOTIFICATION_SCROLL_BEGIN:
		_tap.cancel()
	elif what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_EXIT_TREE:
		_tap.reset()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_tap.reset()
		notification(Control.NOTIFICATION_SCROLL_BEGIN)
