## Régressions tactiles avec de vrais événements routés par le Viewport.
## Exécuter : godot --headless --fixed-fps 60 --path . res://tests/TouchInputChecks.tscn
## Ne nécessite pas GUT et ne modifie pas la sauvegarde du joueur.
extends Node

const TestLog := preload("res://tests/support/TestLog.gd")
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")
const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const FakeTransport := preload("res://tests/support/FakeLanTransport.gd")
const SeriesCoordinatorModel := preload("res://scripts/network/LanSeriesCoordinator.gd")
const MatchRulesModel := preload("res://scripts/domain/MatchRules.gd")
const CampaignContentLoaderModel := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const CampaignGraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const CampaignProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const CampaignStoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const CampaignServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
## Secondes de jeu : avec --fixed-fps 60, la limite ne dépend pas de la machine.
const TIME_LIMIT := 120.0

var _checks: int = 0
var _failures: Array[String] = []
var _log: TestLog = TestLog.new()
var _finished := false
var _profile: ProfileFixture

@onready var root: Window = get_tree().root


func _ready() -> void:
	TestLog.current = _log
	OS.add_logger(_log)
	StoryService.auto_start_tutorials = false
	get_tree().create_timer(TIME_LIMIT).timeout.connect(_on_time_limit)
	_run.call_deferred()


func _on_time_limit() -> void:
	if not _finished:
		_failures.append("temps limite de %d s dépassé" % TIME_LIMIT)
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _profile != null:
		_profile.restore()
	OS.remove_logger(_log)
	TestLog.current = null
	var problems: Array[String] = _log.problems()
	print("TACTILE : %d vérifications, %d échec(s), %d erreur(s) Godot." % [_checks, _failures.size(), problems.size()])
	# printerr : les échecs sont comptés ici, pas comme des erreurs Godot.
	for failure in _failures:
		printerr("ÉCHEC : ", failure)
	for problem in problems:
		printerr("ERREUR GODOT : ", problem)
	get_tree().quit(0 if _failures.is_empty() and problems.is_empty() else 1)


func _run() -> void:
	# Donne au serveur headless le même indicateur tactile qu'Android.
	Input.emulate_touch_from_mouse = true
	Input.use_accumulated_input = false
	_profile = ProfileFixture.new()
	await _check_rules_scroll()
	await _check_deck_slots()
	await _check_collection()
	await _check_evolution_inputs()
	await _check_button_inputs()
	await _check_main_menu()
	await _check_pvp_lobby()
	await _check_pvp_draft_touch()
	await _check_other_menus()
	await _check_campaign_map()
	await _check_result_actions()
	await _check_buffered_input()
	await _check_battle_touch()
	await _check_battle_drag()
	_finish()


func _check_rules_scroll() -> void:
	var page := await _open_scene("res://scenes/menus/HowToPlay.tscn")
	var scroll: ScrollContainer = page.get_node("Content/Scroll")
	var text: RichTextLabel = scroll.get_node("RulesPanel/Page/RulesText")
	_check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "règles : le contenu dépasse l'écran")
	await _swipe(_point(text, Vector2(200, 350)), Vector2(0, -240))
	_check(scroll.scroll_vertical > 100, "règles : glisser depuis le texte fait défiler")
	var badge: Control = scroll.get_node("RulesPanel/Page/GodRules").get_child(1).get_child(0)
	scroll.ensure_control_visible(badge)
	await _settle()
	var before := scroll.scroll_vertical
	await _swipe(_center(badge), Vector2(0, -220))
	_check(scroll.scroll_vertical > before + 60, "règles : glisser depuis un logo fait aussi défiler")
	await _remove(page)


func _check_deck_slots() -> void:
	var page := await _open_scene("res://scenes/menus/CollectionScreen.tscn")
	var scroll: ScrollContainer = page.get_node("Content/Scroll")
	var slots: HBoxContainer = scroll.get_node(
		"Page/GodDeckPanel/GodDeckContent/GodDeckRow/IdentityDeck/DeckSlots")
	var second: Button = slots.get_child(1)
	await _swipe(_center(second), Vector2(0, -180))
	_check(scroll.scroll_vertical > 60 and PlayerData.get_selected_deck() == 0,
		"decks : glisser depuis un numéro fait défiler sans changer de deck")
	await _reset_scroll(scroll)
	await _tap(_center(second))
	_check(PlayerData.get_selected_deck() == 1 and second.button_pressed
		and page._current_deck.is_empty(), "decks : un toucher sélectionne une seule fois le deuxième emplacement")
	_check(second.get_theme_stylebox("hover") == second.get_theme_stylebox("normal"),
		"decks : actualiser la sélection ne réactive pas le survol pendant un geste tactile")
	await _tap(_center(second))
	_check(second.button_pressed and PlayerData.get_selected_deck() == 1,
		"decks : retoucher le numéro actif conserve sa sélection")
	await _tap(_center(slots.get_child(0)))
	_check(PlayerData.get_active_deck() == ProfileFixture.DECK and not page.status_label.visible,
		"decks : revenir au premier deck restaure ses cartes sans message de sauvegarde")
	await _remove(page)


