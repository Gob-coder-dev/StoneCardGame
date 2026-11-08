## Flux complet d'une campagne : tentative, résultat Classique, série FT2,
## victoire différée, idempotence et écran de résultat sans navigation réelle.
extends "res://tests/support/CombatTestSuite.gd"

const ContentLoader := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const StoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const ServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")
const PATH := "user://campaign_flow_checks.json"

var _service: CampaignService = null
var _fixture: ProfileFixture = null


func run() -> void:
	_cleanup()
	_fixture = ProfileFixture.new()
	var content := ContentLoader.read()
	if not bool(content.get("ok", false)):
		_check(false, "flux campagne : le contenu est valide")
		_fixture.restore()
		return
	var graph: CampaignGraph = GraphModel.build(content["definition"])
	var progress := ProgressModel.new()
	for node_id in ["tuto_01", "tuto_02", "tuto_03", "veskar_01"]:
		progress.mark_completed(node_id)
	_service = ServiceModel.new(graph, progress, StoreModel.new(PATH), [])
	CampaignContext.set_service_for_tests(_service)
	_test_classic_result_once()
	_test_series_defers_completion()
	await _test_result_screens()
	await _test_preparation_scene()
	BattleContext.clear_campaign_node()
	CampaignContext.reset_for_tests()
	_fixture.restore()
	_cleanup()


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".unreadable"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _enter(node_id: String) -> void:
	var result := CampaignContext.enter_node(node_id)
	_check(bool(result.get("ok", false)), "flux campagne : '%s' démarre" % node_id)
	if not bool(result.get("ok", false)):
		printerr("  ", result.get("reason", ""))


func _test_classic_result_once() -> void:
	_enter("tuto_01")
	var npc_id := str(BattleContext.current_opponent().get("id", ""))
	var games_before := int(PlayerData.npc_record(npc_id).get("games", 0))
	BattleContext.prepare_result(GameState.PLAYER_HUMAN, 9, 4, 2)
	var first := BattleContext.persist_result()
	_check(first == OK and BattleContext.last_result_saved
		and _service.is_completed("tuto_01"),
		"flux campagne : une victoire Classique termine le nœud et confirme la sauvegarde")
	var games_after := int(PlayerData.npc_record(npc_id).get("games", 0))
	_check(games_after == games_before + 1,
		"flux campagne : la première sauvegarde enregistre une partie")
	var again := BattleContext.persist_result()
	_check(again == OK and int(PlayerData.npc_record(npc_id).get("games", 0)) == games_after,
		"flux campagne : réessayer un résultat déjà sauvé ne compte pas une seconde partie")
	_check(_service.progress().attempts_for("tuto_01") == 1,
		"flux campagne : une tentative est enregistrée avec le nœud")
	BattleContext.clear_campaign_node()


func _test_series_defers_completion() -> void:
	_enter("veskar_02")
	_check(BattleContext.campaign_series_pending(),
		"flux campagne : Aléatoire FT2 ouvre une série non terminée")
	BattleContext.record_mode_round(GameState.PLAYER_HUMAN, 9, 4)
	BattleContext.prepare_result(GameState.PLAYER_HUMAN, 9, 4, 2)
	var first_saved := BattleContext.persist_result()
	_check(first_saved == OK and BattleContext.last_result_saved
		and not _service.is_completed("veskar_02")
		and BattleContext.campaign_series_pending(),
		"flux campagne : une manche gagnée n'est pas une victoire de nœud avant la fin de série")
	_check(BattleContext.campaign_series_pending()
		and not BattleContext.campaign_victory_confirmed(),
		"flux campagne : la série reste ouverte après la première manche")
	var next := BattleContext.prepare_next_mode_round()
	_check(bool(next.get("ok", false)),
		"flux campagne : la manche suivante prépare de nouveaux loadouts")
	BattleContext.record_mode_round(GameState.PLAYER_HUMAN, 8, 5)
	BattleContext.prepare_result(GameState.PLAYER_HUMAN, 8, 5, 1)
	var final_saved := BattleContext.persist_result()
	_check(final_saved == OK and BattleContext.last_result_saved
		and _service.is_completed("veskar_02")
		and not BattleContext.campaign_series_pending(),
		"flux campagne : la victoire du nœud n'est publiée qu'à la fin de la série")
	BattleContext.clear_campaign_node()


