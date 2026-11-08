## CampaignMapController.gd
## Navigation de la carte virtuelle. Le contrôleur demande les états au service,
## ouvre la fiche d'un niveau, restaure une position relative à une ancre et
## transmet le lancement au contexte applicatif. Aucune règle de déverrouillage
## ni aucun contenu de niveau ici.
extends Control

const Routes := preload("res://scripts/ui/GameRoutes.gd")
const EncounterPresenter := preload("res://scripts/ui/campaign/CampaignEncounterPresenter.gd")

@onready var background: MenuBackground = $Background
@onready var back_button: Button = $Root/Header/BackButton
@onready var title_label: Label = $Root/Header/TitleLabel
@onready var progress_label: Label = $Root/Header/ProgressLabel
@onready var scroll: ScrollContainer = $Root/Scroll
@onready var map_view: CampaignMapView = $Root/Scroll/MapView
@onready var status_label: Label = $Root/StatusLabel
@onready var loading_hint: Label = $LoadingHint
@onready var dialog: CampaignLevelDialog = $LevelDialog

var _service: CampaignService = null
var _setup_done := false
var _nav_ready := false
var _restoring := false
var _stream_update_queued := false
var _position_save_timer: Timer = null
var _loading_timer: Timer = null


func _ready() -> void:
	back_button.pressed.connect(_go_back)
	map_view.node_activated.connect(_on_node_activated)
	dialog.launch_requested.connect(_on_launch_requested)
	dialog.closed.connect(_on_dialog_closed)
	map_view.streaming_changed.connect(_on_streaming_changed)
	scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	scroll.scroll_ended.connect(_on_scroll_ended)
	scroll.resized.connect(_on_viewport_resized)
	_setup_timers()
	_service = CampaignContext.get_service()
	if not _service.is_ready():
		_show_unavailable()
		return
	background.set_god(StoneLoader.get_god(PlayerData.player_god_id))
	title_label.text = (_service.graph().title if _service.graph().title != ""
		else "CARTE DE CAMPAGNE").to_upper()
	# La carte ne doit pas apparaître au offset 0 puis sauter sur l'ancre après
	# la première frame de layout. Elle est révélée avec la bonne position.
	map_view.modulate.a = 0.0
	_refresh()
	_restore_map_position.call_deferred()


func _setup_timers() -> void:
	_position_save_timer = Timer.new()
	_position_save_timer.one_shot = true
	_position_save_timer.wait_time = 0.65
	_position_save_timer.timeout.connect(_save_position_now)
	add_child(_position_save_timer)
	_loading_timer = Timer.new()
	_loading_timer.one_shot = true
	_loading_timer.wait_time = 0.28
	_loading_timer.timeout.connect(_show_loading_hint)
	add_child(_loading_timer)
	loading_hint.visible = false


func _show_unavailable() -> void:
	## Une campagne invalide ne s'ouvre pas partiellement : les diagnostics
	## restent lisibles pour corriger les données.
	map_view.visible = false
	loading_hint.visible = false
	dialog.visible = false
	title_label.text = "CARTE INDISPONIBLE"
	progress_label.text = ""
	var problems := _service.problems()
	status_label.text = problems[0] if not problems.is_empty() else "Campagne indisponible."
	status_label.add_theme_color_override("font_color", UITheme.COL_ERROR)


func _refresh() -> void:
	var states := _service.states()
	var anchor := _initial_anchor()
	var selected := _service.progress().last_selected
	if selected == "" or not _service.has_node(selected):
		selected = anchor
	if not _setup_done:
		map_view.setup(_service.graph(), states, selected, anchor, scroll.size.y)
		_setup_done = true
	else:
		map_view.refresh_states(states, selected)
	var total := _service.graph().node_count()
	var completed := _service.progress().completed_count()
	progress_label.text = "%d / %d niveaux terminés" % [completed, total]
	status_label.text = "Toutes les branches terminées restent accessibles."
	status_label.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)


func _initial_anchor() -> String:
	if _service.has_map_navigation():
		var saved = _service.map_navigation_state()
		if _service.has_node(saved.anchor_node_id):
			return saved.anchor_node_id
	return _service.graph().start_node_id


## Centrage initial sans construire les nœuds intermédiaires : la position est
## calculée depuis les coordonnées logiques, puis le ScrollContainer est placé
## avant que la file de lots ne devienne visible.
func _restore_map_position() -> void:
	await get_tree().process_frame
	if not is_inside_tree() or not _setup_done:
		return
	if scroll.size.y <= 0.0:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_restoring = true
	map_view.relayout()
	var target := 0.0
	if _service.has_map_navigation():
		var saved = _service.map_navigation_state()
		if _service.has_node(saved.anchor_node_id):
			target = map_view.scroll_for_anchor(saved.anchor_node_id, saved.offset_y)
	var maximum := maxf(0.0, scroll.get_v_scroll_bar().max_value - scroll.size.y)
	scroll.scroll_vertical = int(clampf(target, 0.0, maximum))
	_update_streaming()
	_restoring = false
	_nav_ready = true
	map_view.modulate.a = 1.0


