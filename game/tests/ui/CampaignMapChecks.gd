## Rendu et navigation de la carte unifiée, sans lancer de combat.
extends "res://tests/support/CombatTestSuite.gd"

const ContentLoader := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const StoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const ServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
const UnlockRules := preload("res://scripts/domain/campaign/CampaignUnlockRules.gd")
const MapViewScript := preload("res://scripts/ui/campaign/CampaignMapView.gd")
const SectionTheme := preload("res://scripts/ui/campaign/CampaignSectionTheme.gd")
const SectionArt := preload("res://scripts/ui/campaign/CampaignSectionArt.gd")
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
	_test_sections()
	var progress := ProgressModel.new()
	progress.mark_completed("tuto_01")
	_service = ServiceModel.new(_graph, progress, StoreModel.new(PATH), [])
	CampaignContext.set_service_for_tests(_service)
	CampaignContext.focus_node_id = "tuto_02"
	var page: Control = (load("res://scenes/campaign/CampaignMap.tscn") as PackedScene).instantiate()
	add_child(page)
	for frame in range(8):
		await get_tree().process_frame
	_test_page(page)
	await _test_dialog(page)
	await _test_progress_refresh(page)
	await _test_far_scroll(page)
	page.queue_free()
	for frame in range(2):
		await get_tree().process_frame
	await _test_restore_position()
	await _test_close_during_load()
	await _test_responsive_view()
	await _test_requested_node_opens_dialog()
	CampaignContext.reset_for_tests()
	_cleanup()


## Le résultat dépose une demande : la carte centre et ouvre la fiche visée,
## puis la demande est consommée pour qu'un retour ordinaire ne rouvre rien.
func _test_requested_node_opens_dialog() -> void:
	CampaignContext.request_node("tuto_02")
	var page: Control = (load("res://scenes/campaign/CampaignMap.tscn") as PackedScene).instantiate()
	add_child(page)
	for _frame in range(16):
		await get_tree().process_frame
	_check(page.dialog.visible and page.dialog.name_label.text == "LA LEÇON",
		"carte : une demande du résultat ouvre la fiche du niveau visé")
	_check(CampaignContext.requested_node() == "",
		"carte : la demande d'ouverture n'est consommée qu'une fois")
	page.queue_free()
	await get_tree().process_frame
	var plain: Control = (load("res://scenes/campaign/CampaignMap.tscn") as PackedScene).instantiate()
	add_child(plain)
	for _frame in range(10):
		await get_tree().process_frame
	_check(not plain.dialog.visible,
		"carte : une arrivée sans demande ne rouvre aucune fiche")
	plain.queue_free()
	await get_tree().process_frame


