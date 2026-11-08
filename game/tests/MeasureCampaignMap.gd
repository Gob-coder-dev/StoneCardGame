## Mesure de référence de la carte de campagne.
## Exécuter :
## godot --headless --fixed-fps 60 --path . res://tests/MeasureCampaignMap.tscn
extends Node

const ContentLoader := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const StoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const ServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
const MapViewScript := preload("res://scripts/ui/campaign/CampaignMapView.gd")
const ValidatorModel := preload("res://scripts/domain/campaign/CampaignValidator.gd")
const GenerationValidatorModel := preload("res://scripts/application/campaign/CampaignGenerationValidator.gd")
const LayoutValidatorModel := preload("res://scripts/data/campaign/CampaignLayoutValidator.gd")
const PATH := "user://campaign_measure.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var started := Time.get_ticks_usec()
	var content := ContentLoader.read()
	var content_ms := _ms(started)
	var definition: Dictionary = content.get("definition", {})
	started = Time.get_ticks_usec()
	var problems := ValidatorModel.problems(definition)
	var validator_ms := _ms(started)
	started = Time.get_ticks_usec()
	var graph: CampaignGraph = GraphModel.build(definition)
	var graph_ms := _ms(started)
	var edge_clearance_ms := _profile_edge_clearance(graph)
	var encounter_ms := _profile_encounters(definition)
	print("MESURE_CARTE validateur_ms=%.2f controles_aretes_ms=%.2f rencontres_ms=%.2f problemes=%d" % [
		validator_ms, edge_clearance_ms, encounter_ms, problems.size()])
	var progress := ProgressModel.new()
	progress.mark_completed("tuto_01")
	var service := ServiceModel.new(graph, progress, StoreModel.new(PATH), [])
	CampaignContext.set_service_for_tests(service)
	CampaignContext.focus_node_id = "tuto_02"
	var states := service.states()

	started = Time.get_ticks_usec()
	var view: CampaignMapView = MapViewScript.new()
	add_child(view)
	view.size = Vector2(1080, 1740)
	view.setup(graph, states, "tuto_02")
	var setup_ms := _ms(started)
	var created_after_setup := _node_views(view)
	started = Time.get_ticks_usec()
	view.relayout()
	var relayout_ms := _ms(started)
	await get_tree().process_frame
	await get_tree().process_frame

	var page: Control = (load("res://scenes/campaign/CampaignMap.tscn") as PackedScene).instantiate()
	started = Time.get_ticks_usec()
	add_child(page)
	var page_add_ms := _ms(started)
	var page_ready_frames := 0
	started = Time.get_ticks_usec()
	for frame in range(6):
		await get_tree().process_frame
		page_ready_frames += 1
	var six_frames_ms := _ms(started)
	var map_view: CampaignMapView = page.map_view
	var scroll: ScrollContainer = page.scroll

	print("MESURE_CARTE contenu_ms=%.2f graphe_ms=%.2f setup_vue_ms=%.2f relayout_ms=%.2f" % [
		content_ms, graph_ms, setup_ms, relayout_ms])
	print("MESURE_CARTE page_add_ms=%.2f six_frames_ms=%.2f frames=%d noeuds_donnees=%d aretes=%d" % [
		page_add_ms, six_frames_ms, page_ready_frames, graph.node_count(), graph.edge_count()])
	print("MESURE_CARTE vues_apres_setup=%d vues_page=%d enfants_page=%d descendants_page=%d" % [
		created_after_setup, _node_views(map_view), map_view.get_child_count(), _descendants(map_view)])
	print("MESURE_CARTE scroll_max=%.1f viewport=%.1f memoire_static_mb=%.2f" % [
		scroll.get_v_scroll_bar().max_value, scroll.size.y,
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0])
	print("MESURE_CARTE focus_controle=%s centre=%s" % [
		str(map_view.node_control("tuto_02") != null), str(map_view.node_center("tuto_02"))])
	view.queue_free()
	page.queue_free()
	CampaignContext.reset_for_tests()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	get_tree().quit(0)


func _ms(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _profile_edge_clearance(graph: CampaignGraph) -> float:
	var started := Time.get_ticks_usec()
	for edge in graph.edges():
		var ignored: Array[String] = []
		LayoutValidatorModel.edge_problems(graph, edge, ignored)
	return _ms(started)


func _profile_encounters(definition: Dictionary) -> float:
	var started := Time.get_ticks_usec()
	for raw in definition.get("nodes", []):
		if not raw is Dictionary:
			continue
		var node := CampaignNode.from_dict(raw)
		var ignored: Array[String] = []
		ignored.append_array(GenerationValidatorModel.node_problems(node,
			int(definition.get("campaign_version", 0))))
	return _ms(started)


func _node_views(view: Control) -> int:
	var count := 0
	for child in view.get_children():
		if child is CampaignNodeView:
			count += 1
	return count


func _descendants(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		count += 1 + _descendants(child)
	return count
