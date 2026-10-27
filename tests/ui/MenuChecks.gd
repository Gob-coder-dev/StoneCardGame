extends "res://tests/support/CombatTestSuite.gd"
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")
const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")

func run() -> void:
	var fixture := ProfileFixture.new()
	await _test_god_selector_ui()
	await _test_deck_slots()
	await _test_home_portraits()
	await _test_preview_layout()
	await _test_rules_legends()
	await _test_collection_incremental_refresh()
	_test_cost_format()
	await _test_hud_game_over()
	await _test_hand_keeps_remaining_cards()
	_test_first_player_draw()
	await _test_prebattle_reveals_draw()
	await _test_generated_opponent_battle()
	await _test_result_uses_generated_opponent()
	fixture.restore()


func _test_preview_layout() -> void:
	var page: Control = load("res://scenes/menus/CollectionScreen.tscn").instantiate()
	add_child(page)
	page._commit_operation({"success": true, "deck": ProfileFixture.DECK.slice(0, 6)})
	for frame in range(6):
		await get_tree().process_frame
	var rows: VBoxContainer = page.get_node("Content/Scroll/Page/DeckPanel/DeckContent/DeckRows")
	var wrapper: VBoxContainer = rows.get_child(0).get_child(0)
	var card: StoneCard = wrapper.get_child(0)
	var empty: Control = rows.get_child(1).get_child(3).get_child(0)
	_check(absf(card.size.x - card.size.y) <= 1.0 and absf(card.size.y - empty.size.y) <= 1.0,
		"les emplacements remplis et vides du deck occupent des carrés de même taille")
	page._on_info_requested("f01_n1")
	for frame in range(6):
		await get_tree().process_frame
	var info: StoneInfoSheet = page.info_sheet
	var bounds := info.card_container.get_global_rect()
	var preview: Control = info.card_container.get_child(0)
	_check(bounds.size.y > 0 and bounds.encloses(preview.get_global_rect())
		and is_equal_approx(preview.size.x, bounds.size.x)
		and is_equal_approx(preview.size.x, preview.size.y)
		and bounds.position.y >= info.stats_label.get_global_rect().end.y,
		"la grande carte utilise la largeur de la fiche sans recouvrir les informations")
	var explanation_badge: Control = info.power_badges.get_child(0) if info.power_badges.get_child_count() > 0 else null
	_check(explanation_badge != null and info.power_badges.get_child_count() == 1
		and explanation_badge.kind == "fortune" and explanation_badge.count == 4
		and explanation_badge.size.y >= 90.0 and info._card._power_badge_scale > 1.0,
		"la fiche agrandit le logo sur la carte et le répète lisiblement devant son explication")
	page.queue_free()
	await get_tree().process_frame
	var rules: Control = load("res://scenes/menus/HowToPlay.tscn").instantiate()
	add_child(rules)
	for frame in range(3):
		await get_tree().process_frame
	var scroll: ScrollContainer = rules.get_node("Content/Scroll")
	scroll.scroll_vertical = 100000
	await get_tree().process_frame
	var end: Control = rules.get_node("Content/Scroll/RulesPanel/Page/EndText")
	_check(scroll.get_global_rect().end.y - end.get_global_rect().end.y >= UITheme.RULES_END_SPACE,
		"les règles peuvent défiler au-delà de la dernière ligne pour laisser une marge de lecture")
	rules.queue_free()
	await get_tree().process_frame


func _test_home_portraits() -> void:
	var original_god := PlayerData.player_god_id
	var menu: Control = load("res://scenes/menus/MainMenu.tscn").instantiate()
	add_child(menu)
	var all_portraits_loaded := true
	var all_identities_match := true
	for god in StoneLoader.get_all_gods():
		PlayerData.player_god_id = str(god["id"])
		menu._refresh()
		var texture: Texture2D = menu.god_portrait.texture
		all_portraits_loaded = all_portraits_loaded and texture != null
		all_identities_match = all_identities_match and menu.god_name.text == str(god["name"]).to_upper()
		all_identities_match = all_identities_match and menu.god_family.text == god["family_name"]
	_check(all_portraits_loaded and all_identities_match,
		"l'accueil charge les six portraits livrés avec le jeu et suit l'identité du dieu actif")
	_check(menu.god_portrait.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and menu.get_node("Background").mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"le portrait et le décor du refuge laissent passer les gestes vers les commandes")
	for frame in range(6):
		await get_tree().process_frame
	var status: Label = menu.deck_status
	var font := status.get_theme_font("font")
	var widest_status := font.get_string_size("Deck 3 • 8/8 cartes • 79,75/80 points",
		HORIZONTAL_ALIGNMENT_LEFT, -1, status.get_theme_font_size("font_size")).x
	_check(not status.text.contains("\n") and status.get_line_count() == 1
		and widest_status <= status.size.x,
		"le numéro, les cartes et les points du deck tiennent sur une ligne à la taille de police courante")
	PlayerData.player_god_id = original_god
	menu.queue_free()
	await get_tree().process_frame

