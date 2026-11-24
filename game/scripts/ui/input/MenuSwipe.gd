## Reconnaît un glissement horizontal et verrouille son axe jusqu’au relâchement.
## Les positions et distances sont exprimées dans le canevas du viewport.
extends RefCounted

enum Result { NONE, STARTED, MOVED, RELEASED, CANCELED }

const NO_POINTER := -1
const AXIS_RATIO := 1.4
var pointer := NO_POINTER
var origin := Vector2.ZERO
var distance := 0.0
var dragging := false
var _rejected := false


func begin(index: int, point: Vector2) -> void:
	pointer = index
	origin = point
	distance = 0.0
	dragging = false
	_rejected = false


func update(event: InputEvent) -> Result:
	if pointer == NO_POINTER or event.device == -1:
		return Result.NONE
	if event is InputEventScreenDrag and event.index == pointer:
		return _move(event.position)
	if event is InputEventScreenTouch and not event.pressed and event.index == pointer:
		pointer = NO_POINTER
		if not dragging:
			return Result.NONE
		distance = event.position.x - origin.x
		dragging = false
		return Result.CANCELED if event.canceled else Result.RELEASED
	return Result.NONE


func _move(point: Vector2) -> Result:
	if _rejected:
		return Result.NONE
	var delta := point - origin
	if dragging:
		distance = delta.x
		return Result.MOVED
	if delta.length() <= UITheme.TOUCH_SLOP:
		return Result.NONE
	if absf(delta.y) > absf(delta.x):
		_rejected = true
	elif absf(delta.x) > absf(delta.y) * AXIS_RATIO:
		dragging = true
		distance = delta.x
		return Result.STARTED
	return Result.NONE


func reset() -> void:
	pointer = NO_POINTER
	dragging = false
	_rejected = false
	distance = 0.0
