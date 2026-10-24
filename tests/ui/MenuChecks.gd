extends "res://tests/support/CombatTestSuite.gd"
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")

func run() -> void:
	var fixture := ProfileFixture.new()
	await _test_god_selector_ui()
	await _test_deck_slots()
	await _test_rules_legends()
	await _test_collection_incremental_refresh()
	_test_cost_format()
	await _test_hud_game_over()
	await _test_hand_keeps_remaining_cards()
	_test_first_player_draw()
	await _test_prebattle_reveals_draw()
	fixture.restore()

func _test_god_selector_ui() -> void:
	var scene: PackedScene = load("res://scenes/menus/CollectionScreen.tscn")
	var page: Control = scene.instantiate()
	add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame
	var button: Button = page.get_node("Content/Scroll/Page/GodPanel/GodContent/GodButton")
	var menu: PanelContainer = page.get_node("Content/Scroll/Page/GodMenu")
	var options: VBoxContainer = page.get_node("Content/Scroll/Page/GodMenu/GodOptions")
	page.sort_button.pressed.emit()
	await get_tree().process_frame
	button.pressed.emit()
	await get_tree().process_frame
	_check(menu.visible and options.get_child_count() == 6, "le sélecteur affiche les six dieux dans le défilement")
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
	page.queue_free()
	await get_tree().process_frame