func _check_collection() -> void:
	var page := await _open_scene("res://scenes/menus/CollectionScreen.tscn")
	var scroll: ScrollContainer = page.get_node("Content/Scroll")
	var deck_rows: VBoxContainer = scroll.get_node("Page/DeckPanel/DeckContent/DeckRows")
	var first_card: StoneCard = deck_rows.get_child(0).get_child(0).get_child(0)
	await _swipe(_center(first_card), Vector2(0, -150))
	_check(scroll.scroll_vertical > 50, "deck : glisser depuis une carte fait défiler")
	_check(not is_instance_valid(page._action_drawer), "deck : un glissement n'ouvre pas le tiroir")
	await _reset_scroll(scroll)
	await _tap(_center(first_card))
	_check(is_instance_valid(page._action_drawer), "deck : un appui ouvre le tiroir")
	await _tap(_center(first_card))
	_check(not is_instance_valid(page._action_drawer), "deck : un second appui referme le tiroir une seule fois")
	await _swipe(_center(first_card), Vector2(0, -220))
	_check(scroll._scrolling, "défilement : l'inertie est active après le geste")
	var visible_card := _find_visible_card(scroll, scroll.get_global_rect())
	if visible_card != null:
		var stopped_at := scroll.scroll_vertical
		await _tap(_center(visible_card))
		_check(not is_instance_valid(page._action_drawer), "inertie : toucher une carte arrête la liste sans l'ouvrir")
		_check(scroll.scroll_vertical == stopped_at, "inertie : la liste reste arrêtée après le toucher")
	else:
		_check(false, "inertie : une carte est visible pour tester l'arrêt")
	await _reset_scroll(scroll)
	var first_position := _center(first_card)
	_press(first_position)
	_press(first_position, 1)
	_release(first_position, false, 1)
	await _settle()
	_check(not is_instance_valid(page._action_drawer), "multitouch : le second doigt ne termine pas l'appui du premier")
	_release(first_position)
	await _settle()
	_check(is_instance_valid(page._action_drawer), "multitouch : le premier doigt déclenche une seule action")
	page._close_action_drawer()
	await _settle()
	await _tap(_center(first_card))
	_check(is_instance_valid(page._action_drawer), "deck : rouvrir le tiroir pour tester le fond")
	var deck_hint: Label = scroll.get_node("Page/DeckPanel/DeckContent/DeckHint")
	await _tap(_center(deck_hint))
	_check(not is_instance_valid(page._action_drawer), "deck : toucher une zone vide referme le tiroir")

	# Les cartes du deck sont masquées dans la collection : prendre la première affichée.
	var collection_card: StoneCard = null
	for wrapper in scroll.get_node("Page/CollectionRows").get_child(0).get_children():
		if wrapper.visible:
			collection_card = wrapper.get_child(0)
			break
	scroll.ensure_control_visible(collection_card)
	await _settle()
	var before := scroll.scroll_vertical
	await _swipe(_center(collection_card), Vector2(0, -180))
	_check(scroll.scroll_vertical > before + 60, "collection : glisser sur l'illustration fait défiler")
	_check(not is_instance_valid(page._action_drawer), "collection : aucune sélection accidentelle")

	var sort: Button = scroll.get_node("Page/CollectionHeader/SortButton")
	await _reset_scroll(scroll)
	await _swipe(_center(sort), Vector2(0, -180))
	_check(scroll.scroll_vertical > 60, "tri : un glissement démarré sur le bouton fait défiler")
	_check(not page.sort_menu.visible, "tri : glisser n'ouvre pas les options")
	await _reset_scroll(scroll)
	var sort_center := _center(sort)
	_press(sort_center)
	_drag(sort_center + Vector2(70, 0), Vector2(70, 0))
	_drag(sort_center, Vector2(-70, 0))
	_release(sort_center)
	await _settle()
	_check(not page.sort_menu.visible, "tri : revenir au point de départ après un glissement reste annulé")

	var crossing_start := _center(sort) + Vector2(0, 170)
	await _swipe(crossing_start, Vector2(0, -300))
	_check(not page.sort_menu.visible, "tri : traverser le bouton n'active rien")
	_check(sort.get_theme_stylebox("hover") == sort.get_theme_stylebox("normal"), "tri : aucune surbrillance de souris pendant le toucher")
	await _reset_scroll(scroll)
	await _tap(_center(sort))
	_check(page.sort_menu.visible, "tri : un véritable appui ouvre les options")
	var cost_option: Button = scroll.get_node("Page/SortMenu/SortOptions/CostButton")
	scroll.ensure_control_visible(cost_option)
	await _settle()
	await _tap(_center(cost_option))
	_check(page._sort_mode == 1 and not page.sort_menu.visible, "tri : choisir le coût fonctionne au tactile")
	await _reset_scroll(scroll)
	await _tap(_center(sort))
	_check(page.sort_menu.visible, "tri : rouvrir les options pour tester l'extérieur")
	var collection_title: Label = scroll.get_node("Page/CollectionTitle")
	await _tap(_center(collection_title))
	_check(not page.sort_menu.visible, "tri : toucher hors du menu referme les options")
	await _tap(_center(sort))
	_check(page.sort_menu.visible, "tri : rouvrir les options pour tester le retour")
	page._go_back()
	await _settle()
	_check(not page.sort_menu.visible, "tri : le retour ferme les options sans quitter la page")

	await _reset_scroll(scroll)
	first_card = deck_rows.get_child(0).get_child(0).get_child(0)
	_press(_center(first_card))
	_release(_center(first_card), true)
	await _settle()
	_check(not is_instance_valid(page._action_drawer), "carte : un toucher annulé par le système n'active rien")
	await _tap(_center(first_card))
	if is_instance_valid(page._action_drawer):
		var info_button: Button = page._action_drawer.get_node("Actions/InfoButton")
		await _swipe(_center(info_button), Vector2(0, -150))
		_check(not page.info_sheet.visible, "tiroir : glisser sur Infos n'ouvre pas la fiche")
		await _tap(_center(info_button))
		_check(page.info_sheet.visible, "tiroir : toucher Infos ouvre la fiche")
		var modal_scroll := scroll.scroll_vertical
		# Viser la marge réelle du fond, même si la fiche change de hauteur.
		var panel: Control = page.info_sheet.get_node("InfoPanel")
		var backdrop: Control = page.info_sheet.get_node("Backdrop")
		var outside := _point(backdrop, Vector2(panel.position.x * 0.5, panel.position.y + 100))
		await _swipe(outside, Vector2(0, 100))
		_check(scroll.scroll_vertical == modal_scroll, "fenêtre : les gestes ne traversent pas le fond modal")
		await _tap(outside)
		_check(not page.info_sheet.visible, "fenêtre : toucher le fond ferme la fiche")

	var incoming_id := ""
	for stone in StoneLoader.get_stones_for_god(PlayerData.player_god_id):
		if not page._current_deck.has(str(stone["id"])):
			incoming_id = str(stone["id"])
			break
	var replacement: ReplacementPanel = page.replacement_panel
	replacement.open_for(page._current_deck, incoming_id)
	await _settle()
	_check(replacement.visible, "remplacement : le panneau s'ouvre")
	var replacement_backdrop: Control = replacement.get_node("Backdrop")
	await _tap(_point(replacement_backdrop, Vector2(10, 10)))
	_check(not replacement.visible, "remplacement : toucher le fond ferme le panneau")
	await _remove(page)


