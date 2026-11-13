## Flux complet d'une campagne : tentative, résultat Classique, série FT2,
## victoire différée, idempotence et écran de résultat sans navigation réelle.
extends "res://tests/support/CombatTestSuite.gd"

const ContentLoader := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const StoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const ServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")
const EncounterPresenter := preload("res://scripts/ui/campaign/CampaignEncounterPresenter.gd")
const SeriesEngineModel := preload("res://scripts/domain/SeriesEngine.gd")
const SeriesStateModel := preload("res://scripts/domain/SeriesState.gd")
const SeriesPresenter := preload("res://scripts/ui/result/SeriesResultPresenter.gd")
const PATH := "user://campaign_flow_checks.json"
const SERIES_NODE := "r08_m1"
const RESULT_SERIES_NODE := "r09_m"
const RESULT_NEXT_NODE := "r09_exit"

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
	# Le test de flux cible une série située après les jalons. Tous ses
	# prédécesseurs sont donc préparés, sans prévalider les rencontres dont
	# le verdict est testé ci-dessous.
	for node in graph.nodes():
		if not [SERIES_NODE, "r08_exit", RESULT_SERIES_NODE, RESULT_NEXT_NODE,
				"nerava_01", "kharun_01"].has(node.id):
			progress.mark_completed(node.id)
	_service = ServiceModel.new(graph, progress, StoreModel.new(PATH), [])
	CampaignContext.set_service_for_tests(_service)
	_test_classic_result_once()
	_test_series_defers_completion()
	_test_series_result_view()
	await _test_mid_series_abandon()
	await _test_result_screens()
	await _test_next_level_grid_layout()
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
	_enter(SERIES_NODE)
	_check(BattleContext.campaign_series_pending(),
		"flux campagne : Aléatoire FT2 ouvre une série non terminée")
	BattleContext.record_mode_round(GameState.PLAYER_HUMAN, 9, 4)
	BattleContext.prepare_result(GameState.PLAYER_HUMAN, 9, 4, 2)
	var first_saved := BattleContext.persist_result()
	_check(first_saved == OK and BattleContext.last_result_saved
		and not _service.is_completed(SERIES_NODE)
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
		and _service.is_completed(SERIES_NODE)
		and not BattleContext.campaign_series_pending(),
		"flux campagne : la victoire du nœud n'est publiée qu'à la fin de la série")
	BattleContext.clear_campaign_node()


## Le présentateur sert les deux modes : titre de manche, score du round, score
## de série encadré et objectif FT2, sans aucun écran.
func _test_series_result_view() -> void:
	var series := SeriesStateModel.create("check", {"mode": "random", "series": "ft2"}, 11)
	SeriesEngineModel.record_round(series, GameState.PLAYER_ONE, 9, 4)
	var mid := SeriesPresenter.view(SeriesEngineModel.public_state(series),
		{"winner": GameState.PLAYER_ONE, "score_one": 9, "score_two": 4},
		GameState.PLAYER_ONE, "Toi", "Veskàr")
	_check(str(mid["title"]) == "MANCHE 1 GAGNÉE"
		and str(mid["round_score"]) == "Toi 9  —  4 Veskàr"
		and str(mid["score"]) == "Toi 1  —  0 Veskàr"
		and str(mid["caption"]) == "Mode de jeu : Aléatoire • FT2 : premier à 2"
		and not bool(mid["finished"]),
		"série : une manche affiche son verdict, son score et l'objectif FT2")
	SeriesEngineModel.record_round(series, GameState.PLAYER_NONE, 5, 5)
	var draw := SeriesPresenter.view(SeriesEngineModel.public_state(series),
		{"winner": GameState.PLAYER_NONE, "score_one": 5, "score_two": 5},
		GameState.PLAYER_ONE, "Toi", "Veskàr")
	_check(str(draw["title"]) == "MANCHE 2 ÉGALITÉ" and str(draw["score"]) == "Toi 1  —  0 Veskàr",
		"série : une manche nulle ne marque aucun point")
	SeriesEngineModel.record_round(series, GameState.PLAYER_ONE, 9, 3)
	var final := SeriesPresenter.view(SeriesEngineModel.public_state(series),
		{"winner": GameState.PLAYER_ONE, "score_one": 9, "score_two": 3},
		GameState.PLAYER_ONE, "Toi", "Veskàr")
	_check(str(final["title"]) == "VICTOIRE !" and str(final["score"]) == "Toi 2  —  0 Veskàr",
		"série : la dernière manche garde le verdict classique et le score final")