func _test_god_selector_ui() -> void:
	var scene: PackedScene = load("res://scenes/menus/CollectionScreen.tscn")
	var page: Control = scene.instantiate()
	add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame
	var button: Button = page.get_node("Content/Scroll/Page/GodDeckPanel/GodDeckContent/GodDeckRow/GodButton")
	var menu: PanelContainer = page.get_node("Content/Scroll/Page/GodMenu")
	var options: GridContainer = page.get_node("Content/Scroll/Page/GodMenu/GodOptions")
	page.sort_button.pressed.emit()
	await get_tree().process_frame
	button.pressed.emit()
	await get_tree().process_frame
	var portraits_loaded := true
	for option in options.get_children():
		portraits_loaded = portraits_loaded and option.get_node("Content/Portrait").has_portrait()
	_check(menu.visible and options.columns == 3 and options.get_child_count() == 6 and portraits_loaded,
		"le tiroir affiche les six portraits de dieux sur deux rangées de trois")
	_check(page.god_portrait.has_portrait() and page.god_name.text == "VÉSKAR"
		and page.get_node("Content/Scroll/Page/GodDeckPanel/GodDeckContent/GodDeckRow/IdentityDeck/DeckSlots").get_child_count() == 3,
		"le panneau associe un grand portrait à l'identité du dieu et à ses trois decks")
	_check(not page.sort_menu.visible and page.sort_button.text.ends_with("▼"),
		"ouvrir le menu des dieux referme le tri et remet sa flèche vers le bas")
	page.queue_free()
	await get_tree().process_frame


func _test_rules_legends() -> void:
	var scene: PackedScene = load("res://scenes/menus/HowToPlay.tscn")
	var page: Control = scene.instantiate()
	add_child(page)
	await get_tree().process_frame
	var legends: VBoxContainer = page.get_node("Content/Scroll/RulesPanel/Page/GodRules")
	var kinds := {}
	for row in legends.get_children():
		if row is HBoxContainer:
			var badge: Control = row.get_child(0)
			kinds[badge.kind] = true
	var all_documented := true
	for stone in StoneLoader.get_all_stones():
		for badge in Symbols.badges_for(stone):
			all_documented = all_documented and kinds.has(badge["kind"])
	_check(all_documented and kinds.size() == 9, "les règles montrent et expliquent tous les pictogrammes utilisés sur les cartes")
	var texts: Array[String] = [page.get_node("Content/Scroll/RulesPanel/Page/RulesText").text]
	for row in legends.get_children():
		if row is HBoxContainer:
			texts.append(row.get_child(1).text)
	var all_text := "\n".join(texts)
	_check(not all_text.contains("{") and all_text.contains("coûte %s point" % UIFormat.cost(StoneCostRules.LONG_BLADE_COST))
		and all_text.contains("jusqu'à +%d" % StoneEffects.SWARM_CAP),
		"les règles affichent les valeurs lues dans le code")
	_check(all_text.contains("Commune ivoire") and all_text.contains("Rare cyan")
		and all_text.contains("Épique violette") and all_text.contains("Légendaire dorée")
		and all_text.contains("bleu pour ton camp") and all_text.contains("rouge pour l'adversaire"),
		"les règles expliquent les quatre raretés et les couleurs de propriété du plateau")
	page.queue_free()
	await get_tree().process_frame