func _check_evolution_inputs() -> void:
	var page := await _open_scene("res://scenes/menus/CollectionScreen.tscn")
	page._select_deck(1)
	await _settle()
	var scroll: ScrollContainer = page.scroll
	scroll.ensure_control_visible(page.level_button)
	await _settle()
	await _tap(_center(page.level_button))
	_check(page.level_menu.visible, "niveaux : le bouton global ouvre ses quatre choix au toucher")
	var fourth: Button = page.get_node("Content/Scroll/Page/LevelMenu/Levels").get_child(3)
	scroll.ensure_control_visible(fourth)
	await _settle()
	var before := scroll.scroll_vertical
	await _swipe(_center(fourth), Vector2(0, -150))
	_check(page._preview_level == 1 and scroll.scroll_vertical > before + 50,
		"niveaux : glisser depuis un choix fait défiler sans l'activer")
	await _reset_scroll(scroll)
	scroll.ensure_control_visible(fourth)
	await _settle()
	await _tap(_center(fourth))
	_check(page._preview_level == 4 and not page.level_menu.visible and PlayerData.get_active_deck().is_empty(),
		"niveaux : sélectionner quatre modifie uniquement l'aperçu de collection")
	var card: StoneCard = null
	for wrapper in page.collection_rows.get_child(0).get_children():
		if wrapper.get_child(0).get_stone_id() == "avortons_des_caves_n4":
			card = wrapper.get_child(0)
	if card == null:
		_check(false, "niveaux : la forme quatre est disponible dans la collection")
		await _remove(page)
		return
	scroll.ensure_control_visible(card)
	await _settle()
	await _tap(_center(card))
	# Une carte proche du bas est remontée d'une frame supplémentaire afin que
	# son tiroir superposé reste entièrement visible sous elle.
	await get_tree().process_frame
	var info_button: Button = page._action_drawer.info_button
	await _tap(_center(info_button))
	var info: StoneInfoSheet = page.info_sheet
	_check(info.visible and info._shown_variant == "avortons_des_caves_n4", "niveaux : Infos ouvre au toucher la forme affichée")
	var second: Button = info.get_node("InfoPanel/InfoContent/Levels").get_child(1)
	await _tap(_center(second))
	_check(info._shown_variant == "avortons_des_caves_n2" and PlayerData.get_active_deck().is_empty(),
		"niveaux : toucher deux dans Infos consulte ce niveau sans l'équiper")
	info.description_label.custom_minimum_size.y = 900
	await _settle()
	var info_scroll: ScrollContainer = info.get_node("InfoPanel/InfoContent/Scroll")
	var underlying := scroll.scroll_vertical
	await _swipe(_point(info_scroll, Vector2(100, 300)), Vector2(0, -180))
	_check(info_scroll.scroll_vertical > 60 and scroll.scroll_vertical == underlying,
		"niveaux : une fiche longue défile au doigt sans déplacer la collection derrière")
	await _swipe(_center(info.use_button), Vector2(0, -120))
	_check(info.visible and PlayerData.get_active_deck().is_empty(), "niveaux : glisser sur Utiliser n'équipe pas la carte")
	await _tap(_center(info.use_button))
	_check(not info.visible and PlayerData.get_active_deck() == ["avortons_des_caves_n2"]
		and PlayerData.get_deck("veskar", 0) == ProfileFixture.DECK,
		"niveaux : Utiliser enregistre une seule fois le niveau consulté dans le bon emplacement")
	PlayerData.set_player_deck([])
	page._select_deck(0)
	await _remove(page)


