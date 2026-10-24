extends "res://tests/support/CombatTestSuite.gd"
const Fixture := preload("res://tests/support/PlayerProfileFixture.gd")
const Storage := preload("res://scripts/data/PlayerSaveStorage.gd")
const PlayerModel := preload("res://scripts/data/PlayerData.gd")

func run() -> void:
	var fixture := Fixture.new()
	var page: Control = (load("res://scenes/menus/CollectionScreen.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame
	_test_preview(page)
	_test_info_and_use(page)
	_test_replacement(page)
	_test_errors(page)
	page.queue_free()
	await get_tree().process_frame
	await _test_battle_level()
	fixture.restore()


func _card(page: Control, lineage: String) -> StoneCard:
	for wrapper in page.collection_rows.get_child(0).get_children():
		var card: StoneCard = wrapper.get_child(0)
		if StoneLoader.stone_lineage(card.get_stone_id()) == lineage:
			return card
	return null


func _test_preview(page: Control) -> void:
	var before := PlayerData.get_profile()
	var card := _card(page, "seed_balanced")
	page._select_preview_level(4)
	_check(card == _card(page, "seed_balanced") and card.get_stone_id() == "seed_balanced_n4"
		and _card(page, "seed_coin").get_stone_id() == "seed_coin_n3"
		and PlayerData.get_profile() == before, "le niveau global actualise les mêmes nœuds et sature chaque rareté sans modifier le profil")
	page._select_god("izanami")
	_check(_card(page, "seed_miasma").get_stone_id() == "seed_miasma_n2", "changer de dieu conserve le niveau d'aperçu et affiche le maximum épique")
	page._select_god("susanoo")
	_check(_card(page, "seed_thief").get_stone_id() == "seed_thief_n1", "la légendaire reste visible au niveau un avec le filtre quatre")
	page._select_god("inari")
	page._select_sort(1)
	var previous_cost := -1.0
	var sorted := true
	for wrapper in page.collection_rows.get_child(0).get_children():
		var cost := StoneLoader.stone_cost(wrapper.get_child(0).get_stone_id())
		sorted = sorted and cost >= previous_cost
		previous_cost = cost
	_check(sorted, "le tri utilise le coût de la forme affichée, y compris après un changement de dieu")
	page._select_deck(1)


func _test_info_and_use(page: Control) -> void:
	page._on_info_requested("seed_balanced_n4")
	var info: StoneInfoSheet = page.info_sheet
	var image_card := info.card_container.get_child(0)
	_check(info.visible and info._shown_variant == "seed_balanced_n4"
		and info.get_node("InfoPanel/InfoContent/Levels").get_child_count() == 4,
		"Infos ouvre la forme touchée avec ses quatre boutons de niveau")
	info._select_level(2)
	_check(info._shown_variant == "seed_balanced_n2" and info.summary_label.text.contains("8 points")
		and info.card_container.get_child(0) == image_card and PlayerData.get_active_deck().is_empty(),
		"parcourir les niveaux met à jour coût et grande carte sans enregistrer ni recréer l'illustration")
	info.use_button.pressed.emit()
	_check(not info.visible and PlayerData.get_active_deck() == ["seed_balanced_n2"]
		and Storage.read(Fixture.PATH)["decks_by_god"]["inari"][1] == ["seed_balanced_n2"]
		and not _card(page, "seed_balanced").get_parent().visible,
		"Utiliser enregistre exactement la forme consultée et masque sa lignée entière dans la collection")
	var reloaded := PlayerModel.new(Fixture.PATH)
	reloaded.load_save()
	_check(reloaded.get_active_deck() == ["seed_balanced_n2"] and reloaded.get_selected_deck() == 1,
		"un nouveau chargement du profil restaure le niveau réellement utilisé dans le bon deck")
	reloaded.free()
	page._on_info_requested("seed_balanced_n2")
	_check(info.use_button.disabled, "Utiliser est désactivé pour la forme déjà équipée")
	info._select_level(4)
	info.close_sheet()
	_check(PlayerData.get_active_deck() == ["seed_balanced_n2"], "fermer une fiche après consultation ne change pas le niveau équipé")
	page._on_info_requested("seed_balanced_n2")
	info._select_level(3)
	info.use_button.pressed.emit()
	_check(PlayerData.get_active_deck() == ["seed_balanced_n3"] and PlayerData.get_deck("inari", 0) == Fixture.DECK,
		"une autre forme remplace le même monstre au même emplacement dans le seul deck actif")


func _test_replacement(page: Control) -> void:
	page._commit_operation({"success": true, "deck": Fixture.DECK})
	page._on_info_requested("seed_balanced_n4")
	page.info_sheet.use_button.pressed.emit()
	_check(page.replacement_panel.visible and not page.info_sheet.visible
		and page._replacement_stone_id == "seed_balanced_n4", "un deck complet ouvre un unique panneau avec la forme exacte à insérer")
	page._select_preview_level(1)
	page._on_replacement_requested("kappa")
	_check(PlayerData.get_active_deck()[0] == "seed_balanced_n4" and not page.replacement_panel.visible,
		"le remplacement conserve le niveau choisi même si le filtre global change entre-temps")
	page._on_info_requested("seed_balanced_n4")
	_check(page.info_sheet._shown_variant == "seed_balanced_n4", "Infos depuis le deck ouvre le niveau équipé, indépendamment de la collection")
	page._select_deck(2)
	_check(not page.info_sheet.visible and page.info_sheet._shown_variant == "" and page._replacement_stone_id == "",
		"changer d'emplacement annule les aperçus et les actions de l'ancien deck")


func _test_errors(page: Control) -> void:
	var deck := ["seed_balanced_n1"]
	for index in range(7):
		_register("evo_menu_budget_%d" % index, 4, 4, 2, 0)
		deck.append("evo_menu_budget_%d" % index)
	page._commit_operation({"success": true, "deck": deck})
	page._on_info_requested("seed_balanced_n1")
	var info: StoneInfoSheet = page.info_sheet
	info._select_level(4)
	info.use_button.pressed.emit()
	_check(info.visible and info.error_label.visible and info.error_label.text.contains("Budget")
		and PlayerData.get_active_deck() == deck, "un niveau trop coûteux affiche son erreur dans la fiche ouverte et conserve le deck")
	info._select_level(2)
	var path: String = PlayerData._save_path
	PlayerData._save_path = path + "/missing/profile.json"
	_expect_log("PlayerData: profil non enregistré")
	info.use_button.pressed.emit()
	_check(info.visible and info.error_label.visible and info.error_label.text.contains("échoué")
		and PlayerData.get_active_deck() == deck, "une erreur disque reste visible dans Infos et n'équipe pas le nouveau niveau")
	PlayerData._save_path = path
	info.use_button.pressed.emit()
	_check(not info.visible and PlayerData.get_active_deck()[0] == "seed_balanced_n2", "réessayer après une erreur enregistre la même forme sans action fantôme")


func _test_battle_level() -> void:
	var saved_npc := BattleContext.selected_npc_id
	var saved_first := BattleContext.forced_first_player
	BattleContext.selected_npc_id = "hiro"
	BattleContext.forced_first_player = GameState.PLAYER_HUMAN
	var board: Control = (load("res://scenes/game/Board.tscn") as PackedScene).instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var state: GameState = board.turn_manager.get_state()
	var cell: Dictionary = RulesEngine.get_free_cells(state)[0]
	board.turn_manager.human_play(cell["row"], cell["col"], "seed_balanced_n2")
	await get_tree().process_frame
	var stone: BattleStone = state.get_cell(cell["row"], cell["col"])["stone"]
	_check(stone != null and stone.stone_id == "seed_balanced_n2" and stone.base_blades["top"] == 2,
		"le combat réel pose la forme sauvegardée avec ses statistiques exactes")
	board.queue_free()
	await get_tree().process_frame
	BattleContext.selected_npc_id = saved_npc
	BattleContext.forced_first_player = saved_first
