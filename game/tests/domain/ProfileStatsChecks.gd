extends "res://tests/support/CombatTestSuite.gd"

const Rules := preload("res://scripts/domain/ProfileStatsRules.gd")
const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")
const Storage := preload("res://scripts/data/PlayerSaveStorage.gd")
const Service := preload("res://scripts/application/campaign/CampaignService.gd")
const Player := preload("res://scripts/data/PlayerData.gd")
const Migration := preload("res://scripts/application/campaign/CampaignSaveMigration.gd")
const PATH := "user://profile_stats_campaign_checks.json"


func run() -> void:
	_test_old_profile()
	_test_results()
	_test_invalid_stats()
	_test_legacy_conversion()
	_test_failed_conversion()
	_test_failed_cleanup()
	await _test_profile_screen()
	await _test_pvp_local_result()


func _test_old_profile() -> void:
	var raw := Codec.starter_profile()
	raw["save_version"] = 11
	raw["stats"] = {"games_played": 12, "wins": 7, "losses": 4, "draws": 1,
		"total_captures": 38, "best_streak": 3,
		"per_npc": {"bot_veskar_n1_facile": {"wins": 1, "games": 2}}}
	var profile := Codec.decode(raw)
	var stats: Dictionary = profile["stats"]
	_check(stats["games_played"] == 12 and stats["total_captures"] == 38
		and stats["by_scope"]["campaign"]["wins"] == 7,
		"profil : les totaux historiques sont conservés et attribués à la campagne")
	_check(not stats.has("per_npc") and stats["by_god"].is_empty()
		and stats["by_mode"].is_empty() and stats["best_move_captures"] == 0,
		"profil : aucun résultat par dieu ni record historique n'est inventé")
	_check(profile["legacy_campaign_stats"] == {"per_npc": raw["stats"]["per_npc"]}
		and Codec.decode(profile) == profile,
		"profil : la conversion reste disponible après une sauvegarde et est idempotente")


func _test_results() -> void:
	var result := {"scope": "pvp", "player_god_id": "ilyr", "mode": "mirror",
		"winner": 1, "score_local": 14, "score_opponent": 0, "board_size": 4,
		"captures": 9, "best_move_captures": 3}
	var stats := Rules.record_match({}, result, "pvp:client-side-two")
	_check(stats["wins"] == 1 and stats["by_scope"]["pvp"]["games_played"] == 1
		and stats["by_god"]["ilyr"]["wins"] == 1
		and stats["by_god"]["pvp:ilyr"]["wins"] == 1
		and stats["by_mode"]["mirror"]["wins"] == 1,
		"profil : le dieu et le mode réellement joués sont comptés dans le bon contexte")
	_check(stats["perfect_rounds"] == 1 and stats["best_move_captures"] == 3
		and stats["best_round_captures"] == 9,
		"profil : un contrôle total sur plateau avec cases condamnées compte")
	_check(Rules.record_match(stats, result, "pvp:client-side-two") == stats,
		"profil : un résultat réessayé n'est jamais compté deux fois")
	result.merge({"scope": "campaign", "player_god_id": "", "mode": "draft",
		"winner": 2, "score_local": 3, "score_opponent": 11}, true)
	stats = Rules.record_match(stats, result, "campaign:1:node:1:1")
	_check(stats["games_played"] == 2 and stats["losses"] == 1
		and stats["current_streak"] == 0 and stats["best_streak"] == 1
		and stats["by_god"]["godless"]["losses"] == 1
		and stats["by_scope"]["pvp"]["wins"] == 1,
		"profil : la campagne, le PVP et le jeu sans dieu restent distincts")
	result.merge({"winner": 0, "score_local": 7, "score_opponent": 7}, true)
	stats = Rules.record_match(stats, result, "campaign:1:node:1:2")
	_check(stats["draws"] == 1 and Rules.win_rate(stats) == 33,
		"profil : les égalités comptent comme des manches, y compris en série")
	result.merge({"winner": 1, "score_local": 9, "score_opponent": 0, "board_size": 3}, true)
	stats = Rules.record_match(stats, result)
	_check(stats["perfect_rounds"] == 1,
		"profil : les petits plateaux guidés ne gonflent pas les contrôles totaux")


func _test_invalid_stats() -> void:
	var stats := Rules.normalize({"wins": INF, "by_god": {"ilyr": {"wins": [],
		"games_played": 3.0}, "broken": []}, "by_scope": [], "recent_results": [1, "ok", "ok"]})
	_check(stats["wins"] == 0 and stats["by_god"]["ilyr"]["wins"] == 0
		and stats["by_god"]["ilyr"]["games_played"] == 3
		and not stats["by_god"].has("broken") and stats["recent_results"] == ["ok"],
		"profil : des données malformées ne cassent ni les statistiques ni leur affichage")