func _check_button_inputs() -> void:
	# Chargé ici : une erreur dans ce script est comptée au lieu de bloquer le lanceur.
	var button: Button = load("res://scripts/ui/input/TouchButton.gd").new()
	button.text = "TEST"
	button.position = Vector2(100, 100)
	button.size = Vector2(300, 100)
	root.add_child(button)
	await _settle()
	var activations := [0]
	button.pressed.connect(func(): activations[0] += 1)
	var position := _center(button)
	_press(position)
	_check(activations[0] == 0, "bouton : aucune action avant le relâchement")
	_release(position)
	_check(activations[0] == 1, "bouton : un toucher déclenche exactement une action")
	_press(position)
	_release(position, true)
	_check(activations[0] == 1, "bouton : un toucher annulé ne déclenche rien")

	button.grab_focus()
	var accept := InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.pressed = true
	Input.parse_input_event(accept)
	accept = InputEventKey.new()
	accept.keycode = KEY_ENTER
	Input.parse_input_event(accept)
	_check(activations[0] == 2, "bouton : l'activation au clavier/manette reste disponible")
	_mouse_move(position)
	_mouse_button(position, true)
	_mouse_button(position, false)
	_check(activations[0] == 3, "bouton : le clic de souris physique reste disponible")
	_check(button.get_theme_stylebox("hover") != button.get_theme_stylebox("normal"), "bouton : le survol de souris est restauré")
	button.disabled = true
	await _tap(position)
	_check(activations[0] == 3, "bouton : une action désactivée reste inactive au toucher")
	await _remove(button)


func _check_main_menu() -> void:
	var menu := await _open_scene("res://scenes/menus/MainMenu.tscn")
	var god_id: String = PlayerData.player_god_id
	var slot: int = PlayerData.get_selected_deck(god_id)
	var original: Array = PlayerData.get_deck(god_id, slot)
	PlayerData._decks_by_god[god_id][slot] = []
	menu._refresh()
	await _tap(_center(menu.campaign_button))
	_check(menu.deck_warning_overlay.visible,
		"accueil : un deck incomplet ouvre une modale bloquante au toucher")
	await _tap(_center(menu.close_warning_button))
	_check(not menu.deck_warning_overlay.visible,
		"accueil : FERMER referme la modale au toucher")
	PlayerData._decks_by_god[god_id][slot] = original
	menu._refresh()
	for path in ["Content/Header/ProfileButton", "Content/Hero/Identity/ModeButtons/CampaignButton",
			"Content/Hero/Identity/ModeButtons/PvpButton"]:
		var button: Button = menu.get_node(path)
		# Les vrais changements de scène fermeraient la suite : on compte seulement.
		for connection in button.pressed.get_connections():
			button.pressed.disconnect(connection["callable"])
		var activations := [0]
		button.pressed.connect(func(): activations[0] += 1)
		await _tap(_center(button))
		_check(activations[0] == 1, "accueil : un toucher sur %s déclenche une seule action" % button.name)
		await _swipe(_center(button), Vector2(0, -150))
		_check(activations[0] == 1, "accueil : glisser depuis %s ne déclenche rien" % button.name)
	await _remove(menu)


## Le salon PVP doit rester utilisable au toucher sans ouvrir de socket :
## deck incomplet, bouton PRÊT inactif et message d'attente lisible.
func _check_pvp_lobby() -> void:
	var god_id: String = PlayerData.player_god_id
	var slot: int = PlayerData.get_selected_deck(god_id)
	var original: Array = PlayerData.get_deck(god_id, slot)
	var page := await _open_scene("res://scenes/menus/PvpLobby.tscn")
	var create: Button = page.get_node(
		"Root/Scroll/Content/ModeScreen/CreateCard/CreateBox/CreateButton")
	var ready_button: Button = page.get_node("Root/Scroll/Content/LobbyScreen/ReadyButton")
	var notice: Label = page.get_node("Root/Scroll/Content/NoticeLabel")
	var title: Label = page.get_node("Root/Scroll/Content/ModeScreen/ModeTitle")
	_check(title.text == "JOUER À DEUX" and ready_button.disabled
		and not page.lobby_screen.visible,
		"salon : l'écran initial choisit le mode et PRÊT reste inactif sans adversaire")
	PlayerData._decks_by_god[god_id][slot] = []
	await _tap(_center(create))
	_check(notice.visible and notice.text == "VEUILLEZ COMPLÉTER VOTRE DECK"
		and LanSession.state == LanSession.State.IDLE,
		"salon : un deck incomplet affiche l'avertissement sans ouvrir de socket")
	_check(ready_button.disabled and not page.lobby_screen.visible,
		"salon : un deck incomplet n'ouvre jamais la salle d'attente")
	PlayerData._decks_by_god[god_id][slot] = original
	var join: Button = page.get_node(
		"Root/Scroll/Content/ModeScreen/JoinCard/JoinBox/JoinButton")
	await _tap(_center(join))
	page._attempted_address = "192.0.2.44"
	page._connection_attempt_pending = true
	LanSession.state = LanSession.State.CONNECTING
	page._refresh_status()
	await _tap(_center(page.cancel_connection_button))
	_check(not page.connection_overlay.visible and page.address_input.text == "192.0.2.44"
		and LanSession.state == LanSession.State.DISCOVERING,
		"salon : le bouton tactile annule la connexion et reprend la recherche")
	await _remove(page)


