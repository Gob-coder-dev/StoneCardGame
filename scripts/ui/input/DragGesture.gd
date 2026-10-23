## Suit un pointeur après un appui : doigt (par son index) ou souris physique.
## Le glissement commence au-delà de UITheme.TOUCH_SLOP, le même seuil qui
## annule un appui : un petit mouvement reste donc un simple appui.
## Les positions sont dans le canevas, comme celles reçues par _input().
extends RefCounted

enum Result { NONE, STARTED, MOVED, RELEASED, CANCELED }

const NO_POINTER: int = -1
const MOUSE_POINTER: int = -2
## Les clics souris émulés depuis le tactile sont ignorés : le toucher natif suffit.
const EMULATED_DEVICE: int = -1

## Position actuelle du pointeur dans le canevas.
var position := Vector2.ZERO
## Vrai une fois le seuil de glissement franchi.
var dragging: bool = false
var _pointer: int = NO_POINTER
var _origin := Vector2.ZERO


## Pointeur d'un appui natif : index du doigt, MOUSE_POINTER pour le clic gauche
## de la souris physique, NO_POINTER pour tout autre événement.
static func pressed_pointer(event: InputEvent) -> int:
	if event.device == EMULATED_DEVICE:
		return NO_POINTER
	if event is InputEventScreenTouch and event.pressed:
		return event.index
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return MOUSE_POINTER
	return NO_POINTER


func is_active() -> bool:
	return _pointer != NO_POINTER


func begin(pointer: int, canvas_position: Vector2) -> void:
	_pointer = pointer
	_origin = canvas_position
	position = canvas_position
	dragging = false


func cancel() -> void:
	_pointer = NO_POINTER
	dragging = false


## STARTED au franchissement du seuil, MOVED ensuite. Au relâchement : RELEASED
## après un vrai glissement, CANCELED sinon ou si le système annule le toucher.
func update(event: InputEvent) -> Result:
	if _pointer == NO_POINTER or event.device == EMULATED_DEVICE:
		return Result.NONE
	if _pointer == MOUSE_POINTER:
		if event is InputEventMouseMotion:
			return _move(event.position)
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			return _finish(event.position, false)
		return Result.NONE
	if event is InputEventScreenDrag and event.index == _pointer:
		return _move(event.position)
	if event is InputEventScreenTouch and event.index == _pointer and not event.pressed:
		return _finish(event.position, event.canceled)
	return Result.NONE


func _move(canvas_position: Vector2) -> Result:
	position = canvas_position
	if dragging:
		return Result.MOVED
	if position.distance_to(_origin) > UITheme.TOUCH_SLOP:
		dragging = true
		return Result.STARTED
	return Result.NONE


func _finish(canvas_position: Vector2, canceled: bool) -> Result:
	position = canvas_position
	var was_dragging := dragging
	cancel()
	return Result.RELEASED if was_dragging and not canceled else Result.CANCELED
