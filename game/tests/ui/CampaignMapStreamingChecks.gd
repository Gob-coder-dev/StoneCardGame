## Découpage spatial, hystérésis et persistance de la position de carte.
extends "res://tests/support/CombatTestSuite.gd"

const ContentLoader := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const StoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const ServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
const ChunkManagerModel := preload("res://scripts/ui/campaign/CampaignMapChunkManager.gd")
const PositionStateModel := preload("res://scripts/application/campaign/CampaignMapPositionState.gd")
const PATH := "user://campaign_streaming_checks.json"


func run() -> void:
	_cleanup()
	var content := ContentLoader.read()
	if not bool(content.get("ok", false)):
		_check(false, "streaming : le contenu de campagne est valide")
		return
	var graph: CampaignGraph = GraphModel.build(content["definition"])
	_test_chunks(graph)
	_test_position_state(graph)
	_test_navigation_store(graph)
	_cleanup()


func _cleanup() -> void:
	for path in [PATH, PATH + ".tmp", PATH + ".unreadable"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _test_chunks(graph: CampaignGraph) -> void:
	var manager: CampaignMapChunkManager = ChunkManagerModel.new(graph)
	var visible := Rect2(0.0, 0.0, UITheme.CAMPAIGN_MAP_WIDTH, 1694.0)
	var first := manager.update(visible, visible.size)
	var first_add: Array = first["add"]
	_check(not first_add.is_empty() and first_add.size() < graph.node_count(),
		"streaming : l'ouverture charge une zone, pas les 154 nœuds")
	_check(_unique(first_add).size() == first_add.size(),
		"streaming : les identifiants demandés ne sont jamais dupliqués")
	_check(manager.active_node_ids().size() == first_add.size(),
		"streaming : la zone active correspond exactement aux nœuds demandés")
	var repeated := manager.update(visible, visible.size)
	_check((repeated["add"] as Array).is_empty()
		and (repeated["remove"] as Array).is_empty(),
		"streaming : une demande répétée ne recharge rien")
	var preloaded_below := false
	for node_id in first_add:
		var node := graph.node(str(node_id))
		if node != null and node.position.y > visible.size.y:
			preloaded_below = true
			break
	_check(preloaded_below,
		"streaming : une marge sous le viewport est préchargée")
	var small := manager.update(Rect2(0.0, 500.0, 1080.0, 1694.0),
		visible.size)
	_check((small["remove"] as Array).is_empty(),
		"streaming : un petit déplacement ne décharge pas la zone voisine")

	var far := manager.update(Rect2(0.0, 8000.0, 1080.0, 1694.0), visible.size)
	_check(not (far["remove"] as Array).is_empty()
		and not (far["add"] as Array).is_empty(),
		"streaming : un saut éloigné remplace les zones devenues inutiles")
	_check(not manager.active_node_ids().has("tuto_01"),
		"streaming : une zone très éloignée est réellement déchargée")
	var back := manager.update(visible, visible.size)
	_check(not (back["add"] as Array).is_empty(),
		"streaming : revenir vers une zone la redemande correctement")
	var active := manager.active_node_ids()
	_check(_unique(active).size() == active.size(),
		"streaming : les allers-retours ne dupliquent aucun nœud")
	_check(manager.chunk_for_point(Vector2(700.0, 10.0)).x == 1,
		"streaming : le découpage prend aussi en compte l'axe latéral")


func _test_position_state(graph: CampaignGraph) -> void:
	var state := PositionStateModel.make("final_01", -240.0, 3200.0)
	var parsed := PositionStateModel.from_dict(state.to_dict())
	_check(parsed.anchor_node_id == "final_01"
		and is_equal_approx(parsed.offset_y, -240.0)
		and is_equal_approx(parsed.scroll_vertical, 3200.0)
		and parsed.version == PositionStateModel.VERSION,
		"position : le format versionné restitue ancre, offset et secours")
	var malformed := PositionStateModel.from_dict("position invalide")
	_check(malformed.is_empty(),
		"position : une valeur corrompue est ignorée sans erreur")
	var invalid := PositionStateModel.from_dict({
		"version": 1,
		"anchor_node_id": "niveau_supprime",
		"offset_y": 12.0,
		"scroll_vertical": 800.0,
	})
	var fallback := invalid.resolved(graph, "tuto_02")
	_check(fallback.anchor_node_id == "tuto_02"
		and is_zero_approx(fallback.offset_y),
		"position : une ancre disparue utilise le fallback sûr")
	var legacy := ProgressModel.from_dict({"completed_node_ids": ["tuto_01"]})
	_check(legacy.map_navigation.is_empty(),
		"position : une ancienne sauvegarde sans navigation reste valide")


func _test_navigation_store(graph: CampaignGraph) -> void:
	var progress := ProgressModel.new()
	progress.mark_completed("tuto_01")
	progress.set_last_selected("tuto_01")
	var service := ServiceModel.new(graph, progress, StoreModel.new(PATH), [])
	var error := service.save_map_navigation("tuto_02", -123.5, 456.0)
	_check(error == OK, "position : la sauvegarde dédiée réussit")
	var loaded := StoreModel.new(PATH).load_progress()
	_check(str(loaded.map_navigation.get("anchor_node_id", "")) == "tuto_02"
		and is_equal_approx(float(loaded.map_navigation.get("offset_y", 0.0)), -123.5),
		"position : le rechargement restitue l'ancre et son offset")
	_check(loaded.is_completed("tuto_01") and loaded.last_selected == "tuto_01",
		"position : la progression et la dernière sélection restent séparées")
	var before := loaded.to_dict()
	var invalid_error := service.save_map_navigation("absent", 0.0, 0.0)
	_check(invalid_error != OK
		and service.progress().to_dict() == before,
		"position : une ancre inconnue n'écrase pas la sauvegarde")

	var old_progress := ProgressModel.from_dict({"completed_node_ids": ["tuto_01"]})
	var old_service := ServiceModel.new(graph, old_progress, StoreModel.new(PATH + ".old"), [])
	_check(not old_service.has_map_navigation()
		and old_service.map_navigation_state().anchor_node_id == graph.start_node_id,
		"position : sans état de navigation, la carte s'ouvre au début")

	var lost := ProgressModel.from_dict({"completed_node_ids": ["tuto_01"]})
	lost.set_map_navigation({"version": 1, "anchor_node_id": "disparu",
		"offset_y": -80.0, "scroll_vertical": 900.0})
	var lost_service := ServiceModel.new(graph, lost, StoreModel.new(PATH + ".lost"), [])
	_check(lost_service.has_map_navigation()
		and lost_service.map_navigation_state().anchor_node_id == "tuto_01",
		"position : une ancre supprimée retombe sur le dernier niveau terminé")
	for path in [PATH + ".old", PATH + ".lost"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _unique(values: Array) -> Array:
	var result := {}
	for value in values:
		result[str(value)] = true
	return result.keys()