## Le draft Sélection doit répondre à un vrai toucher natif, pas seulement à
## l'émission directe du signal de carte par un test.
func _check_pvp_draft_touch() -> void:
	var host_transport := FakeTransport.new()
	host_transport.local_id = 1
	var client_transport := FakeTransport.new()
	client_transport.local_id = 2
	host_transport.remote = client_transport
	client_transport.remote = host_transport
	var host_profile := {"name": "Hote", "god_id": "veskar", "deck": []}
	var client_profile := {"name": "Client", "god_id": "nerava", "deck": []}
	var rules := MatchRulesModel.default_config()
	rules["mode"] = MatchRulesModel.MODE_DRAFT
	rules["series"] = MatchRulesModel.SERIES_FT1
	rules["power_tier"] = 4
	rules["locked"] = true
	var host := SeriesCoordinatorModel.new()
	var client := SeriesCoordinatorModel.new()
	host.attach(host_transport, true, GameState.PLAYER_ONE, 2, host_profile, client_profile,
		rules, 987654)
	client.attach(client_transport, false, GameState.PLAYER_TWO, 0, client_profile,
		host_profile, rules)
	host.host_start_series()
	PvpMatchContext.close_presence()
	PvpMatchContext.clear()
	PvpMatchContext.begin_preparation(host, null, GameState.PLAYER_ONE, 1, 2,
		host_profile, client_profile, rules, host.public_state())
	var page: Control = await _open_scene("res://scenes/menus/PvpPreparation.tscn")
	var cards: Array = page.local_grid._cards
	_check(cards.size() == 2 and page.draft_deck_grid.get_child_count() == 0,
		"draft tactile : deux offres locales et un deck vide sont affichés")
	if cards.size() == 2:
		await _tap(_center(cards[0] as StoneCard))
	_check(page.draft_deck_grid.get_child_count() == 1
		and page.draft_status.text.contains("Choix enregistré"),
		"draft tactile : un toucher sélectionne une seule offre et actualise le deck")
	await _remove(page)
	PvpMatchContext.close_presence()
	PvpMatchContext.clear()
	host.close()
	client.close()
	LanSession.reset()


func _check_other_menus() -> void:
	var stats := await _open_scene("res://scenes/menus/Stats.tscn")
	var scroll: ScrollContainer = stats.get_node("Root/Scroll")
	var edit: Button = scroll.get_node("Content/ProfilePanel/ProfileContent/PseudoRow/EditButton")
	await _tap(_center(edit))
	_check(stats.edit_row.visible, "profil : un seul appui ouvre l'édition du pseudo")
	stats._cancel_edit()
	# Le profil affiche sept chemins ; forcer la hauteur vérifie le défilement
	# sans dépendre des statistiques sauvegardées.
	scroll.get_node("Content/NPCPanel/NPCList").custom_minimum_size.y = 1400
	await _settle()
	var value_before := scroll.scroll_vertical
	await _swipe(_point(scroll, Vector2(100, 400)), Vector2(0, -200))
	_check(scroll.scroll_vertical > value_before, "profil : défilement tactile des statistiques")
	await _remove(stats)
	var select := await _open_scene("res://scenes/menus/EncounterSelect.tscn")
	var grid: GridContainer = select.get_node("Root/Scroll/Content/Gods")
	var first_tile: Control = grid.get_child(0)
	_check(grid.columns == UITheme.ENCOUNTER_COLUMNS and grid.get_child_count() == 6,
		"rencontres : les six dieux forment une grille de cases")
	# Les changements de scène fermeraient la suite : on compte seulement.
	for connection in first_tile.pressed.get_connections():
		first_tile.pressed.disconnect(connection["callable"])
	var selections := [0]
	first_tile.pressed.connect(func(): selections[0] += 1)
	await _swipe(_point(first_tile, Vector2(80, 120)), Vector2(0, -260))
	_check(selections[0] == 0, "rencontres : glisser sur une case ne choisit pas le dieu")
	await _tap(_center(first_tile))
	_check(selections[0] == 1, "rencontres : un toucher choisit une seule fois le dieu")
	await _remove(select)
	var saved_source: String = BattleContext.selected_source_id
	var saved_stats: Dictionary = PlayerData.stats.duplicate(true)
	PlayerData.stats["per_npc"]["bot_kharun_n1_tres_facile"] = {
		"wins": 1, "games": 1, "best_diff": 2}
	BattleContext.select_source("kharun")
	var path := await _open_scene("res://scenes/menus/EncounterPath.tscn")
	var path_scroll: ScrollContainer = path.get_node("Root/Scroll")
	var track: Control = path_scroll.get_node("Track")
	var first_node: Button = track.node_for(0)
	var second_node: Button = track.node_for(1)
	var third_node: Button = track.node_for(2)
	await _tap(_center(first_node))
	_check(path._selected_index == 0 and path.level_label.text.contains("Très facile"),
		"chemin : un rond terminé peut être rejoué")
	await _tap(_center(second_node))
	_check(path._selected_index == 1 and path.level_label.text.contains("Facile"),
		"chemin : un rond ouvert se sélectionne")
	await _tap(_center(third_node))
	_check(path._selected_index == 1, "chemin : un rond verrouillé ignore le toucher")
	await _swipe(_point(path_scroll, Vector2(540, 700)), Vector2(0, -300))
	_check(path_scroll.scroll_vertical > 60,
		"chemin : glisser sur le serpentin le fait défiler")
	await _remove(path)
	BattleContext.selected_source_id = saved_source
	PlayerData.stats = saved_stats