func _cleanup() -> void:
	for path in [PATH, PATH + ".tmp", PATH + ".unreadable"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Les bandes visuelles viennent des chapitres du graphe, pas des données
## sauvegardées : leur géométrie doit rester contiguë et discrète.
func _test_sections() -> void:
	var sections := SectionTheme.build(_graph)
	_check(sections.size() == 13,
		"sections : les 13 chapitres produisent 13 bandes visuelles")
	var chapters := {}
	var tints := {}
	var motifs := {}
	var contiguous := true
	var medians_inside := true
	var palettes := true
	var cursor := 0.0
	for section in sections:
		var top := float(section.get("top", 0.0))
		var bottom := float(section.get("bottom", 0.0))
		var median_y := float(section.get("median_y", 0.0))
		chapters[str(section.get("chapter", ""))] = true
		tints[section.get("tint")] = true
		motifs[str(section.get("motif", ""))] = true
		contiguous = contiguous and is_equal_approx(top, cursor)
		cursor = bottom
		medians_inside = medians_inside and median_y >= top and median_y <= bottom
		palettes = palettes and section.get("tint") is Color \
			and section.get("accent") is Color \
			and str(section.get("motif", "")) != ""
	_check(contiguous,
		"sections : les bandes restent contiguës, sans trou ni recouvrement")
	_check(is_equal_approx(cursor,
		_graph.map_size.y + UITheme.CAMPAIGN_BOTTOM_PAD),
		"sections : la dernière bande couvre la marge basse de la carte")
	_check(chapters.size() == 13,
		"sections : chaque chapitre apparaît une seule fois")
	_check(tints.size() == 13,
		"sections : les treize teintes restent distinctes")
	_check(motifs.size() == 13,
		"sections : les treize motifs restent distincts")
	_check(medians_inside,
		"sections : la médiane de chaque chapitre reste dans sa bande")
	_check(palettes,
		"sections : chaque bande possède une teinte, un accent et un motif")
	_check(SectionArt.TINT_ALPHA <= 0.5 and SectionArt.EDGE_ALPHA <= 0.16
		and SectionArt.CENTER_ALPHA <= 0.07,
		"sections : le budget de contraste reste très discret")


func _test_page(page: Control) -> void:
	var view: CampaignMapView = page.map_view
	var scroll: ScrollContainer = page.scroll
	_check(_graph.node_count() == 162,
		"carte virtuelle : les données conservent les 162 niveaux")
	_check(view.section_count() == 13,
		"carte virtuelle : les 13 sections visuelles sont construites avec le graphe")
	_check(view.loaded_count() > 0 and view.loaded_count() < _graph.node_count(),
		"carte virtuelle : l'ouverture n'instancie pas les 162 représentations")
	_check(view.pending_count() == 0,
		"carte virtuelle : la première zone finit de se construire par lots")
	_check(scroll.scroll_vertical == 0,
		"carte virtuelle : un premier accès sans position sauvegardée ouvre au début")
	_check(view.get_child_count() == view.loaded_count(),
		"carte virtuelle : chaque représentation chargée possède un seul Control")
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
	_check(aligned, "carte : chaque chemin logique commence et finit au centre de ses nœuds")
	_check(view.drawn_edge_count() > 0 and view.drawn_edge_count() <= _graph.edge_count(),
		"carte virtuelle : seules les arêtes des nœuds chargés sont dessinées")
	_check(_drawn_edges_are_loaded(view),
		"carte virtuelle : aucune arête dessinée ne pointe vers un nœud absent")
	var completed: Control = view.node_control("tuto_01")
	var available: Control = view.node_control("tuto_02")
	var locked: Control = view.node_control("tuto_03")
	_check(completed != null and available != null and locked != null,
		"carte virtuelle : la première zone contient les nœuds du tutoriel")
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


func _test_progress_refresh(page: Control) -> void:
	var view: CampaignMapView = page.map_view
	var loaded_before := view.loaded_count()
	_check(_service.complete_node("tuto_02") == OK,
		"carte virtuelle : une victoire met à jour la progression")
	page._refresh()
	await get_tree().process_frame
	_check(view.loaded_count() == loaded_before,
		"carte virtuelle : une progression ne recharge pas toute la carte")
	var completed: Control = view.node_control("tuto_02")
	var unlocked: Control = view.node_control("tuto_03")
	_check(completed != null and completed.state == UnlockRules.State.COMPLETED,
		"carte virtuelle : le niveau terminé garde son état")
	_check(unlocked != null and unlocked.state == UnlockRules.State.AVAILABLE,
		"carte virtuelle : seul le successeur concerné est actualisé")


func _test_far_scroll(page: Control) -> void:
	var view: CampaignMapView = page.map_view
	var scroll: ScrollContainer = page.scroll
	var target := int(maxf(0.0, view.node_center("final_01").y - scroll.size.y * 0.45))
	scroll.scroll_vertical = target
	for frame in range(12):
		await get_tree().process_frame
	_check(scroll.scroll_vertical > 1000,
		"carte virtuelle : le défilement atteint la fin de la campagne")
	_check(view.node_control("final_01") != null,
		"carte virtuelle : la zone finale se charge à l'approche du viewport")
	_check(view.node_control("tuto_01") == null,
		"carte virtuelle : une zone éloignée est déchargée")
	_check(view.loaded_count() < _graph.node_count(),
		"carte virtuelle : le déchargement ne recrée jamais les 162 nœuds")
	_check(_service.is_completed("tuto_01") and _service.is_completed("tuto_02"),
		"carte virtuelle : le déchargement ne perd aucune progression")
	_check(view.get_child_count() == view.loaded_count()
		and _unique_child_count(view) == view.loaded_count(),
		"carte virtuelle : les allers-retours ne créent aucun doublon")
	_check(_drawn_edges_are_loaded(view),
		"carte virtuelle : les connexions restent cohérentes aux frontières")
	scroll.scroll_vertical = 0
	for frame in range(12):
		await get_tree().process_frame
	_check(view.node_control("tuto_01") != null,
		"carte virtuelle : revenir vers une zone déchargée la reconstruit")
	var restored: Control = view.node_control("tuto_02")
	_check(restored != null and restored.state == UnlockRules.State.COMPLETED,
		"carte virtuelle : un niveau recréé retrouve son état de progression")


func _test_restore_position() -> void:
	var error := _service.save_map_navigation("final_01", -280.0, 12000.0)
	_check(error == OK, "position : l'ancre de navigation se sauvegarde")
	var page: Control = (load("res://scenes/campaign/CampaignMap.tscn") as PackedScene).instantiate()
	add_child(page)
	for frame in range(10):
		await get_tree().process_frame
	_check(page.scroll.scroll_vertical > 1000,
		"position : la dernière position est restaurée au lieu du début")
	_check(page.map_view.node_control("final_01") != null,
		"position : la zone de l'ancre est chargée en priorité")
	_check(page.map_view.loaded_count() < _graph.node_count(),
		"position : la restauration ne construit pas les zones intermédiaires")
	page.queue_free()
	for frame in range(2):
		await get_tree().process_frame


func _test_close_during_load() -> void:
	var page: Control = (load("res://scenes/campaign/CampaignMap.tscn") as PackedScene).instantiate()
	add_child(page)
	page.queue_free()
	for frame in range(4):
		await get_tree().process_frame
	var fresh: Control = (load("res://scenes/campaign/CampaignMap.tscn") as PackedScene).instantiate()
	add_child(fresh)
	for frame in range(6):
		await get_tree().process_frame
	_check(fresh.map_view.loaded_count() > 0 and fresh.map_view.get_child_count()
		== fresh.map_view.loaded_count(),
		"position : fermer pendant un chargement ne corrompt pas une nouvelle carte")
	fresh.queue_free()
	for frame in range(2):
		await get_tree().process_frame


func _test_responsive_view() -> void:
	var view: CampaignMapView = MapViewScript.new()
	add_child(view)
	view.size = Vector2(540, 420)
	view.setup(_graph, _service.states(), "tuto_02", "tuto_02", 420)
	view.relayout()
	for frame in range(5):
		await get_tree().process_frame
	_check(is_equal_approx(view.scale_factor(), 0.5),
		"carte téléphone : la largeur 540 donne exactement une échelle de 0,5")
	var phone_node: Control = view.node_control("tuto_01")
	_check(phone_node != null and phone_node.size.x == UITheme.CAMPAIGN_NODE_SIZE * 0.5,
		"carte téléphone : les nœuds réduisent avec le même facteur")
	var endpoints := view.edge_endpoints()
	var aligned := not endpoints.is_empty()
	for endpoint in endpoints:
		aligned = aligned and (endpoint["from"] as Vector2).distance_to(
			view.node_center(str(endpoint["from_id"]))) < 1.0
	_check(aligned, "carte téléphone : les courbes restent alignées après réduction")
	view.size = Vector2(1080, 700)
	view.relayout()
	for frame in range(3):
		await get_tree().process_frame
	var tablet_node: Control = view.node_control("tuto_01")
	_check(is_equal_approx(view.scale_factor(), 1.0)
		and tablet_node != null and tablet_node.size.x == UITheme.CAMPAIGN_NODE_SIZE,
		"carte tablette : la largeur 1080 restaure l'échelle logique de référence")
	_check(view.edge_endpoints().size() == _graph.edge_count(),
		"carte tablette : tous les chemins logiques restent disponibles")
	view.queue_free()
	for frame in range(2):
		await get_tree().process_frame


func _drawn_edges_are_loaded(view: CampaignMapView) -> bool:
	var result := true
	for endpoint in view.drawn_edge_endpoints():
		result = result and view.node_control(str(endpoint["from_id"])) != null
		result = result and view.node_control(str(endpoint["to_id"])) != null
	return result


func _unique_child_count(view: CampaignMapView) -> int:
	var names := {}
	for child in view.get_children():
		names[child.name] = true
	return names.size()
