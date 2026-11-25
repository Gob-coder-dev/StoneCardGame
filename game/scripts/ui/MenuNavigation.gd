## Composition transitoire de deux vrais menus. Le voisin reste inactif
## jusqu’à validation. Chaque page possède les règles de ses fenêtres ouvertes.
extends Node

const Routes := preload("res://scripts/ui/GameRoutes.gd")
const Gesture := preload("res://scripts/ui/input/MenuSwipe.gd")
const PageCache := preload("res://scripts/ui/MenuPageCache.gd")
const PAGES := Routes.MAIN_MENUS
const COMMIT_DISTANCE := 0.20
const SETTLE_SECONDS := 0.18
const MIN_SETTLE_SECONDS := 0.06
const TAP_TRAVEL := 0.20

var _gesture := Gesture.new()
var _current: Control
var _incoming: Control
var _nav: Control
var _nav_x := 0.0
var _nav_z := 0
var _offset := 0.0
var _direction := 0
var _target := -1
var _origin_index := -1
var _tween: Tween
var _shield: CanvasLayer
var _process_mode: ProcessMode
var _blocked_press := false
var _cache: PageCache


func _ready() -> void:
	_cache = PageCache.new()
	add_child(_cache)
	_cache.setup(func(): return _current == null and _gesture.pointer == Gesture.NO_POINTER)
	_shield = CanvasLayer.new()
	_shield.layer = 90
	add_child(_shield)
	var blocker := Control.new()
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shield.add_child(blocker)
	_shield.hide()
	get_tree().root.size_changed.connect(cancel)


## Renvoie true lorsque ce coordinateur prend en charge la navigation.
func navigate_to(path: String) -> bool:
	var scene := get_tree().current_scene
	if not scene is Control or not PAGES.has(scene.scene_file_path) or not PAGES.has(path):
		return false
	if _current != null or scene.scene_file_path == path:
		return true
	_prepare(scene)
	_target = PAGES.find(path)
	_direction = 1 if _target < _origin_index else -1
	if not _load_neighbor():
		_clear()
		return false
	_freeze()
	_set_offset(0.0)
	_settle(true, TAP_TRAVEL)
	return true


func _input(event: InputEvent) -> void:
	# L’émulation souris précède le toucher natif et peut déjà fermer
	# une fenêtre. Ce même appui doit rester réservé à sa fermeture.
	if event is InputEventMouseButton and event.device == -1 and event.pressed:
		_blocked_press = not _can_begin(event.position)
		return
	if _current != null and event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
		return
	if _tween != null and _tween.is_running():
		if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouse:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch and event.pressed and event.device != -1:
		if not _blocked_press and _gesture.pointer == Gesture.NO_POINTER and _can_begin(event.position):
			_gesture.begin(event.index, event.position)
	var result := _gesture.update(event)
	if event is InputEventScreenTouch and not event.pressed:
		_blocked_press = false
	match result:
		Gesture.Result.STARTED:
			_prepare(get_tree().current_scene)
			_direction = 1 if _gesture.distance > 0.0 else -1
			_target = _origin_index - _direction
			if _target >= 0 and _target < PAGES.size():
				if not _load_neighbor():
					cancel()
					return
			_freeze()
			_set_offset(_gesture.distance)
		Gesture.Result.MOVED:
			_set_offset(_gesture.distance)
		Gesture.Result.RELEASED, Gesture.Result.CANCELED:
			var commit := result == Gesture.Result.RELEASED and _incoming != null \
				and _gesture.distance * _direction >= _current.size.x * COMMIT_DISTANCE
			_settle(commit, SETTLE_SECONDS)
	if result != Gesture.Result.NONE:
		get_viewport().set_input_as_handled()


