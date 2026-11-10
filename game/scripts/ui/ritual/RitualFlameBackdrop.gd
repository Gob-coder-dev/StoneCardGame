## Flammes procédurales des Rituels. Le premier embrasement recouvre l'écran ;
## les transitions suivantes restent volontairement basses et discrètes.
class_name RitualFlameBackdrop
extends Control

signal covered
signal finished

const FlameShader := preload("res://assets/shaders/ritual_flames.gdshader")

var coverage := 0.0:
	set(value):
		coverage = clampf(value, 0.0, 1.0)
		_sync_material()
var _animating := false
var _full_screen := true:
	set(value):
		_full_screen = value
		_sync_material()
var _surface: ColorRect
var _flame_material: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface = ColorRect.new()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flame_material = ShaderMaterial.new()
	_flame_material.shader = FlameShader
	_surface.material = _flame_material
	add_child(_surface)
	_sync_material()


func ignite_full() -> void:
	await _ignite(true)


func ignite_minor() -> void:
	await _ignite(false)


func _ignite(full_screen: bool) -> void:
	if _animating:
		return
	_animating = true
	_full_screen = full_screen
	visible = true
	coverage = 0.0
	var rise_duration := 0.46 if full_screen else 0.18
	var fall_duration := 0.58 if full_screen else 0.28
	var rise := create_tween()
	rise.tween_property(self, "coverage", 1.0, rise_duration) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await rise.finished
	covered.emit()
	await get_tree().create_timer(0.12 if full_screen else 0.04).timeout
	var fall := create_tween()
	fall.tween_property(self, "coverage", 0.0, fall_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fall.finished
	_animating = false
	visible = false
	finished.emit()


func _sync_material() -> void:
	if _flame_material == null:
		return
	_flame_material.set_shader_parameter("coverage", coverage)
	_flame_material.set_shader_parameter("full_screen", 1.0 if _full_screen else 0.0)