func _test_deck_slots() -> void:
	var page: Control = (load("res://scenes/menus/CollectionScreen.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	var slots: HBoxContainer = page.get_node("Content/Scroll/Page/DeckSlots")
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
	page._on_primary_requested("kappa", CardActionDrawer.Source.COLLECTION)
	await get_tree().process_frame
	_check(PlayerData.get_active_deck() == ["kappa"] and not _shown_collection_ids(page).has("kappa")
		and not page.status_label.visible and _collection_cards(page)["kappa"] == cards["kappa"]
		and PlayerData.get_deck("inari", 0) == ProfileFixture.DECK,
		"modifier le deuxième deck masque sa carte sans recréer la collection ni afficher de message de succès")
	page._on_primary_requested("kappa", CardActionDrawer.Source.DECK)
	_check(PlayerData.get_active_deck().is_empty() and _shown_collection_ids(page).has("kappa"),
		"retirer une carte agit seulement sur le deck sélectionné")
	page._select_deck(0)
	page._on_primary_requested("izanagi", CardActionDrawer.Source.COLLECTION)
	_check(page.replacement_panel.visible, "un deck complet ouvre le remplacement depuis le deck sélectionné")
	page._on_replacement_requested("kappa")
	_check(not page.replacement_panel.visible and PlayerData.get_active_deck().has("izanagi")
		and not PlayerData.get_active_deck().has("kappa") and PlayerData.get_deck("inari", 1).is_empty(),
		"le remplacement immédiat enregistre uniquement l'emplacement courant")
	# Restaurer la composition initiale, puis vérifier les changements de contexte.
	page._commit_operation(DeckRules.try_replace(page._current_deck, "izanagi", "kappa", "inari"))
	page._select_deck(2)
	page._on_primary_requested("tanuki", CardActionDrawer.Source.COLLECTION)
	page._select_god("susanoo")
	_check(page._current_deck.is_empty() and PlayerData.get_selected_deck() == 0,
		"changer de dieu ouvre sa banque sans copier le deck précédent")
	page._select_deck(1)
	page._on_primary_requested("samurai_red", CardActionDrawer.Source.COLLECTION)
	page._select_god("inari")
	_check(page._current_deck == ["tanuki"] and PlayerData.get_selected_deck() == 2
		and PlayerData.get_deck("susanoo", 1) == ["samurai_red"],
		"revenir à un dieu retrouve son dernier deck et préserve les autres banques")
	var menu: Control = (load("res://scenes/menus/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	_check(menu.deck_status.text.contains("Deck 3") and menu.deck_status.text.contains("1/8")
		and menu.play_button.text == "COMPLÉTER MON DECK", "l'accueil lit le numéro actif et refuse un deck incomplet")
	menu.queue_free()
	# Un ancien panneau ne doit jamais pouvoir modifier le nouveau deck.
	page._replacement_stone_id = "kitsune"
	page.replacement_panel.open_for(page._current_deck, "kitsune")
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


func _test_cost_format() -> void:
	_check(UIFormat.cost(11.5) == "11,5" and UIFormat.cost(8.0) == "8",
		"les coûts s'affichent avec la virgule française, sans décimale inutile")
	_check(UIFormat.cost(1.25) == "1,25" and UIFormat.cost(3.75) == "3,75"
		and UIFormat.cost(8.25) == "8,25", "les quarts de point ne sont jamais arrondis à un dixième")
	_check(UIFormat.cost(StoneLoader.stone_cost("hayabusa")) == "3,75"
		and UIFormat.cost(StoneLoader.stone_cost("tengu")) == "10,75",
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
	hud.set_active_player(GameState.PLAYER_HUMAN)
	hud.set_game_over()
	_check(hud._banner.text == "Partie terminée" and hud._center.text == "VS",
		"en fin de partie, le bandeau n'annonce plus le tour d'un joueur")
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
	for definition in StoneLoader.get_stones_for_god("inari"):
		if not PlayerData.get_active_deck().has(definition["id"]):
			expected.append(definition["id"])
	var shown := _shown_collection_ids(page)
	var shown_sorted := shown.duplicate()
	shown_sorted.sort()
	expected.sort()
	_check(cards.size() == StoneLoader.get_stones_for_god("inari").size() and shown_sorted == expected,
		"la collection n'affiche pas les cartes déjà dans le deck")
	# Tri FAMILLE par défaut : Bakeneko est la première carte d'Inari par son nom.
	_check(page._sort_mode == 0 and page.sort_button.text.begins_with("TRIER : FAMILLE")
		and shown[0] == "bakeneko" and _is_family_order(shown, "inari"),
		"par défaut, les cartes du dieu passent avant les neutres, chacune par ordre alphabétique")
	var kappa: StoneCard = cards["kappa"]
	var identity := kappa.get_instance_id()
	var without_kappa: Array = PlayerData.get_active_deck()
	without_kappa.erase("kappa")
	page._current_deck = without_kappa
	page._refresh_all()
	await get_tree().process_frame
	var grid: GridContainer = page.collection_rows.get_child(0)
	shown = _shown_collection_ids(page)
	# Kappa revient entre Kamaitachi et Maneki-neko.
	_check(shown.find("kappa") == shown.find("kamaitachi") + 1 and _is_family_order(shown, "inari")
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
	page._current_deck = without_kappa + ["izanagi"]
	page._refresh_all()
	await get_tree().process_frame
	var visible_wrappers: Array = []
	for wrapper in grid.get_children():
		if wrapper.visible:
			visible_wrappers.append(wrapper)
	# Izanagi masqué, les cartes visibles restent alignées sur trois colonnes.
	_check(not _shown_collection_ids(page).has("izanagi") and visible_wrappers.size() == expected.size()
		and is_equal_approx(visible_wrappers[3].position.x, visible_wrappers[0].position.x)
		and visible_wrappers[3].position.y > visible_wrappers[0].position.y,
		"une carte ajoutée au deck disparaît et la grille referme le trou")
	page.queue_free()
	await get_tree().process_frame


## Toutes les cartes du dieu d'abord, puis les neutres, chaque groupe par nom.
func _is_family_order(ids: Array, god_id: String) -> bool:
	var seen_neutral := false
	var group: Array = []
	for stone_id in ids:
		var neutral := str(StoneLoader.get_stone(stone_id).get("god_id", "neutral")) == "neutral"
		if neutral and not seen_neutral:
			if not _names_ascending(group):
				return false
			group = []
			seen_neutral = true
		elif not neutral and seen_neutral:
			return false
		if not neutral and str(StoneLoader.get_stone(stone_id)["god_id"]) != god_id:
			return false
		group.append(stone_id)
	return _names_ascending(group)


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
