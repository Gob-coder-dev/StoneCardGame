## Persistance additive des états du scénario, sans migration de version.
extends "res://tests/support/CombatTestSuite.gd"

const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const StoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const ServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
const PATH := "user://story_progress_checks.json"
const BAD_PATH := "user://story_missing_dir_checks/progress.json"


func run() -> void:
	_cleanup()
	_test_defaults_and_round_trip()
	_test_legacy_save_loads()
	_test_service_transaction()
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


func _test_defaults_and_round_trip() -> void:
	var progress := ProgressModel.new()
	_check(not progress.story_state("seq:tuto_01_intro:seen"),
		"progression : un état de scénario est faux par défaut")
	progress.set_story_state("seq:tuto_01_intro:seen", true)
	progress.set_story_state("chapter:tuto_01_first_card:done", true)
	_check(progress.story_state("seq:tuto_01_intro:seen")
		and progress.story_state("chapter:tuto_01_first_card:done"),
		"progression : les états de scénario se lisent en mémoire")
	progress.set_story_state("", true)
	_check(not progress.story_states.has(""),
		"progression : une clé vide n'est jamais enregistrée")
	var loaded := ProgressModel.from_dict(progress.to_dict())
	_check(loaded.story_state("seq:tuto_01_intro:seen")
		and loaded.story_state("chapter:tuto_01_first_card:done"),
		"progression : la sérialisation restitue les états de scénario")
	var store := StoreModel.new(PATH)
	_check(store.save(progress) == OK,
		"progression : la sauvegarde dédiée accepte les états de scénario")
	var restored := store.load_progress()
	_check(restored.story_state("seq:tuto_01_intro:seen")
		and restored.story_state("chapter:tuto_01_first_card:done"),
		"progression : le rechargement disque restitue les états de scénario")


func _test_legacy_save_loads() -> void:
	var legacy := ProgressModel.new()
	legacy.mark_completed("tuto_01")
	legacy.set_last_selected("tuto_01")
	var source := legacy.to_dict()
	source.erase("story_states")
	var upgraded := ProgressModel.from_dict(source)
	_check(upgraded.is_completed("tuto_01"),
		"progression : une ancienne sauvegarde reste lisible")
	_check(upgraded.story_states.is_empty(),
		"progression : une sauvegarde sans champ scénario démarre sans état vu")


func _test_service_transaction() -> void:
	var graph: CampaignGraph = GraphModel.build(_content_definition())
	var progress := ProgressModel.new()
	var service := ServiceModel.new(graph, progress, StoreModel.new(PATH), [])
	_check(not service.story_state("chapter:tuto_01_first_card:done"),
		"service campagne : un chapitre n'est pas terminé par défaut")
	_check(service.mark_story_state("chapter:tuto_01_first_card:done") == OK,
		"service campagne : un état de scénario s'enregistre")
	_check(service.story_state("chapter:tuto_01_first_card:done"),
		"service campagne : l'état enregistré est publié en mémoire")
	_check(service.mark_story_state("chapter:tuto_01_first_card:done") == OK,
		"service campagne : réenregistrer le même état reste idempotent")
	_check(service.mark_story_state("") == ERR_INVALID_PARAMETER,
		"service campagne : une clé vide est refusée")
	var reloaded := StoreModel.new(PATH).load_progress()
	_check(reloaded.story_state("chapter:tuto_01_first_card:done"),
		"service campagne : l'état est bien écrit sur disque")
	var failing := ServiceModel.new(graph, ProgressModel.new(), StoreModel.new(BAD_PATH), [])
	var error := failing.mark_story_state("chapter:autre:done")
	_check(error != OK and not failing.story_state("chapter:autre:done"),
		"service campagne : un échec d'écriture ne publie pas l'état en mémoire")
	_check(not FileAccess.file_exists(BAD_PATH),
		"service campagne : un échec d'écriture ne crée aucun fichier partiel")
