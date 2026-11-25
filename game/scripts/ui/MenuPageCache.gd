## Prépare les voisins pendant les périodes sans geste et conserve leurs vues.
## Les pages cachées restent dans l’arbre pour leur layout, sans traitement ni
## vidéo. Le cache est vidé à la sortie des menus et limité aux deux voisins.
extends Node

const Routes := preload("res://scripts/ui/GameRoutes.gd")
const Calendar := preload("res://scripts/domain/quests/QuestCalendar.gd")
const CHECK_INTERVAL := 0.25
const BUILD_INTERVAL := 0.08

var _pages: Dictionary[String, Control] = {}
var _keys: Dictionary[String, Array] = {}
var _wanted: Array[String] = []
var _can_prepare: Callable
var _active: Control
var _elapsed := 0.0
var _shop_rotation_seconds := 1


func setup(can_prepare: Callable) -> void:
	_can_prepare = can_prepare
	_shop_rotation_seconds = maxi(1, int(EconomyConfig.get_config().get("shop_rotation_seconds", 10800)))
	get_tree().scene_changed.connect(synchronize)
	set_process(false)


func synchronize() -> void:
	var scene := get_tree().current_scene as Control
	if scene == null or not Routes.MAIN_MENUS.has(scene.scene_file_path):
		clear()
		return
	_active = scene
	_wanted.clear()
	var index := Routes.MAIN_MENUS.find(scene.scene_file_path)
	for neighbor in [index - 1, index + 1]:
		if neighbor >= 0 and neighbor < Routes.MAIN_MENUS.size():
			_wanted.append(Routes.MAIN_MENUS[neighbor])
	for path in _pages.keys():
		if not _wanted.has(path) or not is_instance_valid(_pages[path]) or _keys[path] != _state_key(path):
			_discard(path)
	_elapsed = 0.0
	set_process(true)


func take(path: String) -> Control:
	if _pages.has(path):
		if is_instance_valid(_pages[path]) and _keys[path] == _state_key(path):
			var page := _pages[path]
			_pages.erase(path)
			_keys.erase(path)
			return page
		_discard(path)
	# Premier geste très précoce, ou navigation directe vers une page éloignée.
	var packed := load(path) as PackedScene
	return _create_page(packed) if packed != null else null


func keep(page: Control) -> void:
	var path := page.scene_file_path
	if _pages.has(path):
		_discard(path)
	page.set_meta("menu_preview", true)
	page.process_mode = Node.PROCESS_MODE_DISABLED
	page.hide()
	page.position.x = 0.0
	page.get_node("BottomNav").hide()
	if page.has_method("menu_page_deactivated"):
		page.menu_page_deactivated()
	_pages[path] = page
	_keys[path] = _state_key(path)


func clear() -> void:
	set_process(false)
	_active = null
	_wanted.clear()
	for path in _pages.keys():
		_discard(path)


func _discard(path: String) -> void:
	var page := _pages[path]
	_pages.erase(path)
	_keys.erase(path)
	if is_instance_valid(page):
		page.queue_free()


func _state_key(path: String) -> Array:
	# Les règles conservent l’onglet consulté malgré une récompense récoltée.
	if path == Routes.HOW_TO_PLAY:
		return [PlayerData.player_god_id]
	var period := 0
	if path == Routes.SHOP:
		period = floori(Time.get_unix_time_from_system() / _shop_rotation_seconds)
	elif path == Routes.QUESTS:
		period = Calendar.today()
	return [PlayerData.profile_revision(), period]


func _process(delta: float) -> void:
	if not _can_prepare.call():
		_elapsed = 0.0
		return
	_elapsed += delta
	if _elapsed < BUILD_INTERVAL:
		return
	if _active == null or get_tree().current_scene != _active:
		synchronize()
		return
	for path in _wanted:
		if not _pages.has(path):
			# Les Controls sont construits sur le thread principal, un voisin
			# par frame, après un délai sans geste ni transition.
			keep(_create_page(load(path) as PackedScene))
			_elapsed = 0.0
			return
	if _elapsed >= CHECK_INTERVAL:
		synchronize()


func _create_page(packed: PackedScene) -> Control:
	var page := packed.instantiate() as Control
	page.set_meta("menu_preview", true)
	page.process_mode = Node.PROCESS_MODE_DISABLED
	page.hide()
	get_tree().root.add_child(page)
	page.get_node("BottomNav").hide()
	return page


func _exit_tree() -> void:
	clear()
