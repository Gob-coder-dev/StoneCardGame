## Glisser une carte de la main vers le plateau, au doigt ou à la souris.
## Une copie de la carte suit le pointeur ; la case libre la plus proche de
## cette copie s'éclaire, et relâcher y demande la pose. Aucune règle ici :
## BoardController dit quelles cases acceptent la carte.
extends Control

signal drag_started(stone_id: String)
signal drop_requested(stone_id: String, row: int, col: int)

const Gesture := preload("res://scripts/ui/input/DragGesture.gd")
## Au doigt, la copie est levée au-dessus du doigt pour rester visible :
## décalage vertical en fraction de sa taille. La souris la garde centrée.
const TOUCH_LIFT: float = 0.45
const GHOST_OPACITY: float = 0.92
## Opacité de la carte restée dans la main pendant le glissement.
const SOURCE_OPACITY: float = 0.35
const NO_CELL := Vector2i(-1, -1)

var _board: BoardView
var _accepts: Callable
var _gesture := Gesture.new()
var _stone_id: String = ""
var _source: StoneCard = null
var _ghost: StoneCard = null
var _lift: float = 0.0
var _target := NO_CELL


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 50


## accepts(stone_id, row, col) -> bool : vrai si la carte peut être posée là.
func setup(board: BoardView, accepts: Callable) -> void:
	_board = board
	_accepts = accepts


## Commence à suivre l'appui posé sur une carte de la main. Le glissement ne
## démarre qu'au-delà du seuil d'appui ; sinon l'appui reste une sélection.
func begin(stone_id: String, card: StoneCard, pointer: int, canvas_position: Vector2) -> void:
	_end()
	_stone_id = stone_id
	_source = card
	_lift = 0.0 if pointer == Gesture.MOUSE_POINTER else TOUCH_LIFT
	_gesture.begin(pointer, canvas_position)


func is_dragging() -> bool:
	return _gesture.dragging


func _input(event: InputEvent) -> void:
	match _gesture.update(event):
		Gesture.Result.STARTED:
			_start_drag()
			_follow()
		Gesture.Result.MOVED:
			_follow()
		Gesture.Result.RELEASED:
			_follow()
			var stone_id := _stone_id
			var target := _target
			_end()
			if target != NO_CELL:
				drop_requested.emit(stone_id, target.x, target.y)
		Gesture.Result.CANCELED:
			_end()


func _start_drag() -> void:
	if is_instance_valid(_source):
		# Le glissement remplace l'appui : la carte ne sera pas sélectionnée.
		_source.notification(Control.NOTIFICATION_SCROLL_BEGIN)
		_source.modulate.a = SOURCE_OPACITY
	_ghost = StoneCard.new()
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.modulate.a = GHOST_OPACITY
	var cell := _board.slot_at(0, 0)
	_ghost.size = cell.size * _board.get_global_transform_with_canvas().get_scale() \
		/ get_global_transform_with_canvas().get_scale()
	add_child(_ghost)
	_ghost.setup(StoneLoader.get_stone(_stone_id), StoneCard.OWNER_HUMAN)
	drag_started.emit(_stone_id)


## Place la copie sous le pointeur et éclaire la case visée.
func _follow() -> void:
	if _ghost == null:
		return
	var local := get_global_transform_with_canvas().affine_inverse() * _gesture.position
	_ghost.position = local - _ghost.size * 0.5 - Vector2(0.0, _ghost.size.y * _lift)
	var ghost_center := get_global_transform_with_canvas() * (_ghost.position + _ghost.size * 0.5)
	var target := _board.nearest_cell(ghost_center,
		func(row: int, col: int) -> bool: return _accepts.call(_stone_id, row, col))
	if target != _target:
		_target = target
		_board.set_drop_target(_target)


func cancel() -> void:
	_end()


func _end() -> void:
	_gesture.cancel()
	if is_instance_valid(_source):
		_source.modulate.a = 1.0
	_source = null
	if is_instance_valid(_ghost):
		remove_child(_ghost)
		_ghost.queue_free()
	_ghost = null
	if _target != NO_CELL and is_instance_valid(_board):
		_board.set_drop_target(NO_CELL)
	_target = NO_CELL
	_stone_id = ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
		or what == NOTIFICATION_EXIT_TREE:
		_end()