func _on_node_activated(node_id: String) -> void:
	if not _service.is_available(node_id):
		return
	var error := _service.select_node(node_id)
	if error != OK:
		status_label.text = "Sélection non enregistrée (%s)." % error_string(error)
		status_label.add_theme_color_override("font_color", UITheme.COL_ERROR)
		return
	CampaignContext.focus_node_id = node_id
	map_view.set_selected(node_id)
	dialog.open(EncounterPresenter.summary(_service.node(node_id), PlayerData.player_god_id),
		_service.state_for(node_id))


func _on_launch_requested(node_id: String) -> void:
	var started := CampaignContext.enter_node(node_id)
	if not bool(started.get("ok", false)):
		dialog.show_error(str(started.get("reason", "Lancement impossible.")))
		return
	_save_position_now()
	dialog.close()
	Routes.go(get_tree(), Routes.CAMPAIGN_PREPARATION
		if bool(started.get("needs_preparation", false)) else Routes.PRE_BATTLE)


func _on_dialog_closed() -> void:
	status_label.text = "Toutes les branches terminées restent accessibles."
	status_label.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)


func _on_scroll_changed(_value: float) -> void:
	if not _nav_ready or _restoring:
		return
	_queue_stream_update()
	_queue_position_save()


## Un seul recalcul de secteurs par frame, même si le ScrollContainer émet
## plusieurs changements pendant une inertie tactile.
func _queue_stream_update() -> void:
	if _stream_update_queued:
		return
	_stream_update_queued = true
	_deferred_stream_update.call_deferred()


func _deferred_stream_update() -> void:
	_stream_update_queued = false
	if not is_inside_tree() or not _setup_done:
		return
	_update_streaming()


func _update_streaming() -> void:
	if not _setup_done or scroll.size.y <= 0.0:
		return
	map_view.update_streaming(scroll.scroll_vertical, scroll.size.y)


func _on_scroll_ended() -> void:
	if _nav_ready and not _restoring:
		_queue_position_save()


func _on_viewport_resized() -> void:
	if not _setup_done or not _nav_ready or _restoring:
		return
	# Conserver l'ancre visible lors d'un passage téléphone/tablette.
	var state: Dictionary = _current_navigation()
	map_view.relayout()
	var target := map_view.scroll_for_anchor(state["anchor_node_id"],
		float(state["offset_y"]))
	var maximum := maxf(0.0, scroll.get_v_scroll_bar().max_value - scroll.size.y)
	scroll.scroll_vertical = int(clampf(target, 0.0, maximum))
	_queue_stream_update()
	_queue_position_save()


func _queue_position_save() -> void:
	if _nav_ready and _service != null and _position_save_timer != null:
		_position_save_timer.start()


## Instantané relatif : le centre visible est ramené à un nœud ancre. Le pixel
## absolu n'est conservé que comme secours pour une version future du layout.
func _current_navigation() -> Dictionary:
	var scale := maxf(0.001, map_view.scale_factor())
	var logical_top := float(scroll.scroll_vertical) / scale
	var logical_height := float(scroll.size.y) / scale
	var center := Vector2(UITheme.CAMPAIGN_MAP_WIDTH * 0.5,
		logical_top + logical_height * 0.5)
	var anchor := map_view.nearest_node_id(center)
	if anchor == "":
		anchor = _service.graph().start_node_id
	var node := _service.node(anchor)
	var offset := logical_top - (node.position.y if node != null else 0.0)
	return {
		"anchor_node_id": anchor,
		"offset_y": offset,
		"scroll_vertical": float(scroll.scroll_vertical),
	}


func _save_position_now() -> void:
	if not _nav_ready or _service == null or not _setup_done:
		return
	if _position_save_timer != null:
		_position_save_timer.stop()
	var state := _current_navigation()
	var error := _service.save_map_navigation(str(state["anchor_node_id"]),
		float(state["offset_y"]), float(state["scroll_vertical"]))
	if error != OK and is_inside_tree():
		status_label.text = "Position de carte non enregistrée (%s)." % error_string(error)
		status_label.add_theme_color_override("font_color", UITheme.COL_WARNING)


func _on_streaming_changed(pending_count: int) -> void:
	if _loading_timer == null or loading_hint == null:
		return
	if pending_count > 0:
		if not loading_hint.visible:
			_loading_timer.start()
	else:
		_loading_timer.stop()
		loading_hint.visible = false


func _show_loading_hint() -> void:
	if map_view.is_streaming() and is_inside_tree():
		loading_hint.visible = true


func _go_back() -> void:
	if dialog.visible:
		dialog.close()
		return
	_save_position_now()
	_nav_ready = false
	Routes.go(get_tree(), Routes.MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _exit_tree() -> void:
	if _position_save_timer != null:
		_position_save_timer.stop()
	if _loading_timer != null:
		_loading_timer.stop()
	if _setup_done and _nav_ready:
		_save_position_now()