func _can_begin(point: Vector2) -> bool:
	var scene := get_tree().current_scene
	if not scene is Control or not PAGES.has(scene.scene_file_path):
		return false
	if StoryService.is_playing() or StoryService.is_tutorial_running():
		return false
	var nav := scene.get_node_or_null("BottomNav") as Control
	if nav == null or nav.get_global_rect().has_point(point):
		return false
	return not scene.has_method("menu_swipe_allowed") or scene.menu_swipe_allowed()


func _prepare(scene: Control) -> void:
	_current = scene
	_origin_index = PAGES.find(scene.scene_file_path)
	_nav = scene.get_node("BottomNav")
	_nav_x = _nav.position.x
	_nav_z = _nav.z_index
	_process_mode = scene.process_mode
	_current.tree_exiting.connect(_on_current_exiting, CONNECT_ONE_SHOT)


func _load_neighbor() -> bool:
	_incoming = _cache.take(PAGES[_target])
	if _incoming == null:
		return false
	_incoming.position.x = -_direction * _current.size.x
	_incoming.show()
	return true


func _freeze() -> void:
	_current.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
	_current.process_mode = Node.PROCESS_MODE_DISABLED
	_nav.z_index = 100
	_shield.show()


func _set_offset(value: float) -> void:
	if not is_instance_valid(_current):
		return
	if Accessibility.reduced_motion:
		return
	var width := _current.size.x
	_offset = clampf(value * _direction, 0.0, width) * _direction
	if _incoming == null:
		_offset = 0.0
	_current.position.x = _offset
	_nav.position.x = _nav_x - _offset
	if _incoming != null:
		_incoming.position.x = _offset - _direction * width


func _settle(commit: bool, duration: float) -> void:
	_gesture.reset()
	if Accessibility.reduced_motion:
		_finish(commit)
		return
	_tween = create_tween()
	var endpoint := _current.size.x * _direction if commit else 0.0
	var remaining := absf(endpoint - _offset) / _current.size.x
	var travel_time := clampf(duration * remaining, MIN_SETTLE_SECONDS, duration)
	_tween.tween_method(_set_offset, _offset, endpoint, travel_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_finish.bind(commit))


func _finish(commit: bool) -> void:
	var previous := _current
	if previous.tree_exiting.is_connected(_on_current_exiting):
		previous.tree_exiting.disconnect(_on_current_exiting)
	if commit:
		var next := _incoming
		_incoming = null
		next.position.x = 0.0
		next.remove_meta("menu_preview")
		next.process_mode = Node.PROCESS_MODE_INHERIT
		get_tree().current_scene = next
		next.get_node("BottomNav").show()
		next.get_node("BottomNav").register_story_anchors()
		_restore_current()
		_cache.keep(previous)
		_clear()
		get_tree().scene_changed.emit()
		if next.has_method("menu_page_activated"):
			next.menu_page_activated()
		next.get_node("BottomNav").menu_page_activated()
	else:
		_restore_current()
		_clear()


func cancel() -> void:
	if _tween != null:
		_tween.kill()
	if is_instance_valid(_current):
		_restore_current()
		if _current.tree_exiting.is_connected(_on_current_exiting):
			_current.tree_exiting.disconnect(_on_current_exiting)
	_clear()


func cancel_for_back() -> bool:
	if _current == null:
		return false
	cancel()
	return true


func _restore_current() -> void:
	_current.position.x = 0.0
	_nav.position.x = _nav_x
	_nav.z_index = _nav_z
	_current.process_mode = _process_mode


func _clear() -> void:
	_gesture.reset()
	if is_instance_valid(_current) and _current.tree_exiting.is_connected(_on_current_exiting):
		_current.tree_exiting.disconnect(_on_current_exiting)
	if is_instance_valid(_incoming):
		_cache.keep(_incoming)
	_incoming = null
	_current = null
	_nav = null
	_offset = 0.0
	_blocked_press = false
	_tween = null
	if _shield != null:
		_shield.hide()


func _on_current_exiting() -> void:
	if _tween != null:
		_tween.kill()
	_clear()
	_cache.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel()
