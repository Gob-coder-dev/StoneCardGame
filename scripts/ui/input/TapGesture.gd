@tool
class_name TapGesture
extends RefCounted
## Reconnaît un appui au relâchement, sans confondre déplacement et clic.
## Les positions sont mesurées dans le canevas, même si le contenu défile.

enum Result { NONE, TAP, CANCELED }

const NO_POINTER: int = -1
const MOUSE_POINTER: int = -2
const EMULATED_DEVICE: int = -1

var _pointer: int = NO_POINTER
var _origin := Vector2.ZERO
var _canceled: bool = false


func update(event: InputEvent, control: Control) -> Result:
	if event.device == EMULATED_DEVICE:
		return Result.NONE
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin(event.index, event.position, control)
		elif event.index == _pointer:
			return _finish(event.position, control, event.canceled)
	elif event is InputEventScreenDrag and event.index == _pointer:
		return _move(event.position, control)
	elif event is InputEventMouseButton and event.device != EMULATED_DEVICE:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin(MOUSE_POINTER, event.position, control)
			elif _pointer == MOUSE_POINTER:
				return _finish(event.position, control, event.canceled)
	elif event is InputEventMouseMotion and event.device != EMULATED_DEVICE:
		if _pointer == MOUSE_POINTER:
			return _move(event.position, control)
	return Result.NONE


func cancel() -> void:
	_canceled = true


func reset() -> void:
	_pointer = NO_POINTER
	_canceled = false


func _begin(pointer: int, position: Vector2, control: Control) -> void:
	if _pointer != NO_POINTER:
		return
	_pointer = pointer
	_origin = control.get_global_transform_with_canvas() * position
	_canceled = false


func _move(position: Vector2, control: Control) -> Result:
	var canvas_position := control.get_global_transform_with_canvas() * position
	if not _canceled and canvas_position.distance_to(_origin) > UITheme.TOUCH_SLOP:
		cancel()
		return Result.CANCELED
	return Result.NONE


func _finish(position: Vector2, control: Control, canceled: bool) -> Result:
	_move(position, control)
	var tapped := not canceled and not _canceled and Rect2(Vector2.ZERO, control.size).has_point(position)
	reset()
	return Result.TAP if tapped else Result.CANCELED