func _test_result_screens() -> void:
	# Une défaite ne termine pas le nœud et ne propose pas de suite.
	_enter("nerava_01")
	BattleContext.prepare_result(GameState.PLAYER_AI, 4, 9, 0)
	BattleContext.persist_result()
	var defeat: Control = (load("res://scenes/menus/Result.tscn") as PackedScene).instantiate()
	add_child(defeat)
	await get_tree().process_frame
	_check(not defeat.next_btn.visible and defeat.replay_btn.visible
		and defeat.level_btn.text == "Carte de campagne" and not defeat.gods_btn.visible,
		"résultat campagne : une défaite propose de rejouer et de revenir à la carte")
	_check(not _service.is_completed("nerava_01"),
		"résultat campagne : une défaite ne valide jamais le nœud")
	defeat.queue_free()
	await get_tree().process_frame
	BattleContext.clear_campaign_node()

	# Une égalité ne valide pas davantage le nœud.
	_enter("kharun_01")
	BattleContext.prepare_result(GameState.PLAYER_NONE, 5, 5, 0)
	BattleContext.persist_result()
	var draw_page: Control = (load("res://scenes/menus/Result.tscn") as PackedScene).instantiate()
	add_child(draw_page)
	await get_tree().process_frame
	_check(draw_page.result_label.text == "ÉGALITÉ" and not draw_page.next_btn.visible
		and draw_page.replay_btn.visible and not _service.is_completed("kharun_01"),
		"résultat campagne : une égalité ne valide pas le nœud et propose une revanche")
	draw_page.queue_free()
	await get_tree().process_frame
	BattleContext.clear_campaign_node()

	# Une série gagnée affiche le retour à la carte, pas une nouvelle manche.
	_enter("veskar_02")
	BattleContext.record_mode_round(GameState.PLAYER_HUMAN, 9, 3)
	BattleContext.record_mode_round(GameState.PLAYER_HUMAN, 9, 2)
	BattleContext.prepare_result(GameState.PLAYER_HUMAN, 9, 2, 3)
	BattleContext.persist_result()
	var victory: Control = (load("res://scenes/menus/Result.tscn") as PackedScene).instantiate()
	add_child(victory)
	await get_tree().process_frame
	_check(victory.next_btn.visible and victory.next_btn.text == "Retour à la carte",
		"résultat campagne : une série terminée ramène à la carte unifiée")
	_check(victory.level_btn.text == "Carte de campagne" and not victory.gods_btn.visible,
		"résultat campagne : les anciennes sorties par dieu sont remplacées")
	victory.queue_free()
	await get_tree().process_frame


func _test_preparation_scene() -> void:
	_enter("veskar_02")
	var random_page: Control = (load("res://scenes/campaign/CampaignPreparation.tscn") as PackedScene).instantiate()
	add_child(random_page)
	await get_tree().process_frame
	_check(random_page.deck_grid.get_child_count() == DeckRules.DECK_SIZE
		and random_page.opponent_grid.get_child_count() == DeckRules.DECK_SIZE
		and not random_page.confirm_button.disabled,
		"préparation campagne : Aléatoire affiche les deux loadouts prêts et autorise le lancement")
	random_page.queue_free()
	await get_tree().process_frame
	BattleContext.clear_campaign_node()

	# Le draft est derrière la convergence : un seul prédécesseur suffit (ANY).
	_service.complete_node("nerava_01")
	_enter("convergence_01")
	var draft_page: Control = (load("res://scenes/campaign/CampaignPreparation.tscn") as PackedScene).instantiate()
	add_child(draft_page)
	await get_tree().process_frame
	_check(draft_page.offers_grid.visible
		and draft_page.offers_grid.get_child_count() == 2
		and draft_page.confirm_button.disabled
		and draft_page.deck_title.text.contains("0 / 8"),
		"préparation campagne : Sélection charge les deux offres locales avant le draft")
	draft_page.queue_free()
	await get_tree().process_frame
	BattleContext.clear_campaign_node()
