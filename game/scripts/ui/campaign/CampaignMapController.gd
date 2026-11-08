## CampaignMapController.gd
## Navigation de la carte unifiée. Le contrôleur demande les états au service,
## ouvre la fiche d'un niveau et transmet le lancement au contexte applicatif.
## Aucune règle de déverrouillage ni aucun contenu de niveau ici.
extends Control

const Routes := preload("res://scripts/ui/GameRoutes.gd")

@onready var background: MenuBackground = $Background
@onready var back_button: Button = $Root/Header/BackButton
@onready var title_label: Label = $Root/Header/TitleLabel
@onready var progress_label: Label = $Root/Header/ProgressLabel
@onready var scroll: ScrollContainer = $Root/Scroll
@onready var map_view: CampaignMapView = $Root/Scroll/MapView
@onready var status_label: Label = $Root/StatusLabel
@onready var dialog: CampaignLevelDialog = $LevelDialog

var _service: CampaignService = null
var _setup_done := false


func _ready() -> void:
	back_button.pressed.connect(_go_back)
	map_view.node_activated.connect(_on_node_activated)
	dialog.launch_requested.connect(_on_launch_requested)
	dialog.closed.connect(_on_dialog_closed)
	_service = CampaignContext.get_service()
	if not _service.is_ready():
		_show_unavailable()
		return
	background.set_god(StoneLoader.get_god(PlayerData.player_god_id))
	title_label.text = (_service.graph().title if _service.graph().title != ""
		else "CARTE DE CAMPAGNE").to_upper()
	_refresh()
	_center_on_focus.call_deferred()


func _show_unavailable() -> void:
	## Une campagne invalide ne s'ouvre pas partiellement : les diagnostics
	## restent lisibles pour corriger les données.
	map_view.visible = false
	dialog.visible = false
	title_label.text = "CARTE INDISPONIBLE"
	progress_label.text = ""
	var problems := _service.problems()
	status_label.text = problems[0] if not problems.is_empty() else "Campagne indisponible."
	status_label.add_theme_color_override("font_color", UITheme.COL_ERROR)


func _refresh() -> void:
	var states := _service.states()
	var focus := CampaignContext.focus_node_id
	if focus == "" or not _service.has_node(focus):
		focus = _service.focus_node_id()
		CampaignContext.focus_node_id = focus
	if not _setup_done:
		map_view.setup(_service.graph(), states, focus)
		_setup_done = true
	else:
		map_view.refresh_states(states, focus)
	var total := _service.graph().node_count()
	var completed := _service.progress().completed_count()
	progress_label.text = "%d / %d niveaux terminés" % [completed, total]
	status_label.text = "Toutes les branches terminées restent accessibles."
	status_label.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)


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
	dialog.open(_service.summary(node_id, PlayerData.player_god_id),
		_service.state_for(node_id))


func _on_launch_requested(node_id: String) -> void:
	var started := CampaignContext.enter_node(node_id)
	if not bool(started.get("ok", false)):
		dialog.show_error(str(started.get("reason", "Lancement impossible.")))
		return
	dialog.close()
	Routes.go(get_tree(), Routes.CAMPAIGN_PREPARATION
		if bool(started.get("needs_preparation", false)) else Routes.PRE_BATTLE)


func _on_dialog_closed() -> void:
	status_label.text = "Toutes les branches terminées restent accessibles."
	status_label.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)


## Centrage initial sur le dernier nœud pertinent. Le calcul est volontairement
## séparé du rendu : la carte peut être plus haute que le téléphone.
func _center_on_focus() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	map_view.relayout()
	var focus := CampaignContext.focus_node_id
	var control := map_view.node_control(focus)
	if control == null:
		return
	var target := control.position.y + control.size.y * 0.5 - scroll.size.y * 0.45
	var maximum := maxf(0.0, scroll.get_v_scroll_bar().max_value - scroll.size.y)
	scroll.scroll_vertical = int(clampf(target, 0.0, maximum))


func _go_back() -> void:
	if dialog.visible:
		dialog.close()
		return
	Routes.go(get_tree(), Routes.MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()