## Le résultat est un vrai menu tactile : les cinq actions répondent au doigt
## et le bouton suivant disparaît après une défaite.
func _check_result_actions() -> void:
	var saved_id := BattleContext.selected_npc_id
	var saved_source := BattleContext.selected_source_id
	var saved_opponent := BattleContext.selected_opponent
	var saved_winner := BattleContext.last_winner
	var saved_human := BattleContext.last_score_human
	var saved_ai := BattleContext.last_score_ai
	BattleContext.select_opponent(OpponentCatalogModel.build("veskar", "n1", "tres_facile"))
	BattleContext.record_result(GameState.PLAYER_HUMAN, 10, 3)
	var page: Control = await _open_scene("res://scenes/menus/Result.tscn")
	var buttons: Array[Button] = [page.next_btn, page.replay_btn, page.level_btn,
		page.gods_btn, page.menu_btn]
	var activations := [0]
	for button in buttons:
		for connection in button.pressed.get_connections():
			button.pressed.disconnect(connection["callable"])
		button.pressed.connect(func(): activations[0] += 1)
	_check(page.next_btn.visible, "résultat : une victoire avec un suivant affiche Niveau suivant")
	for button in buttons:
		await _tap(_center(button))
	_check(activations[0] == buttons.size(), "résultat : les cinq boutons répondent une fois au toucher")
	await _remove(page)
	BattleContext.record_result(GameState.PLAYER_AI, 3, 10)
	var defeat: Control = await _open_scene("res://scenes/menus/Result.tscn")
	_check(not defeat.next_btn.visible and defeat.replay_btn.visible
		and defeat.level_btn.visible and defeat.gods_btn.visible and defeat.menu_btn.visible,
		"résultat : une défaite masque le suivant et laisse les quatre autres boutons")
	await _remove(defeat)
	BattleContext.selected_npc_id = saved_id
	BattleContext.selected_source_id = saved_source
	BattleContext.selected_opponent = saved_opponent
	BattleContext.record_result(saved_winner, saved_human, saved_ai)


func _check_buffered_input() -> void:
	# Vérifie aussi le regroupement d'événements utilisé par défaut en jeu.
	Input.use_accumulated_input = true
	var page := await _open_scene("res://scenes/menus/HowToPlay.tscn")
	var scroll: ScrollContainer = page.get_node("Content/Scroll")
	await _swipe(_point(scroll, Vector2(200, 400)), Vector2(0, -240))
	_check(scroll.scroll_vertical > 100, "entrée regroupée : le défilement fonctionne avec les réglages du jeu")
	await _remove(page)
	Input.use_accumulated_input = false


func _check_battle_touch() -> void:
	var saved_npc: String = BattleContext.selected_npc_id
	var saved_first: int = BattleContext.forced_first_player
	BattleContext.selected_npc_id = "disciple_muraille"
	BattleContext.forced_first_player = GameState.PLAYER_HUMAN
	var board := await _open_scene("res://scenes/game/Board.tscn")
	var hand: HandView = board.get_node("Root/HandView")
	var card: StoneCard = hand.get_child(0).get_child(0)
	await _tap(_center(card))
	_check(board._selected_stone_id != "", "combat : sélectionner une carte avec un toucher natif")
	var slot: Panel = board.get_node("Root/BoardArea/BoardView/cell_1_1")
	var state: GameState = board.turn_manager.get_state()
	# Le plateau peut comporter une case bloquée : choisir une case libre.
	for index in range(state.board.size()):
		if state.board[index]["cell_type"] != GameState.CELL_BLOCKED:
			slot = board.get_node("Root/BoardArea/BoardView").get_node("cell_%d_%d" % [
				index / GameState.BOARD_SIZE, index % GameState.BOARD_SIZE])
			break
	await _tap(_center(slot))
	_check(state.human_hand.size() == DeckRules.DECK_SIZE - 1, "combat : une seule carte est posée au toucher")
	await _remove(board)
	BattleContext.selected_npc_id = saved_npc
	BattleContext.forced_first_player = saved_first


