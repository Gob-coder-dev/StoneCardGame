## Régressions de l'audit : transactions atomiques, reprises et données externes.
extends "res://tests/support/CombatTestSuite.gd"

const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const Profile := preload("res://scripts/data/PlayerData.gd")
const Storage := preload("res://scripts/data/PlayerSaveStorage.gd")
const Inventory := preload("res://scripts/domain/economy/PlayerInventory.gd")
const Economy := preload("res://scripts/application/economy/EconomyService.gd")
const Quests := preload("res://scripts/application/quests/QuestService.gd")
const Persistence := preload("res://scripts/application/campaign/CampaignResultPersistence.gd")
const Content := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const Graph := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const Progress := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const Service := preload("res://scripts/application/campaign/CampaignService.gd")
const Store := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const Fixture := preload("res://tests/support/PlayerProfileFixture.gd")
const PvpContext := preload("res://scripts/application/pvp/PvpMatchContext.gd")
const ResultScene := preload("res://scenes/menus/Result.tscn")
const PATH := "user://audit_regression.json"

var _quest_attempts := 0


class FaultStore extends Store:
	var fail_next := false

	func save(progress: CampaignProgress) -> Error:
		if fail_next:
			fail_next = false
			return ERR_FILE_CANT_WRITE
		return super.save(progress)


