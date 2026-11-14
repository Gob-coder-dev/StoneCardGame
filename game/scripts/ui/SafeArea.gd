## SafeArea.gd
## Autoload : décale l'interface sous la zone réellement visible de l'écran.
##
## Les appareils sans découpe (tablettes, ordinateurs) ne voient aucune
## différence : l'inset vaut zéro, donc les offsets de conception sont
## restaurés tels quels. Un téléphone à caméra poinçonnée reçoit uniquement la
## hauteur occupée par la caméra elle-même, jamais toute la barre d'état : en
## plein écran immersif, seule la découpe empiète réellement sur l'interface.
##
## Les scènes déclarent leur conteneur principal dans le groupe
## `safe_area_top`. Le service mémorise les offsets d'origine et ajoute
## l'inset : il est donc idempotent, réversible, et se met à jour si la zone
## change (rotation, pli, réglage système).
extends Node

const GROUP_TOP: StringName = &"safe_area_top"
const GROUP_LEFT: StringName = &"safe_area_left"
const GROUP_RIGHT: StringName = &"safe_area_right"

## Une valeur aberrante de l'OS ne doit jamais écraser la mise en page.
const MAX_INSET_RATIO: float = 0.05
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
		or control.is_in_group(GROUP_RIGHT)


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
	control.offset_bottom = base.w


func _inset_for(control: Control, group: StringName) -> float:
	if not control.is_in_group(group):
		return 0.0
	if group == GROUP_TOP:
		return float(_insets["top"])
	if group == GROUP_LEFT:
		return float(_insets["left"])
	return float(_insets["right"])


func _forget(control: Control) -> void:
	_base_offsets.erase(control)


## L'API renvoie des pixels d'écran, alors que le jeu se place en unités de
## canevas (1080 x 1920, canvas_items + expand) : la conversion est obligatoire.
func _read_os_insets() -> Dictionary:
	if not OS.has_feature("mobile") or OS.get_name() != "Android":
		return _empty_insets()
	# Sans découpe, l'API a déjà renvoyé des rectangles faux selon les versions
	# d'Android : on ne touche à rien tant qu'aucune caméra n'empiète sur l'écran.
	if DisplayServer.get_display_cutouts().is_empty():
		return _empty_insets()
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return _empty_insets()
	var viewport := get_viewport()
	var visible := viewport.get_visible_rect()
	var to_canvas := viewport.get_final_transform().affine_inverse()
	var safe_canvas := to_canvas * safe
	var limit := visible.size * MAX_INSET_RATIO
	var screen_height := float(DisplayServer.window_get_size().y)
	var camera := cutout_depth(DisplayServer.get_display_cutouts(), screen_height)
	var top := (to_canvas * Vector2(0.0, camera)).y - visible.position.y
	return {
		"top": clamp_top(top),
		"left": clampf(roundf(safe_canvas.position.x - visible.position.x), 0.0, limit.x),
		"right": clampf(roundf(visible.end.x - safe_canvas.end.x), 0.0, limit.x),
	}


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


func _empty_insets() -> Dictionary:
	return {"top": 0.0, "left": 0.0, "right": 0.0}