## Glisser une carte de la main jusqu'au plateau, au doigt puis à la souris.
func _check_battle_drag() -> void:
	var saved_npc: String = BattleContext.selected_npc_id
	var saved_first: int = BattleContext.forced_first_player
	BattleContext.selected_npc_id = "disciple_muraille"

	var board := await _open_battle(GameState.PLAYER_HUMAN)
	var hand: HandView = board.get_node("Root/HandView")
	var view: BoardView = board.get_node("Root/BoardArea/BoardView")
	var state: GameState = board.turn_manager.get_state()
	var cell := _free_cell(state)
	var card: StoneCard = hand.get_child(0).get_child(0)
	var start := _center(card)
	var lift: float = board._card_drag.TOUCH_LIFT * view.slot_at(0, 0).size.y
	var release := _center(view.slot_at(cell.x, cell.y)) + Vector2(0, lift)
	_press(start)
	for step in range(1, 9):
		var point := start.lerp(release, float(step) / 8.0)
		_drag(point, (release - start) / 8.0)
		await get_tree().process_frame
	await _settle()
	_check(board._card_drag.is_dragging() and view._drop_target == cell and card.modulate.a < 1.0,
		"glisser : la copie suit le doigt et la case visée s'éclaire")
	_release(release)
	await _settle()
	_check(state.human_hand.size() == DeckRules.DECK_SIZE - 1 and state.get_cell(cell.x, cell.y)["owner"] == GameState.PLAYER_HUMAN
		and view._drop_target == Vector2i(-1, -1) and board._card_drag.get_child_count() == 0,
		"glisser : relâcher sur une case y pose la carte une seule fois")
	await _remove(board)

	board = await _open_battle(GameState.PLAYER_HUMAN)
	hand = board.get_node("Root/HandView")
	view = board.get_node("Root/BoardArea/BoardView")
	state = board.turn_manager.get_state()
	cell = _free_cell(state)
	card = hand.get_child(0).get_child(0)
	# Lâchée un peu à côté du centre, la carte va quand même sur la case la plus proche.
	var near := _center(view.slot_at(cell.x, cell.y)) + Vector2(view.slot_at(0, 0).size.x * 0.3, lift)
	await _drag_touch(_center(card), near)
	_check(state.human_hand.size() == DeckRules.DECK_SIZE - 1 and state.get_cell(cell.x, cell.y)["owner"] == GameState.PLAYER_HUMAN,
		"glisser : une carte lâchée près d'une case est posée sur cette case")
	await _remove(board)

	board = await _open_battle(GameState.PLAYER_HUMAN)
	hand = board.get_node("Root/HandView")
	state = board.turn_manager.get_state()
	card = hand.get_child(0).get_child(0)
	await _drag_touch(_center(card), _center(card) + Vector2(0, 260))
	_check(state.human_hand.size() == DeckRules.DECK_SIZE and board._selected_stone_id == ""
		and is_equal_approx(card.modulate.a, 1.0) and board._card_drag.get_child_count() == 0,
		"glisser : relâcher hors du plateau ne joue rien et la carte revient sans sélection")
	_press(_center(card))
	_drag(_center(card) + Vector2(8, 0), Vector2(8, 0))
	_release(_center(card) + Vector2(8, 0))
	await _settle()
	_check(board._selected_stone_id == card.get_stone_id() and state.human_hand.size() == DeckRules.DECK_SIZE,
		"glisser : un petit mouvement reste un appui qui sélectionne la carte")
	await _remove(board)

	board = await _open_battle(GameState.PLAYER_HUMAN)
	hand = board.get_node("Root/HandView")
	view = board.get_node("Root/BoardArea/BoardView")
	state = board.turn_manager.get_state()
	cell = _free_cell(state)
	card = hand.get_child(0).get_child(0)
	var mouse_start := _center(card)
	var mouse_end := _center(view.slot_at(cell.x, cell.y))
	_mouse_move(mouse_start)
	_mouse_button(mouse_start, true)
	for step in range(1, 9):
		_mouse_move(mouse_start.lerp(mouse_end, float(step) / 8.0))
		await get_tree().process_frame
	_mouse_button(mouse_end, false)
	await _settle()
	_check(state.human_hand.size() == DeckRules.DECK_SIZE - 1 and state.get_cell(cell.x, cell.y)["owner"] == GameState.PLAYER_HUMAN,
		"glisser : la souris pose aussi la carte sur la case visée")
	await _remove(board)

	board = await _open_battle(GameState.PLAYER_AI)
	hand = board.get_node("Root/HandView")
	view = board.get_node("Root/BoardArea/BoardView")
	state = board.turn_manager.get_state()
	cell = _free_cell(state)
	card = hand.get_child(0).get_child(0)
	await _drag_touch(_center(card), _center(view.slot_at(cell.x, cell.y)) + Vector2(0, lift))
	_check(state.human_hand.size() == DeckRules.DECK_SIZE and state.get_cell(cell.x, cell.y)["owner"] != GameState.PLAYER_HUMAN,
		"glisser : aucune carte ne peut être posée pendant le tour adverse")
	await _remove(board)

	BattleContext.selected_npc_id = saved_npc
	BattleContext.forced_first_player = saved_first


