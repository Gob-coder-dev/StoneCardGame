## SafeArea.gd
## Autoload : garde les commandes dans la zone utilisable de l'écran.
##
## Les appareils sans découpe (tablettes, ordinateurs) ne voient aucune
## différence : l'inset vaut zéro, donc les offsets de conception sont
## restaurés tels quels. Un téléphone à caméra poinçonnée reçoit uniquement la
## hauteur occupée par la caméra elle-même, jamais toute la barre d'état : en
## plein écran immersif, seule la découpe empiète réellement en haut.
## La marge basse réserve l'emprise de la navigation Android lorsqu'elle apparaît.
##
## Les scènes déclarent leur conteneur principal dans le groupe
## `safe_area_top`. Le service mémorise les offsets d'origine et ajoute
## l'inset : il est donc idempotent, réversible, et se met à jour si la zone
## change (rotation, pli, réglage système).
extends Node

const GROUP_TOP: StringName = &"safe_area_top"
const GROUP_LEFT: StringName = &"safe_area_left"
const GROUP_RIGHT: StringName = &"safe_area_right"
const GROUP_BOTTOM: StringName = &"safe_area_bottom"

## Une valeur aberrante de l'OS ne doit jamais écraser la mise en page.
const MAX_SIDE_INSET_RATIO: float = 0.05
const MAX_BOTTOM_INSET_RATIO: float = 0.10
## Sur Android, le rectangle de découpe couvre toute la bande haute (barre
## d'état comprise) : 130 px sur un Redmi 14 Pro, alors que l'objectif n'en
## occupe qu'une quarantaine. Décaler l'interface de toute cette bande vide
## écrase la mise en page pour rien : on ne garde que la hauteur de l'objectif.
const MAX_TOP_INSET: float = 36.0
## Les découpes de la moitié basse de l'écran ne concernent jamais le haut.
const TOP_CUTOUT_LIMIT_RATIO: float = 0.3
## Android peut annoncer ses découpes quelques dixièmes après le lancement :
## on relit la zone pendant les premières secondes pour que le tout premier
## menu soit aligné comme les suivants.
const STARTUP_POLL_SECONDS: float = 6.0
const STARTUP_POLL_INTERVAL: float = 0.5

var _insets := _empty_insets()
var _base_offsets: Dictionary = {}
var _forced_insets: Variant = null
var _poll_left: float = 0.0
var _poll_tick: float = 0.0


func _ready() -> void:
	get_tree().root.size_changed.connect(_refresh)
	get_tree().node_added.connect(_on_node_added)
	_refresh()
	if OS.has_feature("mobile") and OS.get_name() == "Android":
		_poll_left = STARTUP_POLL_SECONDS
		set_process(true)


func _process(delta: float) -> void:
	_poll_left -= delta
	_poll_tick -= delta
	if _poll_tick <= 0.0:
		_poll_tick = STARTUP_POLL_INTERVAL
		_refresh()
	if _poll_left <= 0.0:
		set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_inside_tree():
		_refresh()


func insets() -> Dictionary:
	return _insets.duplicate()


## Valeurs imposées, utilisées par les tests. `null` restaure la lecture
## réelle de l'OS.
func set_insets_for_tests(value: Variant) -> void:
	_forced_insets = value
	_refresh()


func _on_node_added(node: Node) -> void:
	if node is Control and _targets_an_edge(node):
		_apply(node)


func _targets_an_edge(control: Control) -> bool:
	return control.is_in_group(GROUP_TOP) or control.is_in_group(GROUP_LEFT) \
		or control.is_in_group(GROUP_RIGHT) or control.is_in_group(GROUP_BOTTOM)


func _refresh() -> void:
	var next: Dictionary = _forced_insets if _forced_insets != null else _read_os_insets()
	if next == _insets:
		return
	_insets = next
	for control in _base_offsets.keys():
		if is_instance_valid(control):
			_apply(control)
		else:
			_base_offsets.erase(control)