## En cours de série : verdict de manche, score encadré, et seulement « Manche
## suivante » et « Abandonner ». Un abandon concède la série et compte une
## défaite ; une nouvelle entrée repart sur une série neuve.
func _test_mid_series_abandon() -> void:
	_enter(SERIES_NODE)
	var losses_before := int(PlayerData.stats.get("losses", 0))
	BattleContext.record_mode_round(GameState.PLAYER_HUMAN, 9, 6)
	BattleContext.prepare_result(GameState.PLAYER_HUMAN, 9, 6, 2)
	BattleContext.persist_result()
	var page: Control = (load("res://scenes/menus/Result.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	_check(page.result_label.text == "MANCHE 1 GAGNÉE"
		and page.series_card.visible
		and page.series_card._score_label.text == "%s 1  —  0 %s" % [
			page._player_name, page._opponent_name]
		and page.next_btn.visible and page.next_btn.text == "Manche suivante"
		and page.abandon_btn.visible and not page.replay_btn.visible
		and not page.level_btn.visible and not page.menu_btn.visible,
		"résultat campagne : une manche de série propose la suite ou l'abandon, jamais Rejouer")
	_check(page.abandon_btn.get_theme_color("font_color") != UITheme.COL_DANGER
		and page.abandon_btn.get_theme_color("font_color").get_luminance() > 0.4,
		"résultat campagne : l'abandon reste lisible sur le fond sombre")
	page.abandon_btn.pressed.emit()
	_check(page.abandon_popup.visible and page.abandon_popup.is_open()
		and page.abandon_popup.message_label.text
			== "Voulez-vous vraiment abandonner et perdre la partie ?",
		"résultat campagne : abandonner demande d'abord confirmation")
	page.abandon_popup.no_btn.pressed.emit()
	_check(not page.abandon_popup.visible and page.result_label.text == "MANCHE 1 GAGNÉE"
		and BattleContext.campaign_series_pending(),
		"résultat campagne : refuser l'abandon laisse la série en cours")
	page.abandon_btn.pressed.emit()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	page.abandon_popup._gui_input(click)
	_check(not page.abandon_popup.visible and BattleContext.campaign_series_pending(),
		"résultat campagne : un clic à côté de la confirmation n'abandonne pas")
	page.abandon_btn.pressed.emit()
	page.abandon_popup.yes_btn.pressed.emit()
	await get_tree().process_frame
	_check(page.result_label.text == "DÉFAITE..."
		and page.series_card.visible
		and page.series_card._score_label.text == "%s 1  —  2 %s" % [
			page._player_name, page._opponent_name]
		and page.series_card._note_label.text == "Série abandonnée"
		and page.replay_btn.visible and page.level_btn.visible and page.menu_btn.visible
		and not page.abandon_btn.visible and not page.next_btn.visible,
		"résultat campagne : abandonner concède la série et rouvre les sorties de fin")
	_check(int(PlayerData.stats.get("losses", 0)) == losses_before + 1,
		"résultat campagne : l'abandon compte une défaite pour le joueur")
	page.queue_free()
	await get_tree().process_frame
	_enter(SERIES_NODE)
	_check(BattleContext.campaign_series_pending()
		and int(BattleContext.campaign_series_state().get("wins_one", -1)) == 0,
		"résultat campagne : une nouvelle entrée repart sur une série neuve")
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
	_enter(RESULT_SERIES_NODE)
	BattleContext.record_mode_round(GameState.PLAYER_HUMAN, 9, 3)
	BattleContext.record_mode_round(GameState.PLAYER_HUMAN, 9, 2)
	BattleContext.prepare_result(GameState.PLAYER_HUMAN, 9, 2, 3)
	BattleContext.persist_result()
	var victory: Control = (load("res://scenes/menus/Result.tscn") as PackedScene).instantiate()
	add_child(victory)
	await get_tree().process_frame
	var random_summary := EncounterPresenter.summary(
		_service.node(RESULT_SERIES_NODE), "nerava")
	_check(str(random_summary.get("opponent_god_label", "")) == "Adversaire",
		"présentateur : un mode Aléatoire sans dieu imposé ne répète pas le mode comme dieu")
	_check(not victory.next_btn.visible,
		"résultat campagne : la victoire ne duplique plus la sortie vers la carte")
	_check(victory.level_btn.text == "Carte de campagne" and not victory.gods_btn.visible,
		"résultat campagne : les anciennes sorties par dieu sont remplacées")
	_check(victory.next_levels.visible
		and victory.next_levels_title.text == "NIVEAU SUIVANT"
		and victory.next_levels_rows.get_child_count() == 1
		and victory.next_levels_rows.get_child(0).get_child_count() == 1,
		"résultat campagne : la victoire propose le niveau suivant sous forme de carte")
	_check(victory.result_label.text == "VICTOIRE !" and victory.series_card.visible
		and victory.series_card._score_label.text == "%s 2  —  0 %s" % [
			victory._player_name, victory._opponent_name]
		and victory.series_card._caption_label.text.contains("FT2 : premier à 2")
		and victory.replay_btn.visible and victory.level_btn.visible and victory.menu_btn.visible
		and not victory.abandon_btn.visible,
		"résultat campagne : la fin de série garde le menu victoire et le score final")
	var next_card: Button = victory.next_levels_rows.get_child(0).get_child(0)
	var card_style := next_card.get_theme_stylebox("normal") as StyleBoxFlat
	_check(victory.next_levels.get_theme_stylebox("panel") is StyleBoxFlat
		and victory.next_levels_title.get_theme_font_size("font_size") == 36
		and card_style != null and card_style.border_width_left == 5,
		"résultat campagne : le bloc est encadré, le titre agrandi, les contours renforcés")
	var card_content := next_card.get_child(0)
	_check(str(card_content.get_child(0).text) != ""
		and str(card_content.get_child(1).text) != "",
		"résultat campagne : la carte affiche le dieu à combattre et le mode")
	var requested_paths: Array[String] = []
	victory.scene_changer = func(path: String) -> void: requested_paths.append(path)
	next_card.pressed.emit()
	_check(requested_paths == [Routes.CAMPAIGN_MAP]
		and CampaignContext.requested_node() == RESULT_NEXT_NODE,
		"résultat campagne : une carte demande la fiche du niveau sans lancer le combat")
	CampaignContext.take_requested_node()
	victory.queue_free()
	await get_tree().process_frame


## Trois successeurs : deux cartes sur la première ligne, la troisième seule et
## centrée sur la seconde. Vérifié sur la géométrie réelle, pas sur l'intention.
func _test_next_level_grid_layout() -> void:
	var page: Control = (load("res://scenes/menus/Result.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	page._clear_next_levels()
	page._build_next_level_cards([
		{"id": "a", "name": "Le Seuil", "opponent_god_label": "Veskàr",
			"mode_label": "Classique", "accent": "#ffffff"},
		{"id": "b", "name": "La Leçon", "opponent_god_label": "Nerava",
			"mode_label": "Miroir", "accent": "#ffffff"},
		{"id": "c", "name": "Le Premier Pas", "opponent_god_label": "Kharûn",
			"mode_label": "Aléatoire", "accent": "#ffffff"},
	])
	page.next_levels.visible = true
	for _frame in range(4):
		await get_tree().process_frame
	var rows: VBoxContainer = page.next_levels_rows
	_check(rows.get_child_count() == 2
		and rows.get_child(0).get_child_count() == 2
		and rows.get_child(1).get_child_count() == 1,
		"résultat : trois niveaux suivants forment deux lignes, deux puis une")
	var alone: Control = rows.get_child(1).get_child(0)
	var row_center := (rows.get_child(1) as Control).get_global_rect().get_center().x
	_check(absf(alone.get_global_rect().get_center().x - row_center) <= 1.0,
		"résultat : la carte seule de la seconde ligne est centrée")
	page.queue_free()
	await get_tree().process_frame


func _test_preparation_scene() -> void:
	_enter("init_veskar")
	var mirror_page: Control = (load("res://scenes/campaign/CampaignPreparation.tscn") as PackedScene).instantiate()
	add_child(mirror_page)
	await get_tree().process_frame
	await get_tree().process_frame
	var mirror_view = mirror_page.preparation_view
	_check(mirror_view.deck_grid.get_child_count() == DeckRules.DECK_SIZE
		and mirror_view.deck_grid.columns == 2
		and mirror_view.deck_title.text == "VOTRE DECK"
		and not mirror_page.status_label.visible
		and mirror_view.get_node_or_null("OpponentGrid") == null,
		"préparation campagne : Miroir montre uniquement le deck du joueur")
	mirror_page.queue_free()
	await get_tree().process_frame
	BattleContext.clear_campaign_node()

	_enter("r03_b")
	var random_page: Control = (load("res://scenes/campaign/CampaignPreparation.tscn") as PackedScene).instantiate()
	add_child(random_page)
	await get_tree().process_frame
	await get_tree().process_frame
	var random_view = random_page.preparation_view
	_check(random_view.deck_grid.get_child_count() == DeckRules.DECK_SIZE
		and random_view.deck_grid.columns == 2
		and random_view.deck_title.text == "VOTRE DECK"
		and not random_page.status_label.visible
		and not random_page.confirm_button.disabled,
		"préparation campagne : Aléatoire montre uniquement le deck du joueur")
	random_page.queue_free()
	await get_tree().process_frame
	BattleContext.clear_campaign_node()

	# Le draft est derrière la convergence : un seul prédécesseur suffit (ANY).
	_service.complete_node("nerava_01")
	_enter("r05_a1")
	var draft_page: Control = (load("res://scenes/campaign/CampaignPreparation.tscn") as PackedScene).instantiate()
	add_child(draft_page)
	await get_tree().process_frame
	var draft_view = draft_page.preparation_view
	var timer_before: String = draft_view.draft_timer.text
	draft_page._process(1.1)
	_check(draft_view.local_grid.visible
		and draft_view.local_grid.get_child_count() == 2
		and not draft_page.confirm_button.visible
		and draft_view.draft_deck_title.text.contains("0 / 8")
		and draft_view.draft_timer.visible
		and draft_view.draft_timer.text != timer_before,
		"préparation campagne : Sélection charge les deux offres locales avant le draft")
	draft_page.queue_free()
	await get_tree().process_frame
	BattleContext.clear_campaign_node()
