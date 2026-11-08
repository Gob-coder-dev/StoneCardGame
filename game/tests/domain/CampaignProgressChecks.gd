## Sauvegarde, chargement et migration de la progression de campagne.
extends "res://tests/support/CombatTestSuite.gd"

const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const StoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const MigrationModel := preload("res://scripts/application/campaign/CampaignSaveMigration.gd")
const ServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
const UnlockRules := preload("res://scripts/domain/campaign/CampaignUnlockRules.gd")
const PATH := "user://campaign_progress_checks.json"
const BAD_PATH := "user://campaign_missing_dir_checks/progress.json"


func run() -> void:
	_cleanup()
	_test_round_trip()
	_test_service_save_failure()
	_test_migration()
	_test_migration_is_idempotent()
	_test_twenty_node_save_upgrade()
	_test_migration_archives_ambiguity()
	_test_migration_does_not_touch_profile()
	_test_failed_migration_keeps_old_file()
	_cleanup()


func _cleanup() -> void:
	for path in [PATH, PATH + ".tmp", PATH + ".unreadable", BAD_PATH, BAD_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _content_definition() -> Dictionary:
	var file := FileAccess.open("res://data/campaign/campaign_v2.json", FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _test_round_trip() -> void:
	var progress := ProgressModel.new()
	progress.mark_completed("tuto_01")
	progress.mark_completed("tuto_02")
	progress.record_attempt("tuto_02")
	progress.record_attempt("tuto_02")
	progress.set_last_selected("tuto_02")
	progress.set_tutorial_state("tutoriel_seuil", "done")
	progress.set_map_navigation({"version": 1, "anchor_node_id": "tuto_02",
		"offset_y": -120.5, "scroll_vertical": 880.0})
	progress.campaign_version = 1
	var store := StoreModel.new(PATH)
	_check(store.save(progress) == OK, "progression : la sauvegarde dédiée réussit")
	var loaded := store.load_progress()
	_check(loaded.completed == progress.completed
		and loaded.attempts_for("tuto_02") == 2
		and loaded.last_selected == "tuto_02"
		and loaded.tutorial_state("tutoriel_seuil") == "done"
		and str(loaded.map_navigation.get("anchor_node_id", "")) == "tuto_02",
		"progression : le rechargement restitue nœuds, tentatives, dernier nœud, tutoriels et position")
	_check(loaded.to_dict() == progress.to_dict(),
		"progression : la sérialisation est stable et complète")
	var copy := progress.duplicate_progress()
	copy.mark_completed("tuto_03")
	_check(not progress.is_completed("tuto_03") and copy.is_completed("tuto_03"),
		"progression : les copies de travail sont indépendantes")


func _test_service_save_failure() -> void:
	var graph: CampaignGraph = GraphModel.build(_content_definition())
	var progress := ProgressModel.new()
	var service := ServiceModel.new(graph, progress, StoreModel.new(BAD_PATH), [])
	var error := service.complete_node("tuto_01")
	_check(error != OK and not service.is_completed("tuto_01"),
		"progression : un échec d'écriture ne valide pas le nœud en mémoire")
	_check(not FileAccess.file_exists(BAD_PATH),
		"progression : un échec d'écriture ne crée aucun fichier partiel")


func _test_migration() -> void:
	var graph: CampaignGraph = GraphModel.build(_content_definition())
	var progress := ProgressModel.new()
	var stats := {
		"per_npc": {
			"bot_kharun_n2_facile": {"wins": 1, "games": 2, "best_diff": 1},
			"bot_veskar_n1_tres_facile": {"wins": 1, "games": 1, "best_diff": 3},
		},
	}
	var stats_before := stats.duplicate(true)
	var migrated := MigrationModel.migrate(graph, stats, progress)
	_check(bool(migrated.get("changed", false)) and progress.is_completed("kharun_01"),
		"migration : une victoire historique non ambiguë devient un nœud terminé")
	_check(not progress.is_completed("veskar_01")
		and progress.migration.get("archived_stats", {}).has("bot_veskar_n1_tres_facile"),
		"migration : une victoire non convertible est archivée au lieu d'être devinée")
	_check(stats == stats_before,
		"migration : les statistiques historiques ne sont pas modifiées")
	_check(progress.migration_version() == graph.campaign_version,
		"migration : la version de migration est enregistrée")


func _test_migration_is_idempotent() -> void:
	var graph: CampaignGraph = GraphModel.build(_content_definition())
	var progress := ProgressModel.new()
	var first := MigrationModel.migrate(graph, {"per_npc": {
		"bot_kharun_n2_facile": {"wins": 1},
	}}, progress)
	_check(bool(first.get("changed", false)), "migration : la première conversion s'applique")
	var completed_before := progress.completed.duplicate()
	var second := MigrationModel.migrate(graph, {"per_npc": {
		"bot_kharun_n2_facile": {"wins": 1},
		"bot_veskar_n1_tres_facile": {"wins": 1},
	}}, progress)
	_check(not bool(second.get("changed", false))
		and progress.completed == completed_before,
		"migration : une seconde exécution ne convertit ni n'archive à nouveau")


func _test_twenty_node_save_upgrade() -> void:
	var graph: CampaignGraph = GraphModel.build(_content_definition())
	var progress := ProgressModel.new()
	var old_ids := [
		"tuto_01", "tuto_02", "tuto_03", "veskar_01", "nerava_01", "kharun_01",
		"mini_optional_01", "veskar_02", "ilyr_01", "mirror_01", "kharun_02",
		"sylkha_01", "veilleur_impasse", "convergence_01", "boss_required_gate",
		"choice_01", "ilyr_02", "sylkha_02", "mini_optional_02", "final_01",
	]
	for node_id in old_ids:
		progress.mark_completed(node_id)
	progress.campaign_version = 1
	var migrated := MigrationModel.migrate(graph, {}, progress)
	_check(bool(migrated.get("changed", false))
		and progress.campaign_version == 3
		and progress.completed_count() == 27
		and progress.is_completed("mini_optional_01_path_2")
		and progress.is_completed("mini_optional_02_path_5")
		and (migrated.get("path_nodes_completed", []) as Array).size() == 7,
		"migration : une sauvegarde à 20 niveaux conserve ses victoires et complète les approches")
	var states := UnlockRules.states(graph, progress.completed)
	_check(int(states.get("r03_entry", UnlockRules.State.LOCKED)) == UnlockRules.State.AVAILABLE,
		"migration : la suite de 154 niveaux s'ouvre derrière un carrefour déjà terminé")
	var second := MigrationModel.migrate(graph, {}, progress)
	_check(not bool(second.get("changed", false)) and progress.completed_count() == 27,
		"migration : la conversion 20 → 154 est idempotente")

	var partial := ProgressModel.new()
	partial.mark_completed("tuto_01")
	partial.campaign_version = 1
	MigrationModel.migrate(graph, {}, partial)
	var partial_states := UnlockRules.states(graph, partial.completed)
	_check(partial.completed_count() == 1
		and int(partial_states.get("tuto_02", UnlockRules.State.LOCKED)) == UnlockRules.State.AVAILABLE
		and int(partial_states.get("r03_entry", UnlockRules.State.LOCKED)) == UnlockRules.State.LOCKED,
		"migration : une progression partielle ne débloque pas une région sans son prédécesseur")


func _test_migration_archives_ambiguity() -> void:
	var definition := _content_definition()
	var graph: CampaignGraph = GraphModel.build(definition)
	var template: Dictionary = {}
	for node in graph.nodes():
		if node.id == "kharun_01":
			template = node.raw.duplicate(true)
	if template.is_empty():
		_check(false, "migration : le nœud kharun_01 existe")
		return
	template["id"] = "kharun_01_bis"
	template["name"] = "Doublon"
	template["position"] = {"x": 1040, "y": 2380}
	definition["nodes"].append(template)
	var ambiguous_graph: CampaignGraph = GraphModel.build(definition)
	var progress := ProgressModel.new()
	var migrated := MigrationModel.migrate(ambiguous_graph,
		{"per_npc": {"bot_kharun_n2_facile": {"wins": 1}}}, progress)
	_check((migrated.get("converted", []) as Array).is_empty()
		and progress.completed_count() == 0
		and progress.migration.get("archived_stats", {}).has("bot_kharun_n2_facile"),
		"migration : une rencontre revendiquée par deux nœuds est archivée sans choix arbitraire")


func _test_migration_does_not_touch_profile() -> void:
	var before: Dictionary = PlayerData.stats.duplicate(true)
	var graph: CampaignGraph = GraphModel.build(_content_definition())
	var progress := ProgressModel.new()
	MigrationModel.migrate(graph, before, progress)
	_check(PlayerData.stats == before,
		"migration : le profil permanent reste strictement inchangé")


func _test_failed_migration_keeps_old_file() -> void:
	# Un ancien fichier valide doit survivre à une migration dont l'écriture
	# échoue : le service signale l'erreur au lieu de détruire la progression.
	var progress := ProgressModel.new()
	progress.mark_completed("tuto_01")
	var store := StoreModel.new(PATH)
	_check(store.save(progress) == OK, "migration : le fichier initial est écrit")
	var before := FileAccess.get_file_as_string(PATH)
	var service := ServiceModel.create_default(BAD_PATH, {"per_npc": {
		"bot_kharun_n2_facile": {"wins": 1},
	}})
	_check(not service.is_ready()
		and not service.problems().is_empty(),
		"migration : un échec d'écriture rend le chargement explicite")
	_check(FileAccess.get_file_as_string(PATH) == before,
		"migration : l'ancien fichier de progression reste intact")