func _open_battle(first_player: int) -> Control:
	BattleContext.forced_first_player = first_player
	return await _open_scene("res://scenes/game/Board.tscn")


## Première case jouable : le plateau peut comporter une case bloquée.
func _free_cell(state: GameState) -> Vector2i:
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		if cell["cell_type"] != GameState.CELL_BLOCKED and cell["owner"] == GameState.PLAYER_NONE:
			return Vector2i(index / GameState.BOARD_SIZE, index % GameState.BOARD_SIZE)
	return Vector2i(-1, -1)


func _drag_touch(start: Vector2, finish: Vector2) -> void:
	_press(start)
	for step in range(1, 9):
		_drag(start.lerp(finish, float(step) / 8.0), (finish - start) / 8.0)
		await get_tree().process_frame
	_release(finish)
	await _settle()


func _open_scene(path: String) -> Control:
	var scene: PackedScene = load(path)
	var page := scene.instantiate() as Control
	root.add_child(page)
	await _settle()
	return page


func _remove(node: Node) -> void:
	root.remove_child(node)
	node.queue_free()
	await _settle()


func _reset_scroll(scroll: ScrollContainer) -> void:
	var point := _point(scroll, Vector2(3, 50))
	_press(point)
	_release(point, true)
	scroll.scroll_vertical = 0
	await _settle()


func _tap(position: Vector2) -> void:
	_press(position)
	_release(position)
	await _settle()


func _swipe(start: Vector2, movement: Vector2) -> void:
	_press(start)
	for step in range(1, 9):
		_drag(start + movement * (float(step) / 8.0), movement / 8.0)
		await get_tree().process_frame
	_release(start + movement)
	await _settle()


func _press(position: Vector2, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = true
	_inject(event)


func _release(position: Vector2, canceled: bool = false, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.canceled = canceled
	_inject(event)


func _drag(position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = position
	event.relative = relative
	_inject(event)


func _mouse_move(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	_inject(event)


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	_inject(event)


func _inject(event: InputEvent) -> void:
	# L'entrée passe par Input, y compris l'émulation native et le routage GUI.
	# Les contrôles vivent dans le canevas 1080p ; l'OS reçoit des pixels écran.
	Input.parse_input_event(event.xformed_by(root.get_final_transform()))


func _point(control: Control, local_point: Vector2) -> Vector2:
	return control.get_global_transform_with_canvas() * local_point


func _center(control: Control) -> Vector2:
	return _point(control, control.size * 0.5)


func _find_visible_card(node: Node, rect: Rect2) -> StoneCard:
	if node is CanvasItem and not node.is_visible_in_tree():
		return null
	if node is StoneCard and rect.has_point(_center(node)):
		return node
	for child in node.get_children():
		var found := _find_visible_card(child, rect)
		if found != null:
			return found
	return null


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _check_campaign_map() -> void:
	var path := "user://campaign_touch_checks.json"
	for suffix in ["", ".tmp", ".unreadable"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	var content := CampaignContentLoaderModel.read()
	if not bool(content.get("ok", false)):
		_check(false, "campagne tactile : le contenu est valide")
		return
	var graph: CampaignGraph = CampaignGraphModel.build(content["definition"])
	var progress := CampaignProgressModel.new()
	progress.mark_completed("tuto_01")
	var service := CampaignServiceModel.new(graph, progress, CampaignStoreModel.new(path), [])
	CampaignContext.set_service_for_tests(service)
	CampaignContext.focus_node_id = "tuto_02"
	var page: Control = await _open_scene("res://scenes/campaign/CampaignMap.tscn")
	await _settle()
	var map: CampaignMapView = page.get_node("Root/Scroll/MapView")
	var scroll: ScrollContainer = page.get_node("Root/Scroll")
	var dialog: CampaignLevelDialog = page.get_node("LevelDialog")
	scroll.scroll_vertical = 0
	await _settle()
	var locked: Control = map.node_control("tuto_03")
	await _tap(_center(locked))
	_check(not dialog.visible, "campagne tactile : un nœud verrouillé n'ouvre pas sa fiche")
	var available: Control = map.node_control("tuto_02")
	await _tap(_center(available))
	_check(dialog.visible and not dialog.launch_button.disabled,
		"campagne tactile : toucher un nœud accessible ouvre sa fiche")
	await _tap(_center(dialog.close_button))
	_check(not dialog.visible, "campagne tactile : la croix referme la fiche")
	var completed: Control = map.node_control("tuto_01")
	await _tap(_center(completed))
	_check(dialog.visible and dialog.launch_button.text == "REJOUER",
		"campagne tactile : un niveau terminé reste rejouable")
	await _tap(_center(dialog.close_button))
	scroll.scroll_vertical = 0
	await _settle()
	var before := scroll.scroll_vertical
	await _swipe(_center(available), Vector2(0, -260))
	_check(scroll.scroll_vertical > before + 30 and not dialog.visible,
		"campagne tactile : glisser depuis un nœud fait défiler sans l'activer")
	await _remove(page)
	CampaignContext.reset_for_tests()
	for suffix in ["", ".tmp", ".unreadable"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	print("%s %s" % ["OK" if condition else "ÉCHEC", label])
	if not condition:
		_failures.append(label)
