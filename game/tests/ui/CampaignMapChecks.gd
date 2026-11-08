## Rendu et navigation de la carte unifiée, sans lancer de combat.
extends "res://tests/support/CombatTestSuite.gd"

const ContentLoader := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const StoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const ServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
const UnlockRules := preload("res://scripts/domain/campaign/CampaignUnlockRules.gd")
const MapViewScript := preload("res://scripts/ui/campaign/CampaignMapView.gd")
const PATH := "user://campaign_map_checks.json"

var _service: CampaignService = null
var _graph: CampaignGraph = null


func run() -> void:
	_cleanup()
	var content := ContentLoader.read()
	if not bool(content.get("ok", false)):
		_check(false, "carte : le contenu de campagne est valide")
		return
	_graph = GraphModel.build(content["definition"])
	var progress := ProgressModel.new()
	progress.mark_completed("tuto_01")
	_service = ServiceModel.new(_graph, progress, StoreModel.new(PATH), [])
	CampaignContext.set_service_for_tests(_service)
	CampaignContext.focus_node_id = "tuto_02"
	var page: Control = (load("res://scenes/campaign/CampaignMap.tscn") as PackedScene).instantiate()
	add_child(page)
	for frame in range(6):
		await get_tree().process_frame
	_test_page(page)
	await _test_dialog(page)
	await _test_responsive_view()
	page.queue_free()
	await get_tree().process_frame
	CampaignContext.reset_for_tests()
	_cleanup()


func _cleanup() -> void:
	for path in [PATH, PATH + ".tmp", PATH + ".unreadable"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _test_page(page: Control) -> void:
	var view: CampaignMapView = page.map_view
	var scroll: ScrollContainer = page.scroll
	_check(view != null and view.get_child_count() == _graph.node_count(),
		"carte : un contrôle de nœud est créé pour chaque nœud des données")
	_check(scroll.get_v_scroll_bar().max_value > scroll.size.y,
		"carte : la hauteur du contenu dépasse le téléphone et active le défilement vertical")
	_check(view.scale_factor() > 0.0
		and is_equal_approx(view.scale_factor(), view.size.x / UITheme.CAMPAIGN_MAP_WIDTH),
		"carte : le fond, les nœuds et les arêtes partagent le même facteur d'échelle")
	_check(view.content_height()
		>= (_graph.map_size.y + UITheme.CAMPAIGN_BOTTOM_PAD) * view.scale_factor() - 1.0,
		"carte : la hauteur minimale couvre tout le graphe et sa marge basse")
	var endpoints := view.edge_endpoints()
	var aligned := endpoints.size() == _graph.edge_count()
	for endpoint in endpoints:
		var from_center := view.node_center(str(endpoint["from_id"]))
		aligned = aligned and (endpoint["from"] as Vector2).distance_to(from_center) < 1.0
		aligned = aligned and (endpoint["to"] as Vector2).distance_to(
			view.node_center(str(endpoint["to_id"]))) < 1.0
	_check(aligned, "carte : chaque chemin commence et finit au centre de ses nœuds")
	var completed: Control = view.node_control("tuto_01")
	var available: Control = view.node_control("tuto_02")
	var locked: Control = view.node_control("tuto_03")
	_check(completed.state == UnlockRules.State.COMPLETED
		and available.state == UnlockRules.State.AVAILABLE
		and locked.state == UnlockRules.State.LOCKED,
		"carte : les états terminé, accessible et verrouillé sont distincts")
	_check(not completed.disabled and not available.disabled and locked.disabled,
		"carte : seul un nœud verrouillé est inactif")
	_check(completed.size.x > 0.0 and absf(completed.size.x - completed.size.y) < 1.0,
		"carte : les nœuds restent carrés à l'échelle du téléphone")


func _test_dialog(page: Control) -> void:
	page._on_node_activated("tuto_03")
	await get_tree().process_frame
	_check(not page.dialog.visible, "carte : un nœud verrouillé n'ouvre aucune fiche")
	page._on_node_activated("tuto_02")
	await get_tree().process_frame
	_check(page.dialog.visible and not page.dialog.launch_button.disabled,
		"carte : un nœud accessible ouvre sa fiche et autorise le lancement")
	_check(page.dialog.opponent_label.text.contains("Pr.Stone")
		and page.dialog.mode_label.text.contains("Classique")
		and page.dialog.type_label.text == "Tutoriel",
		"fiche : le nom, le dieu, le mode et le type du niveau sont lisibles")
	page.dialog.close()
	page._on_node_activated("tuto_01")
	await get_tree().process_frame
	_check(page.dialog.visible and page.dialog.launch_button.text == "REJOUER",
		"carte : un niveau terminé reste rejouable depuis sa fiche")
	page.dialog.close()


func _test_responsive_view() -> void:
	var view: CampaignMapView = MapViewScript.new()
	add_child(view)
	view.size = Vector2(540, 420)
	view.setup(_graph, _service.states(), "tuto_02")
	view.relayout()
	await get_tree().process_frame
	_check(is_equal_approx(view.scale_factor(), 0.5),
		"carte téléphone : la largeur 540 donne exactement une échelle de 0,5")
	_check(view.node_control("tuto_01").size.x == UITheme.CAMPAIGN_NODE_SIZE * 0.5,
		"carte téléphone : les nœuds réduisent avec le même facteur")
	var endpoints := view.edge_endpoints()
	var aligned := not endpoints.is_empty()
	for endpoint in endpoints:
		aligned = aligned and (endpoint["from"] as Vector2).distance_to(
			view.node_center(str(endpoint["from_id"]))) < 1.0
	_check(aligned, "carte téléphone : les courbes restent alignées après réduction")
	view.size = Vector2(1080, 700)
	view.relayout()
	await get_tree().process_frame
	_check(is_equal_approx(view.scale_factor(), 1.0)
		and view.node_control("final_01").size.x == UITheme.CAMPAIGN_NODE_SIZE,
		"carte tablette : la largeur 1080 restaure l'échelle logique de référence")
	_check(view.edge_endpoints().size() == _graph.edge_count(),
		"carte tablette : tous les chemins restent dessinés après redimensionnement")
	view.queue_free()
	await get_tree().process_frame
