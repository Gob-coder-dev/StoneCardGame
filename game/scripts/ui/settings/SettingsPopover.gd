## Panneau des réglages de l'accueil. Les services Audio et Accessibility
## appliquent et enregistrent les préférences.
class_name SettingsPopover
extends Control

@onready var dismiss_button: Button = $DismissButton
@onready var panel: PanelContainer = $Panel
@onready var music_slider: HSlider = $Panel/Content/Sound/MusicSlider
@onready var music_value: Label = $Panel/Content/Sound/MusicHeader/Value
@onready var sfx_slider: HSlider = $Panel/Content/Sound/SfxSlider
@onready var sfx_value: Label = $Panel/Content/Sound/SfxHeader/Value
@onready var reduced_motion: CheckButton = $Panel/Content/Accessibility/ReducedMotion
@onready var motion_description: Label = $Panel/Content/Accessibility/Description
@onready var save_error: Label = $Panel/Content/Accessibility/SaveError
@onready var close_button: Button = $Panel/Content/CloseButton

var _opener: Button
var _syncing := false


func _ready() -> void:
	Audio.set_button_silent(dismiss_button)
	dismiss_button.pressed.connect(close)
	close_button.pressed.connect(close)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	sfx_slider.drag_ended.connect(_on_sfx_drag_ended)
	reduced_motion.toggled.connect(_on_reduced_motion_toggled)
	reduced_motion.accessibility_description = motion_description.text
	_set_focus_order([music_slider, sfx_slider, reduced_motion, close_button])
	panel.minimum_size_changed.connect(panel.reset_size, CONNECT_DEFERRED)
	panel.resized.connect(_reposition)
	Audio.volume_changed.connect(_on_service_volume_changed)
	resized.connect(_reposition)
	_sync_from_service()


func setup(opener: Button) -> void:
	_opener = opener
	_opener.pressed.connect(open)


func is_open() -> bool:
	return panel.visible


func open() -> void:
	_set_open(true)


func close() -> void:
	_set_open(false)


func _set_open(opened: bool) -> void:
	if opened == panel.visible:
		return
	panel.visible = opened
	dismiss_button.visible = opened
	_opener.set_pressed_no_signal(opened)
	if opened:
		_sync_from_service()
		reduced_motion.set_pressed_no_signal(Accessibility.reduced_motion)
		save_error.hide()
		panel.reset_size.call_deferred()
		_reposition()
		music_slider.grab_focus()
	else:
		_opener.grab_focus()
		Audio.flush_volume_settings()


func _set_focus_order(controls: Array[Control]) -> void:
	for index in range(controls.size()):
		var control := controls[index]
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = control.get_path_to(controls[index - 1])
		control.focus_neighbor_bottom = control.focus_next
		control.focus_neighbor_top = control.focus_previous
		control.focus_neighbor_left = ^"."
		control.focus_neighbor_right = ^"."


func _sync_from_service() -> void:
	_syncing = true
	music_slider.value = Audio.music_volume_percent()
	sfx_slider.value = Audio.sfx_volume_percent()
	_refresh_value_labels()
	_syncing = false


func _on_music_changed(value: float) -> void:
	if not _syncing:
		Audio.set_music_volume_percent(value)
	_refresh_value_labels()


func _on_sfx_changed(value: float) -> void:
	if not _syncing:
		Audio.set_sfx_volume_percent(value)
	_refresh_value_labels()


func _on_sfx_drag_ended(changed: bool) -> void:
	if changed and Audio.sfx_volume_percent() > 0.0:
		Audio.play_sfx(AudioCatalog.SFX_BUTTON_2)


func _on_reduced_motion_toggled(enabled: bool) -> void:
	save_error.visible = Accessibility.set_reduced_motion(enabled) != OK
	if save_error.visible:
		reduced_motion.set_pressed_no_signal(Accessibility.reduced_motion)


func _on_service_volume_changed(_bus_name: StringName, _percent: float) -> void:
	if not is_node_ready():
		return
	_sync_from_service()


func _refresh_value_labels() -> void:
	music_value.text = "%d %%" % int(round(music_slider.value))
	sfx_value.text = "%d %%" % int(round(sfx_slider.value))


func _reposition() -> void:
	if not is_instance_valid(_opener) or not panel.visible:
		return
	var relative := get_global_transform().affine_inverse() \
		* _opener.get_global_transform()
	var anchor := relative * Vector2(0.0, _opener.size.y)
	var panel_position := anchor + Vector2(0.0, UITheme.GAP_SMALL)
	panel_position.x = clampf(panel_position.x, UITheme.MARGIN_SCREEN,
		maxf(UITheme.MARGIN_SCREEN,
			size.x - UITheme.MARGIN_SCREEN - panel.size.x))
	panel_position.y = minf(panel_position.y,
		maxf(UITheme.MARGIN_SCREEN, size.y - UITheme.MARGIN_SCREEN - panel.size.y))
	panel.position = panel_position