## Les offsets d'origine ne sont enregistrés qu'une fois : appliquer deux fois
## le même inset ne cumule jamais les marges.
func _apply(control: Control) -> void:
	if not _base_offsets.has(control):
		_base_offsets[control] = Vector4(control.offset_left, control.offset_top,
			control.offset_right, control.offset_bottom)
		control.tree_exiting.connect(_forget.bind(control), CONNECT_ONE_SHOT)
	var base: Vector4 = _base_offsets[control]
	control.offset_left = base.x + _inset_for(control, GROUP_LEFT)
	control.offset_top = base.y + _inset_for(control, GROUP_TOP)
	control.offset_right = base.z - _inset_for(control, GROUP_RIGHT)
	control.offset_bottom = base.w - _inset_for(control, GROUP_BOTTOM)


func _inset_for(control: Control, group: StringName) -> float:
	return float(_insets.get(str(group).trim_prefix("safe_area_"), 0.0)) if control.is_in_group(group) else 0.0


func _forget(control: Control) -> void:
	_base_offsets.erase(control)


## L'API renvoie des pixels d'écran, alors que le jeu se place en unités de
## canevas (1080 x 1920, canvas_items + expand) : la conversion est obligatoire.
func _read_os_insets() -> Dictionary:
	if not OS.has_feature("mobile") or OS.get_name() != "Android":
		return _empty_insets()
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var cutouts := DisplayServer.get_display_cutouts()
	var viewport := get_viewport()
	var visible := viewport.get_visible_rect()
	var to_canvas := viewport.get_final_transform().affine_inverse()
	var safe_canvas := to_canvas * safe
	var screen_height := float(DisplayServer.window_get_size().y)
	var camera := cutout_depth(cutouts, screen_height)
	var top := (to_canvas * Vector2(0.0, camera)).y - visible.position.y if camera > 0.0 else 0.0
	var navigation_bottom := to_canvas.basis_xform(Vector2(0.0, _android_navigation_bottom())).y
	return canvas_insets(visible, safe_canvas, top, not cutouts.is_empty(), navigation_bottom)


static func canvas_insets(visible: Rect2, safe: Rect2, top: float, has_cutout: bool,
		navigation_bottom: float = 0.0) -> Dictionary:
	if not safe.has_area() or not visible.intersects(safe):
		safe = visible
	var side_limit := visible.size.x * MAX_SIDE_INSET_RATIO
	var bottom_limit := visible.size.y * MAX_BOTTOM_INSET_RATIO
	return {
		"top": clamp_top(top),
		"left": clampf(roundf(safe.position.x - visible.position.x), 0.0, side_limit) if has_cutout else 0.0,
		"right": clampf(roundf(visible.end.x - safe.end.x), 0.0, side_limit) if has_cutout else 0.0,
		"bottom": clampf(roundf(maxf(visible.end.y - safe.end.y, navigation_bottom)), 0.0, bottom_limit),
	}


## En mode immersif, la zone sûre de Godot ignore les barres système.
## La marge stable d'Android reste disponible sur toutes les API prises en charge.
static func _android_navigation_bottom() -> int:
	if not Engine.has_singleton("AndroidRuntime"):
		return 0
	var activity: Object = Engine.get_singleton("AndroidRuntime").call("getActivity")
	var window: Object = activity.call("getWindow") if activity != null else null
	var decor: Object = window.call("getDecorView") if window != null else null
	var platform_insets: Object = decor.call("getRootWindowInsets") if decor != null else null
	return int(platform_insets.call("getStableInsetBottom")) if platform_insets != null else 0


## Marge haute appliquée : de quoi passer sous l'objectif, jamais plus.
static func clamp_top(value: float) -> float:
	return clampf(roundf(value), 0.0, MAX_TOP_INSET)


## Profondeur réelle de la caméra, en pixels d'écran : le bas de la découpe la
## plus profonde de la moitié haute. Les découpes latérales ou basses ne
## poussent jamais le contenu vers le bas.
static func cutout_depth(cutouts: Array, screen_height: float) -> float:
	var depth := 0.0
	for rect in cutouts:
		var cut := Rect2(rect)
		if cut.size.y <= 0.0 or cut.get_center().y > screen_height * TOP_CUTOUT_LIMIT_RATIO:
			continue
		depth = maxf(depth, cut.end.y)
	return depth


static func _empty_insets() -> Dictionary:
	return {"top": 0.0, "left": 0.0, "right": 0.0, "bottom": 0.0}