func _test_legacy_conversion() -> void:
	_remove_campaign_file()
	var fixture := ProfileFixture.new()
	var service := Service.create_default(PATH, {"unused": true})
	var node_id := ""
	var legacy_id := ""
	var claims := {}
	for node in service.graph().nodes():
		var id := Migration.legacy_opponent_id(node)
		if id != "":
			claims[id] = int(claims.get(id, 0)) + 1
	for node in service.graph().nodes():
		var id := Migration.legacy_opponent_id(node)
		if id != "" and claims[id] == 1:
			node_id = node.id
			legacy_id = id
			break
	_remove_campaign_file()
	PlayerData.legacy_campaign_stats = {"per_npc": {legacy_id: {"wins": 1}}}
	_check(PlayerData.save() == OK and node_id != "", "profil : une ancienne victoire est préparée")
	service = Service.create_default(PATH)
	_check(service.is_ready() and service.is_completed(node_id)
		and PlayerData.legacy_campaign_stats.is_empty()
		and not Storage.read(ProfileFixture.PATH).has("legacy_campaign_stats"),
		"profil : la victoire est convertie avant le retrait des anciens adversaires du profil")
	var reloaded := Service.create_default(PATH)
	_check(reloaded.is_completed(node_id), "profil : la progression convertie survit au redémarrage")
	fixture.restore()
	_remove_campaign_file()


func _test_failed_cleanup() -> void:
	var player := Player.new("user://missing_profile_stats/checks/profile.json")
	player.legacy_campaign_stats = {"per_npc": {"old": {"wins": 1}}}
	player.profile_load_error = ERR_FILE_CANT_WRITE
	_check(player.finish_campaign_migration() != OK
		and not player.legacy_campaign_stats.is_empty(),
		"profil : un échec de nettoyage garde les données de conversion en mémoire")
	player.free()


func _test_failed_conversion() -> void:
	var fixture := ProfileFixture.new()
	_remove_campaign_file()
	PlayerData.legacy_campaign_stats = {"per_npc": {"old_opponent": {"wins": 1}}}
	_check(PlayerData.save() == OK, "profil : la source historique est sauvegardée avant conversion")
	var before := Storage.read(ProfileFixture.PATH)
	var blocker := FileAccess.open(PATH, FileAccess.WRITE)
	blocker.store_string("blocked")
	blocker.close()
	var service := Service.create_default(PATH + "/cannot_write.json")
	_check(not service.is_ready() and not PlayerData.legacy_campaign_stats.is_empty()
		and Storage.read(ProfileFixture.PATH) == before,
		"profil : une conversion impossible laisse la sauvegarde historique intacte")
	fixture.restore()
	_remove_campaign_file()


func _test_profile_screen() -> void:
	var fixture := ProfileFixture.new()
	var service := Service.create_default(PATH, {"unused": true})
	CampaignContext.set_service_for_tests(service)
	PlayerData.record_match({"scope": "pvp", "winner": 1, "player_god_id": "ilyr", "mode": "random"})
	var page: Control = load("res://scenes/menus/Stats.tscn").instantiate()
	add_child(page)
	await get_tree().process_frame
	_check(not page.has_node("Root/Scroll/Content/NPCPanel") and page._sections.size() > 8,
		"profil : les chemins 0/15 sont remplacés par la progression et les nouvelles statistiques")
	var picker: OptionButton = page.get_node("Root/Scroll/Content/StatsScope")
	picker.select(2)
	picker.item_selected.emit(2)
	_check(page._scope_stats().get("wins", 0) == 1,
		"profil : le filtre PVP montre uniquement ses résultats")
	picker.select(1)
	picker.item_selected.emit(1)
	_check(page._scope_stats().get("wins", 0) == 0,
		"profil : le filtre campagne n'inclut pas les victoires PVP")
	page.queue_free()
	await get_tree().process_frame
	CampaignContext.reset_for_tests()
	fixture.restore()
	_remove_campaign_file()


func _test_pvp_local_result() -> void:
	var fixture := ProfileFixture.new()
	PvpMatchContext.match_id = "profile-stats-pvp-check"
	PvpMatchContext.local_side = GameState.PLAYER_TWO
	PvpMatchContext.local_god_id = "ilyr"
	PvpMatchContext.match_rules = {"mode": "random"}
	PvpMatchContext.record_result(GameState.PLAYER_TWO, 4, 10)
	PvpMatchContext.prepare_profile_result(5, 2, 4)
	PvpMatchContext.persist_profile_result()
	PvpMatchContext.persist_profile_result()
	_check(PlayerData.stats["wins"] == 1 and PlayerData.stats["by_scope"]["pvp"]["wins"] == 1
		and PlayerData.stats["by_god"]["ilyr"]["wins"] == 1
		and PvpMatchContext.last_result["profile_result"]["score_local"] == 10,
		"profil : le résultat du client PVP est enregistré une seule fois")
	PvpMatchContext.match_id = "profile-stats-pvp-retry"
	PvpMatchContext.record_result(GameState.PLAYER_NONE, 7, 7)
	PvpMatchContext.prepare_profile_result(2, 1, 4)
	var previous_error := PlayerData.profile_load_error
	PlayerData.profile_load_error = ERR_FILE_CANT_WRITE
	_check(PvpMatchContext.persist_profile_result() != OK
		and not PvpMatchContext.last_result["profile_saved"] and PlayerData.stats["games_played"] == 1,
		"profil : un résultat PVP reste disponible après un échec d'écriture")
	PlayerData.profile_load_error = previous_error
	_check(PvpMatchContext.persist_profile_result() == OK and PlayerData.stats["draws"] == 1
		and PvpMatchContext.persist_profile_result() == OK and PlayerData.stats["games_played"] == 2,
		"profil : le réessai PVP sauvegarde une seule égalité et aucune défaite")
	PvpMatchContext.clear()
	fixture.restore()


func _remove_campaign_file() -> void:
	for suffix in ["", ".tmp", ".unreadable"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)