func run() -> void:
	var fixture := Fixture.new(Codec.starter_profile())
	_test_malformed_profile()
	_test_future_profile()
	_test_future_campaign()
	_test_ledger_compaction()
	_test_atomic_upgrade()
	_test_invalid_deck_rollback()
	_test_result_retry(false)
	_test_result_retry(true)
	_test_result_restart("completion")
	_test_result_restart("quest")
	_test_result_restart("cleanup")
	await _test_rewards_after_retry()
	_test_pvp_result_atomic()
	fixture.restore()
	for suffix in ["", ".tmp", ".unreadable"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _test_malformed_profile() -> void:
	var raw := Codec.starter_profile()
	raw["stats"] = {"games_played": [], "wins": "corrompu", "losses": -8,
		"total_captures": INF, "per_npc": {"bad": [], "ok": {"games": 3.0, "wins": {}}}}
	raw["inventory"]["souls"] = {}
	raw["inventory"]["candles"] = "invalide"
	var profile := Codec.decode(raw)
	var stats: Dictionary = profile["stats"]
	_check(stats["games_played"] == 0 and stats["wins"] == 0 and stats["losses"] == 0
		and stats["total_captures"] == 0 and not stats.has("per_npc")
		and profile["inventory"]["souls"] == 0,
		"sauvegarde : les types et nombres non finis sont nettoyés avant les calculs")


func _test_future_profile() -> void:
	var raw := Codec.starter_profile()
	raw["save_version"] = Codec.VERSION + 1
	raw["future_field"] = {"must_survive": true}
	Storage.write(PATH, raw)
	var before := FileAccess.get_file_as_string(PATH)
	var isolated := Profile.new(PATH)
	isolated.load_save()
	_check(isolated.profile_load_error == ERR_UNAVAILABLE and isolated.save() == ERR_UNAVAILABLE
		and "version plus récente" in isolated.profile_load_notice
		and FileAccess.get_file_as_string(PATH) == before,
		"sauvegarde : une version future reste intacte après une tentative d'écriture")
	isolated.free()


func _test_future_campaign() -> void:
	Storage.write(PATH, {"progress_version": Progress.PROGRESS_VERSION + 1,
		"campaign_version": 90, "future_field": {"must_survive": true}})
	var before := FileAccess.get_file_as_string(PATH)
	var service := Service.create_default(PATH)
	var store := Store.new(PATH)
	_check(not service.is_ready() and service.load_error() == ERR_UNAVAILABLE
		and store.load_progress() == null,
		"progression : un schéma futur est détecté avant la conversion de campagne")
	_check(store.save(Progress.new()) == ERR_UNAVAILABLE
		and not service.begin_attempt("tuto_01")["ok"]
		and FileAccess.get_file_as_string(PATH) == before,
		"progression : une écriture directe et une nouvelle tentative préservent le fichier futur")
	DirAccess.remove_absolute(PATH)


func _test_ledger_compaction() -> void:
	var inventory := Inventory.new()
	for attempt in range(1, 1001):
		inventory.mark_transaction("campaign:6:level:replay:%d" % attempt)
		for round_index in [1, 2, 3]:
			inventory.mark_transaction("quest:campaign:6:level:%d:%d" % [attempt, round_index])
	var loaded := Inventory.from_dict(inventory.to_dict())
	_check(loaded.applied_transactions.is_empty() and loaded.transaction_cursors.size() == 2
		and loaded.has_transaction("campaign:6:level:replay:999")
		and loaded.has_transaction("quest:campaign:6:level:1000:2")
		and not loaded.has_transaction("quest:campaign:6:level:1001:1"),
		"transactions : 4 000 actions ordonnées occupent deux curseurs sans rouvrir les doublons")
	var legacy := Inventory.from_dict({"applied_transactions": {
		"quest:campaign:6:level:5": true, "campaign:6:level:replay:8": true}})
	_check(legacy.has_transaction("quest:campaign:6:level:5")
		and not legacy.has_transaction("quest:campaign:6:level:5:1")
		and legacy.has_transaction("campaign:6:level:replay:8"),
		"transactions : la migration conserve les anciennes preuves sans supprimer les nouvelles manches")


func _test_atomic_upgrade() -> void:
	PlayerData._apply_profile(Codec.starter_profile())
	var inventory := Inventory.from_dict(PlayerData.inventory_dict())
	var lineage := MonsterLoader.monster_lineage(str(PlayerData.get_active_deck()[0]))
	inventory.souls = 10000
	inventory.cards[lineage]["copies"] = 1000
	PlayerData.commit_inventory(inventory)
	var before := PlayerData.get_profile()
	var path: String = PlayerData._save_path
	PlayerData._save_path = "user://absent-audit-folder/profile.json"
	_expect_log("PlayerData: profil non enregistré")
	var failed := Economy.new().upgrade_card(lineage)
	PlayerData._save_path = path
	_check(not bool(failed.get("ok", false)) and PlayerData.get_profile() == before,
		"achat : une panne ne consomme ni monnaie ni copies et ne compte aucune quête")
	var result := Economy.new().upgrade_card(lineage)
	var counters: Dictionary = PlayerData.quests_dict().get("counters", {})
	_check(bool(result.get("ok", false)) and int(counters.get("upgrades", 0)) == 1
		and int(counters.get("souls_spent", 0)) == int(result.get("spent_souls", -1)),
		"achat : l'amélioration et ses compteurs sont écrits dans la même transaction")


func _test_invalid_deck_rollback() -> void:
	var before := PlayerData.get_profile()
	var inventory := Inventory.from_dict(PlayerData.inventory_dict())
	inventory.souls += 100
	var error := PlayerData.commit_economy(inventory, ["unknown_card"], {"counters": {"upgrades": 999}})
	_check(error == ERR_INVALID_DATA and PlayerData.get_profile() == before,
		"transaction : un deck invalide restaure aussi l'état des quêtes")


func _test_result_retry(fail_completion: bool) -> void:
	PlayerData._apply_profile(Codec.starter_profile())
	var store := FaultStore.new(PATH)
	var graph: CampaignGraph = Graph.build(Content.read()["definition"])
	var service := Service.new(graph, Progress.new(), store, [])
	service.begin_attempt("tuto_01")
	store.fail_next = fail_completion
	_quest_attempts = 0
	var result := {"npc_id": "audit", "winner": 1, "score_local": 9,
		"score_opponent": 4, "captures": 3, "campaign_victory": true, "round_index": 1}
	var recorder := Persistence.new(result, service, "tuto_01",
		Callable() if fail_completion else _fail_quest_once)
	var first := recorder.persist()
	var paid := PlayerData.souls()
	var reward := recorder.reward.duplicate(true)
	_check(first == ERR_FILE_CANT_WRITE and paid > 0,
		"résultat : une panne tardive conserve la récompense déjà versée")
	var again := recorder.persist()
	_check(again == OK and PlayerData.souls() == paid and recorder.reward["souls"] == reward["souls"]
		and int(PlayerData.stats["games_played"]) == 1 and service.is_completed("tuto_01")
		and int(PlayerData.quests_dict().get("counters", {}).get("captures", 0)) == 3,
		"résultat : réessayer ne change ni récompense, ni statistiques, ni captures")


func _fail_quest_once(kind: String, payload: Dictionary, key: String) -> Error:
	_quest_attempts += 1
	if _quest_attempts == 1:
		return ERR_FILE_CANT_WRITE
	return Quests.new().record_event(kind, payload, key)


func _test_result_restart(checkpoint: String) -> void:
	PlayerData._apply_profile(Codec.starter_profile())
	PlayerData.save()
	var store := FaultStore.new(PATH)
	var graph: CampaignGraph = Graph.build(Content.read()["definition"])
	var service := Service.new(graph, Progress.new(), store, [])
	service.begin_attempt("tuto_01")
	CampaignContext.set_service_for_tests(service)
	var starter_souls := PlayerData.souls()
	var quest_recorder := Callable()
	if checkpoint == "completion":
		store.fail_next = true
	elif checkpoint == "quest":
		_quest_attempts = 0
		quest_recorder = _fail_quest_once
	else:
		quest_recorder = _save_quest_before_cleanup_failure
	var result := {"npc_id": "audit", "winner": 1, "score_local": 5,
		"score_opponent": 4, "captures": 3, "campaign_victory": true, "round_index": 1}
	var recorder := Persistence.new(result, service, "tuto_01", quest_recorder)
	var failed := recorder.persist()
	var awarded_souls := PlayerData.souls() - starter_souls
	var paid_inventory := PlayerData.inventory_dict()
	_check(failed == ERR_FILE_CANT_WRITE and awarded_souls > 0
		and not PlayerData.pending_campaign_result().is_empty(),
		"reprise après %s : l'intention et le reçu restent enregistrés" % checkpoint)
	recorder = null
	service = null
	PlayerData.load_save()
	var pending: Dictionary = PlayerData.pending_campaign_result()
	_check(int(pending.get("reward", {}).get("souls", 0)) == awarded_souls,
		"reprise après %s : le profil relu contient le montant exact" % checkpoint)
	var reloaded := Service.create_default(PATH, {"unused": true})
	CampaignContext.set_service_for_tests(reloaded)
	var recovered := CampaignContext.recover_pending_result()
	var paid_after := PlayerData.inventory_dict()
	_check(recovered == OK and reloaded.is_completed("tuto_01")
		and int(PlayerData.stats["games_played"]) == 1
		and PlayerData.souls() == starter_souls + awarded_souls
		and paid_after["cards"] == paid_inventory["cards"]
		and paid_after["candles"] == paid_inventory["candles"]
		and int(PlayerData.quests_dict().get("counters", {}).get("captures", 0)) == 3,
		"reprise après %s : niveau, gains et compteurs appliqués une seule fois" % checkpoint)
	PlayerData.load_save()
	_check(PlayerData.pending_campaign_result().is_empty()
		and CampaignContext.recover_pending_result() == OK
		and int(PlayerData.stats["games_played"]) == 1,
		"reprise après %s : un deuxième redémarrage ne rejoue rien" % checkpoint)
	CampaignContext.reset_for_tests()


func _save_quest_before_cleanup_failure(kind: String, payload: Dictionary, key: String) -> Error:
	var error := Quests.new().record_event(kind, payload, key)
	if error == OK:
		PlayerData.profile_load_error = ERR_FILE_CANT_WRITE
	return error


func _test_rewards_after_retry() -> void:
	PlayerData._apply_profile(Codec.starter_profile())
	var service := Service.new(Graph.build(Content.read()["definition"]), Progress.new(), Store.new(PATH))
	service.begin_attempt("tuto_01")
	CampaignContext.set_service_for_tests(service)
	BattleContext.enter_campaign_node("tuto_01", service)
	BattleContext.prepare_result(GameState.PLAYER_HUMAN, 5, 4, 3)
	var before := PlayerData.get_profile()
	var profile_path: String = PlayerData._save_path
	PlayerData._save_path = PATH + "/profile.json"
	_expect_log("PlayerData: profil non enregistré")
	var failed := BattleContext.persist_result()
	PlayerData._save_path = profile_path
	var page := ResultScene.instantiate()
	add_child(page)
	await get_tree().process_frame
	_check(failed != OK and PlayerData.get_profile() == before
		and PlayerData.pending_campaign_result().is_empty()
		and page.retry_save_btn.visible and not page.rewards.visible,
		"résultat : l'échec du premier enregistrement ne publie ni gains ni reçu")
	page.retry_save_btn.pressed.emit()
	_check(BattleContext.last_result_saved and page.rewards.visible
		and page.reward_soul_row.visible and not page.retry_save_btn.visible,
		"résultat : les gains apparaissent sur le même écran après le réessai")
	page.queue_free()
	await get_tree().process_frame
	BattleContext.clear_campaign_node()
	CampaignContext.reset_for_tests()


func _test_pvp_result_atomic() -> void:
	PlayerData._apply_profile(Codec.starter_profile())
	var context := PvpContext.new()
	context.match_id = "audit-pvp-result"
	context.local_side = GameState.PLAYER_TWO
	context.record_result(GameState.PLAYER_TWO, 0, 16)
	context.prepare_profile_result(3, 2, 4)
	var before := PlayerData.get_profile()
	var profile_path: String = PlayerData._save_path
	PlayerData._save_path = PATH + "/profile.json"
	_expect_log("PlayerData: profil non enregistré")
	var failed := context.persist_profile_result()
	PlayerData._save_path = profile_path
	_check(failed != OK and PlayerData.get_profile() == before,
		"résultat PVP : une panne n'enregistre ni statistiques ni quêtes")
	var saved := context.persist_profile_result()
	context.prepare_profile_result(3, 2, 4)
	var duplicate := context.persist_profile_result()
	var counters: Dictionary = PlayerData.quests_dict().get("counters", {})
	_check(saved == OK and duplicate == OK and int(PlayerData.stats["games_played"]) == 1
		and int(counters.get("pvp_matches", 0)) == 1 and int(counters.get("perfect_rounds", 0)) == 1,
		"résultat PVP : le réessai enregistre ensemble la manche et les deux compteurs une seule fois")
	context.free()
