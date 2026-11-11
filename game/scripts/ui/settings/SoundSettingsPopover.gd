## Réglages audio compacts de l'accueil.
##
## Ce composant ne connaît ni les lecteurs ni le stockage : il reflète le
## service Audio et reste responsable uniquement de l'ouverture et du layout.
class_name SoundSettingsPopover
extends Control

const OPEN_ICON: Texture2D = preload("res://assets/ui/sound.svg")
const MUTED_ICON: Texture2D = preload("res://assets/ui/sound-muted.svg")

@onready var dismiss_button: Button = $DismissButton
@onready var toggle_button: Button = $ToggleButton
@onready var panel: PanelContainer = $Panel
@onready var music_slider: HSlider = $Panel/Content/MusicSlider
@onready var music_value: Label = $Panel/Content/MusicHeader/Value
@onready var sfx_slider: HSlider = $Panel/Content/SfxSlider
@onready var sfx_value: Label = $Panel/Content/SfxHeader/Value

var _anchor_control: Control = null
var _syncing := false


func _ready() -> void:
	Audio.set_button_silent(dismiss_button)
	toggle_button.pressed.connect(toggle)
	dismiss_button.pressed.connect(close)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	sfx_slider.drag_ended.connect(_on_sfx_drag_ended)
	Audio.volume_changed.connect(_on_service_volume_changed)
	resized.connect(_reposition)
	_sync_from_service()
	_set_open(false, false)


## Positionne le bouton sous une commande existante sans déplacer cette
## dernière ni modifier sa hiérarchie (important pour les ancres du tutoriel).
func anchor_below(control: Control) -> void:
	if is_instance_valid(_anchor_control) \
			and _anchor_control.resized.is_connected(_reposition):
		_anchor_control.resized.disconnect(_reposition)
	_anchor_control = control
	if is_instance_valid(_anchor_control):
		_anchor_control.resized.connect(_reposition)
	_reposition.call_deferred()


func is_open() -> bool:
	return panel.visible


func open() -> void:
	_set_open(true)


func close() -> void:
	_set_open(false)


func toggle() -> void:
	_set_open(not is_open())


func _set_open(opened: bool, focus: bool = true) -> void:
	var was_open := panel.visible
	panel.visible = opened
	dismiss_button.visible = opened
	toggle_button.button_pressed = opened
	if opened:
		_sync_from_service()
		_reposition()
		if focus:
			music_slider.grab_focus()
	elif focus:
		toggle_button.grab_focus()
	if was_open and not opened:
		Audio.flush_volume_settings()


func _sync_from_service() -> void:
	_syncing = true
	music_slider.value = Audio.music_volume_percent()
	sfx_slider.value = Audio.sfx_volume_percent()
	_refresh_value_labels()
	_refresh_icon()
	_syncing = false


func _on_music_changed(value: float) -> void:
	if not _syncing:
		Audio.set_music_volume_percent(value)
	_refresh_value_labels()
	_refresh_icon()


func _on_sfx_changed(value: float) -> void:
	if not _syncing:
		Audio.set_sfx_volume_percent(value)
	_refresh_value_labels()
	_refresh_icon()


func _on_sfx_drag_ended(changed: bool) -> void:
	if changed and Audio.sfx_volume_percent() > 0.0:
		Audio.play_sfx(AudioCatalog.SFX_BUTTON_2)


func _on_service_volume_changed(_bus_name: StringName, _percent: float) -> void:
	if not is_node_ready():
		return
	_sync_from_service()


func _refresh_value_labels() -> void:
	music_value.text = "%d %%" % int(round(music_slider.value))
	sfx_value.text = "%d %%" % int(round(sfx_slider.value))


func _refresh_icon() -> void:
	var muted := is_zero_approx(music_slider.value) \
		and is_zero_approx(sfx_slider.value)
	toggle_button.icon = MUTED_ICON if muted else OPEN_ICON
	toggle_button.tooltip_text = "Réactiver le son" if muted else "Réglages du son"


func _reposition() -> void:
	if not is_node_ready() or not is_instance_valid(_anchor_control):
		return
	var relative := get_global_transform().affine_inverse() \
		* _anchor_control.get_global_transform()
	var anchor_top_left := relative * Vector2.ZERO
	var anchor_bottom_right := relative * _anchor_control.size
	var button_position := Vector2(anchor_top_left.x,
		anchor_bottom_right.y + UITheme.GAP_SMALL)
	var right_limit := maxf(UITheme.MARGIN_SCREEN,
		size.x - UITheme.MARGIN_SCREEN - toggle_button.size.x)
	button_position.x = clampf(button_position.x,
		UITheme.MARGIN_SCREEN, right_limit)
	toggle_button.position = button_position

	var panel_position := Vector2(button_position.x,
		button_position.y + toggle_button.size.y + UITheme.GAP_SMALL)
	panel_position.x = clampf(panel_position.x, UITheme.MARGIN_SCREEN,
		maxf(UITheme.MARGIN_SCREEN,
			size.x - UITheme.MARGIN_SCREEN - panel.size.x))
	panel_position.y = minf(panel_position.y,
		maxf(UITheme.MARGIN_SCREEN, size.y - UITheme.MARGIN_SCREEN - panel.size.y))
	panel.position = panel_position


func _exit_tree() -> void:
	if is_instance_valid(_anchor_control) \
			and _anchor_control.resized.is_connected(_reposition):
		_anchor_control.resized.disconnect(_reposition)