func _test_deck_slots() -> void:
	var page: Control = (load("res://scenes/menus/CollectionScreen.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	var slots: HBoxContainer = page.get_node(
		"Content/Scroll/Page/GodDeckPanel/GodDeckContent/GodDeckRow/IdentityDeck/DeckSlots")
	_check(slots.get_child_count() == 3 and slots.get_child(0).text == "1"
		and slots.get_child(1).text == "2" and slots.get_child(2).text == "3"
		and slots.get_child(0).button_pressed and not page.status_label.visible,
		"la collection affiche seulement trois boutons numérotés, avec le deck actif sélectionné")
	var cards := _collection_cards(page)
	slots.get_child(1).pressed.emit()
	await get_tree().process_frame
	_check(PlayerData.get_selected_deck() == 1 and page._current_deck.is_empty()
		and slots.get_child(1).button_pressed and not slots.get_child(0).button_pressed,
		"choisir un numéro ouvre un deck vide et déplace la sélection")
	page._on_primary_requested("f03_n1", CardActionDrawer.Source.COLLECTION)
	await get_tree().process_frame
	_check(PlayerData.get_active_deck() == ["f03_n1"] and not _shown_collection_ids(page).has("f03_n1")
		and not page.status_label.visible and _collection_cards(page)["f03_n1"] == cards["f03_n1"]
		and PlayerData.get_deck("inari", 0) == ProfileFixture.DECK,
		"modifier le deuxième deck masque sa carte sans recréer la collection ni afficher de message de succès")
	page._on_primary_requested("f03_n1", CardActionDrawer.Source.DECK)
	_check(PlayerData.get_active_deck().is_empty() and _shown_collection_ids(page).has("f03_n1"),
		"retirer une carte agit seulement sur le deck sélectionné")
	page._select_deck(0)
	page._on_primary_requested("n01_n4", CardActionDrawer.Source.COLLECTION)
	_check(page.replacement_panel.visible, "un deck complet ouvre le remplacement depuis le deck sélectionné")
	page._on_replacement_requested("f03_n1")
	_check(not page.replacement_panel.visible and PlayerData.get_active_deck().has("n01_n4")
		and not PlayerData.get_active_deck().has("f03_n1") and PlayerData.get_deck("inari", 1).is_empty(),
		"le remplacement immédiat enregistre uniquement l'emplacement courant")
	# Restaurer la composition initiale, puis vérifier les changements de contexte.
	page._commit_operation(DeckRules.try_replace(page._current_deck, "n01_n4", "f03_n1", "inari"))
	page._select_deck(2)
	page._on_primary_requested("f07_n1", CardActionDrawer.Source.COLLECTION)
	page._select_god("susanoo")
	_check(page._current_deck.is_empty() and PlayerData.get_selected_deck() == 0,
		"changer de dieu ouvre sa banque sans copier le deck précédent")
	page._select_deck(1)
	page._on_primary_requested("p08_n1", CardActionDrawer.Source.COLLECTION)
	page._select_god("inari")
	_check(page._current_deck == ["f07_n1"] and PlayerData.get_selected_deck() == 2
		and PlayerData.get_deck("susanoo", 1) == ["p08_n1"],
		"revenir à un dieu retrouve son dernier deck et préserve les autres banques")
	var menu: Control = (load("res://scenes/menus/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	_check(menu.deck_status.text.contains("Deck 3") and menu.deck_status.text.contains("1/8")
		and menu.play_button.text == "COMPLÉTER MON DECK", "l'accueil lit le numéro actif et refuse un deck incomplet")
	menu.queue_free()
	# Un ancien panneau ne doit jamais pouvoir modifier le nouveau deck.
	page._replacement_stone_id = "n12_n2"
	page.replacement_panel.open_for(page._current_deck, "n12_n2")
	page._select_deck(0)
	_check(not page.replacement_panel.visible and page._replacement_stone_id == "",
		"changer d'emplacement ferme le remplacement et annule sa carte en attente")
	var save_path: String = PlayerData._save_path
	PlayerData._save_path = save_path + "/missing/profile.json"
	_expect_log("PlayerData: profil non enregistré")
	page._select_deck(2)
	_check(page.status_label.visible and page.status_label.text.contains("échoué")
		and PlayerData.get_selected_deck() == 0 and slots.get_child(0).button_pressed
		and page._current_deck == ProfileFixture.DECK, "une erreur disque est visible et conserve le deck précédent dans l'interface")
	PlayerData._save_path = save_path
	# Les tests suivants retrouvent le même profil de départ.
	page._select_deck(1)
	PlayerData.set_player_deck([])
	page._select_deck(2)
	PlayerData.set_player_deck([])
	page._select_deck(0)
	page.queue_free()
	await get_tree().process_frame
	await _test_battle_uses_selected_deck()


func _test_battle_uses_selected_deck() -> void:
	var saved_npc := BattleContext.selected_npc_id
	var saved_first := BattleContext.forced_first_player
	PlayerData.set_selected_deck(2)
	var reordered := ProfileFixture.DECK.duplicate()
	reordered.reverse()
	PlayerData.set_player_deck(reordered)
	BattleContext.selected_npc_id = "hiro"
	BattleContext.forced_first_player = GameState.PLAYER_HUMAN
	var board: Control = (load("res://scenes/game/Board.tscn") as PackedScene).instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var state: GameState = board.turn_manager.get_state()
	_check(state.hand_of(GameState.PLAYER_HUMAN) == reordered and state.god_of(GameState.PLAYER_HUMAN) == "inari",
		"un vrai combat reçoit les huit cartes du troisième deck et le dieu sélectionné")
	board.queue_free()
	await get_tree().process_frame
	BattleContext.selected_npc_id = saved_npc
	BattleContext.forced_first_player = saved_first
	PlayerData.set_player_deck([])
	PlayerData.set_selected_deck(0)


func _test_generated_opponent_battle() -> void:
	var saved_npc := BattleContext.selected_npc_id
	var saved_opponent := BattleContext.selected_opponent
	var saved_first := BattleContext.forced_first_player
	var opponent := OpponentCatalogModel.build("susanoo", "n1", "moyen")
	BattleContext.select_opponent(opponent)
	BattleContext.forced_first_player = GameState.PLAYER_HUMAN
	PlayerData.set_selected_deck(0)
	PlayerData.set_player_deck(ProfileFixture.DECK.duplicate())
	var board: Control = (load("res://scenes/game/Board.tscn") as PackedScene).instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var state: GameState = board.turn_manager.get_state()
	_check(state.npc_id == opponent["id"]
		and state.god_of(GameState.PLAYER_AI) == "susanoo"
		and state.hand_of(GameState.PLAYER_AI) == StoneLoader.build_hand(opponent["deck"]),
		"un combat généré reçoit le deck, le dieu et l'identifiant de la rencontre choisie")
	board.queue_free()
	await get_tree().process_frame
	BattleContext.selected_npc_id = saved_npc
	BattleContext.selected_opponent = saved_opponent
	BattleContext.forced_first_player = saved_first
	PlayerData.set_player_deck([])
	PlayerData.set_selected_deck(0)


func _test_result_uses_generated_opponent() -> void:
	var saved_id := BattleContext.selected_npc_id
	var saved_opponent := BattleContext.selected_opponent
	var saved_winner := BattleContext.last_winner
	var saved_human := BattleContext.last_score_human
	var saved_ai := BattleContext.last_score_ai
	var opponent := OpponentCatalogModel.build("izanami", "n2", "tres_difficile")
	BattleContext.select_opponent(opponent)
	BattleContext.record_result(GameState.PLAYER_HUMAN, 42, 17)
	var page: Control = (load("res://scenes/menus/Result.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	_check(page.result_label.text == "VICTOIRE !"
		and page.score_label.text.contains(opponent["name"])
		and page.score_label.text.contains("42") and page.score_label.text.contains("17"),
		"l'écran de résultat affiche le nom et le score de la rencontre générée")
	page.queue_free()
	await get_tree().process_frame
	BattleContext.selected_npc_id = saved_id
	BattleContext.selected_opponent = saved_opponent
	BattleContext.record_result(saved_winner, saved_human, saved_ai)


func _test_cost_format() -> void:
	_check(UIFormat.cost(11.5) == "11,5" and UIFormat.cost(8.0) == "8",
		"les coûts s'affichent avec la virgule française, sans décimale inutile")
	_check(UIFormat.cost(1.25) == "1,25" and UIFormat.cost(3.75) == "3,75"
		and UIFormat.cost(8.25) == "8,25", "les quarts de point ne sont jamais arrondis à un dixième")
	_check(UIFormat.cost(StoneLoader.stone_cost("h06_n1")) == "3,75"
		and UIFormat.cost(StoneLoader.stone_cost("h05_n3")) == "10,75",
		"les coûts des cartes Horizon affichent exactement le coût du catalogue")


func _test_hand_keeps_remaining_cards() -> void:
	var hand := HandView.new()
	add_child(hand)
	var full_height := hand.custom_minimum_size.y
	_check(hand.columns == UITheme.DECK_COLUMNS and is_equal_approx(full_height, 468.0),
		"la main réserve deux rangées de quatre cartes à sa construction")
	hand.refresh(["fx_plain", "fx_attack2", "fx_wall"])
	var kept_first: StoneCard = hand.get_child(0).get_child(0)
	var kept_last: StoneCard = hand.get_child(2).get_child(0)
	hand.refresh(["fx_plain", "fx_wall"])
	_check(hand.get_child_count() == 2 and hand.get_child(0).get_child(0) == kept_first
		and hand.get_child(1).get_child(0) == kept_last and hand.custom_minimum_size.y == full_height,
		"jouer une carte retire seulement celle-ci de la main")
	hand.refresh(["fx_target"])
	_check(hand.get_child_count() == 1 and hand.get_child(0).get_child(0).get_stone_id() == "fx_target",
		"une nouvelle main est reconstruite")
	hand.queue_free()
	await get_tree().process_frame


func _test_first_player_draw() -> void:
	seed(2026)
	var drawn := {}
	for attempt in range(40):
		drawn[BoardSetupGenerator.draw_first_player()] = true
	randomize()
	_check(drawn.size() == 2 and drawn.has(GameState.PLAYER_HUMAN) and drawn.has(GameState.PLAYER_AI),
		"le tirage du premier joueur donne les deux camps, et seulement eux")


func _test_prebattle_reveals_draw() -> void:
	var saved_npc := BattleContext.selected_npc_id
	var saved_first := BattleContext.forced_first_player
	BattleContext.selected_npc_id = "hiro"
	BattleContext.forced_first_player = 0
	var page: Control = (load("res://scenes/menus/PreBattle.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	_check(page.player_god_portrait.has_portrait() and page.opponent_god_portrait.has_portrait()
		and page.player_god_name.text == "TOI • Véskar"
		and page.opponent_god_name.text == "LUI • Kharûn",
		"l'avant-combat présente les portraits et l'identité des deux dieux autour de la pièce")
	await get_tree().create_timer(1.6).timeout
	var first := BattleContext.forced_first_player
	var face: String = page.coin_label.text
	_check((first == GameState.PLAYER_HUMAN and face == "TOI") or (first == GameState.PLAYER_AI and face == "LUI"),
		"l'écran d'avant-combat révèle et transmet le premier joueur tiré")
	_check(not page.start_button.disabled, "le combat peut commencer une fois la pièce retombée")
	page.queue_free()
	BattleContext.selected_npc_id = saved_npc
	BattleContext.forced_first_player = saved_first
	await get_tree().process_frame


func _test_hud_game_over() -> void:
	var hud := BattleHUD.new()
	add_child(hud)
	hud.set_names("Joueur", "Hiro")
	hud.set_gods(StoneLoader.get_god("inari"), StoneLoader.get_god("hachiman"))
	hud.set_active_player(GameState.PLAYER_HUMAN)
	hud.set_game_over()
	_check(hud._banner.text == "Partie terminée" and hud._center.text == "VS",
		"en fin de partie, le bandeau n'annonce plus le tour d'un joueur")
	_check(hud._human_portrait.has_portrait() and hud._ai_portrait.has_portrait()
		and hud._human_god.text == "Véskar" and hud._ai_god.text == "Kharûn",
		"le HUD conserve l'image et le nom du dieu de chaque camp pendant le combat")
	hud.queue_free()
	await get_tree().process_frame


## Les cartes du deck sont absentes de la collection ; une carte retirée du
## deck y revient. Ces changements visuels ne modifient pas le profil.
func _test_collection_incremental_refresh() -> void:
	var scene: PackedScene = load("res://scenes/menus/CollectionScreen.tscn")
	var page: Control = scene.instantiate()
	add_child(page)
	await get_tree().process_frame
	var cards := _collection_cards(page)
	var expected: Array = []
	for definition in StoneLoader.get_lineages_for_god("inari"):
		if DeckRules.lineage_index(PlayerData.get_active_deck(), StoneLoader.stone_lineage(definition["id"])) < 0:
			expected.append(definition["id"])
	var shown := _shown_collection_ids(page)
	var shown_sorted := shown.duplicate()
	shown_sorted.sort()
	expected.sort()
	_check(cards.size() == StoneLoader.get_lineages_for_god("inari").size() and shown_sorted == expected,
		"la collection n'affiche pas les cartes déjà dans le deck")
	# Tri FAMILLE par défaut : la première carte est la moins chère d'Inari.
	_check(page._sort_mode == 0 and page.sort_button.text.begins_with("TRIER : FAMILLE")
		and str(StoneLoader.get_stone(shown[0])["god_id"]) == "inari" and _is_family_order(shown, "inari"),
		"par défaut, les cartes du dieu passent avant les neutres, chaque groupe par coût puis par nom")
	var kappa: StoneCard = cards["f03_n1"]
	var identity := kappa.get_instance_id()
	var without_kappa: Array = PlayerData.get_active_deck()
	without_kappa.erase("f03_n1")
	page._current_deck = without_kappa
	page._refresh_all()
	await get_tree().process_frame
	var grid: GridContainer = page.collection_rows.get_child(0)
	shown = _shown_collection_ids(page)
	# Kappa revient à la place que lui donnent son coût et son nom.
	_check(shown.has("f03_n1") and _is_family_order(shown, "inari")
		and is_instance_valid(kappa) and kappa.get_instance_id() == identity and not kappa._selected,
		"une carte retirée du deck revient à sa place dans la collection, sans recréer de carte")
	page._select_sort(3)
	await get_tree().process_frame
	var by_name := _shown_collection_ids(page)
	_check(page.sort_button.text.begins_with("TRIER : NOM")
		and _names_ascending(by_name) and not _is_family_order(by_name, "inari"),
		"le tri par nom mélange de nouveau cartes du dieu et neutres")
	page._select_sort(0)
	await get_tree().process_frame
	grid = page.collection_rows.get_child(0)
	page._current_deck = without_kappa + ["n01_n4"]
	page._refresh_all()
	await get_tree().process_frame
	var visible_wrappers: Array = []
	for wrapper in grid.get_children():
		if wrapper.visible:
			visible_wrappers.append(wrapper)
	# Izanagi masqué, les cartes visibles restent alignées sur trois colonnes.
	_check(not _shown_collection_ids(page).has("n01_n1") and visible_wrappers.size() == expected.size()
		and is_equal_approx(visible_wrappers[3].position.x, visible_wrappers[0].position.x)
		and visible_wrappers[3].position.y > visible_wrappers[0].position.y,
		"une carte ajoutée au deck disparaît et la grille referme le trou")
	page.queue_free()
	await get_tree().process_frame


## Toutes les cartes du dieu d'abord, puis les neutres, chaque groupe par
## coût croissant puis par nom.
func _is_family_order(ids: Array, god_id: String) -> bool:
	var seen_neutral := false
	var group: Array = []
	for stone_id in ids:
		var neutral := str(StoneLoader.get_stone(stone_id).get("god_id", "neutral")) == "neutral"
		if neutral and not seen_neutral:
			if not _cost_then_name_ascending(group):
				return false
			group = []
			seen_neutral = true
		elif not neutral and seen_neutral:
			return false
		if not neutral and str(StoneLoader.get_stone(stone_id)["god_id"]) != god_id:
			return false
		group.append(stone_id)
	return _cost_then_name_ascending(group)


func _cost_then_name_ascending(ids: Array) -> bool:
	for index in range(1, ids.size()):
		var previous_cost := StoneLoader.stone_cost(ids[index - 1])
		var current_cost := StoneLoader.stone_cost(ids[index])
		if previous_cost > current_cost:
			return false
		if is_equal_approx(previous_cost, current_cost) and not _names_ascending([ids[index - 1], ids[index]]):
			return false
	return true


func _names_ascending(ids: Array) -> bool:
	for index in range(1, ids.size()):
		var previous := str(StoneLoader.get_stone(ids[index - 1])["name"])
		var current := str(StoneLoader.get_stone(ids[index])["name"])
		if previous.naturalnocasecmp_to(current) > 0:
			return false
	return true


func _collection_cards(page: Control) -> Dictionary:
	var cards := {}
	for wrapper in page.collection_rows.get_child(0).get_children():
		var card: StoneCard = wrapper.get_child(0)
		cards[card.get_stone_id()] = card
	return cards


func _shown_collection_ids(page: Control) -> Array:
	var ids: Array = []
	for wrapper in page.collection_rows.get_child(0).get_children():
		if wrapper.visible:
			ids.append(wrapper.get_child(0).get_stone_id())
	return ids
