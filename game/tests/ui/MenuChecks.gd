extends "res://tests/support/CombatTestSuite.gd"
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")
const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")
const EncounterPathModel := preload("res://scripts/domain/EncounterPath.gd")
const TouchButtonScript := preload("res://scripts/ui/input/TouchButton.gd")
const LobbyCoordinator := preload("res://scripts/network/LanLobbyCoordinator.gd")
const BattleLayoutModel := preload("res://scripts/ui/BattleLayout.gd")
const SeriesEngineModel := preload("res://scripts/domain/SeriesEngine.gd")
const SeriesStateModel := preload("res://scripts/domain/SeriesState.gd")
const PvpResultPresenterModel := preload("res://scripts/ui/pvp/PvpResultPresenter.gd")

func run() -> void:
	var fixture := ProfileFixture.new()
	_test_screen_backgrounds()
	await _test_god_selector_ui()
	await _test_deck_slots()
	await _test_deck_clear()
	await _test_safe_area()
	await _test_home_portraits()
	await _test_sound_settings()
	await _test_menu_modes()
	await _test_preview_layout()
	await _test_rules_legends()
	await _test_collection_incremental_refresh()
	_test_cost_format()
	await _test_hud_game_over()
	await _test_hand_keeps_remaining_cards()
	_test_first_player_draw()
	await _test_prebattle_reveals_draw()
	await _test_pvp_prebattle()
	await _test_pvp_board_opens_ready()
	await _test_pvp_result()
	await _test_pvp_lobby_screens()
	await _test_encounter_selection()
	await _test_encounter_path()
	await _test_stats_progress()
	await _test_generated_opponent_battle()
	await _test_neutral_bot_battle()
	await _test_result_uses_generated_opponent()
	await _test_result_actions()
	fixture.restore()


func _test_screen_backgrounds() -> void:
	var scenes := {
		"res://scenes/menus/MainMenu.tscn": MenuBackground.Room.REFUGE,
		"res://scenes/menus/CollectionScreen.tscn": MenuBackground.Room.BESTIARY,
		"res://scenes/menus/HowToPlay.tscn": MenuBackground.Room.JOURNAL,
		"res://scenes/menus/EncounterSelect.tscn": MenuBackground.Room.ENCOUNTERS,
		"res://scenes/menus/EncounterPath.tscn": MenuBackground.Room.ENCOUNTER_PATH,
		"res://scenes/menus/PreBattle.tscn": MenuBackground.Room.COIN_RITUAL,
		"res://scenes/game/Board.tscn": MenuBackground.Room.BOARD,
		"res://scenes/menus/Result.tscn": MenuBackground.Room.AFTERMATH,
		"res://scenes/menus/Stats.tscn": MenuBackground.Room.PROFILE,
		"res://scenes/menus/PvpLobby.tscn": MenuBackground.Room.PVP,
		"res://scenes/menus/PvpPreparation.tscn": MenuBackground.Room.PVP,
		"res://scenes/menus/PvpResult.tscn": MenuBackground.Room.AFTERMATH,
	}
	var assigned_rooms := {}
	for scene_path in scenes:
		var page: Control = (load(scene_path) as PackedScene).instantiate()
		var background: MenuBackground = page.get_node("Background")
		assigned_rooms[background.room] = true
		_check(background.room == scenes[scene_path],
			"l'écran %s utilise son ambiance néon dédiée" % scene_path)
		page.free()
	# La préparation reprend volontairement l'arène du salon et le résultat PVP
	# partage l'ambiance de la campagne : ce sont les mêmes familles visuelles.
	_check(assigned_rooms.size() == 10,
		"les écrans PVP conservent leurs ambiances dédiées sans multiplier les variantes")
	var background := MenuBackground.new()
	var formats := [Vector2(1080.0, 1920.0), Vector2(1200.0, 1920.0),
		Vector2(1000.0, 1920.0), Vector2(1080.0, 2160.0)]
	var artwork_fits_without_crop := true
	for viewport_size in formats:
		var scale: float = background._artwork_scale_for_size(viewport_size)
		var offset: Vector2 = background._artwork_offset_for_size(viewport_size, scale)
		var artwork_size := Vector2(1080.0, 1920.0) * scale
		artwork_fits_without_crop = artwork_fits_without_crop \
			and is_equal_approx(artwork_size.x, artwork_size.y * 1080.0 / 1920.0) \
			and offset.x >= 0.0 and offset.y >= 0.0 \
			and offset.x + artwork_size.x <= viewport_size.x \
			and offset.y + artwork_size.y <= viewport_size.y
	_check(artwork_fits_without_crop,
		"les fonds gardent leur proportion et tiennent entièrement dans plusieurs formats portrait")
	var full_bleed_formats := [Vector2(1080.0, 2400.0), Vector2(1200.0, 1920.0)]
	var rails_reach_edges := true
	for viewport_size in full_bleed_formats:
		var scale := background._full_bleed_scale_for_size(viewport_size)
		var offset := background._full_bleed_offset_for_size(viewport_size, scale)
		var left_rail := offset.x + 18.0 * scale
		var right_rail := offset.x + 1062.0 * scale
		rails_reach_edges = rails_reach_edges \
			and left_rail <= viewport_size.x * 0.02 + 1.0 \
			and right_rail >= viewport_size.x * 0.98 - 1.0
	_check(rails_reach_edges,
		"les rails des salles combat et PVP restent collés aux bords sur téléphone et tablette")
	var curve := background._firework_curve_points(
		Vector2.ZERO, 0.0, 100.0, 36.0, 8)
	var adjacent_curve := background._firework_curve_points(
		Vector2.ZERO, 0.4, 100.0, 36.0, 8)
	var firework_colors: Array[Color] = []
	for ray in range(5):
		firework_colors.append(background._firework_color(Color("#e75aa8"), ray))
	var mixed_firework_colors := true
	for index in range(1, firework_colors.size()):
		mixed_firework_colors = mixed_firework_colors \
			and firework_colors[index] != firework_colors[index - 1]
	var rays_keep_their_order := true
	for index in range(1, curve.size() - 1):
		var first_angle: float = curve[index].angle()
		var second_angle: float = adjacent_curve[index].angle()
		rays_keep_their_order = rays_keep_their_order \
			and second_angle > first_angle
	var ribbon := background._firework_ribbon(curve, 3.2)
	var skull_width := 460.0 * MenuBackground.SKULL_SCALE
	var skull_height := 635.0 * MenuBackground.SKULL_SCALE
	_check(curve[4].y > curve[2].y and rays_keep_their_order
		and mixed_firework_colors and ribbon[0].distance_to(ribbon[-1])
		> ribbon[8].distance_to(ribbon[9]),
		"les traînées grossissent en retombant et restent évasées, ordonnées et multicolores")
	_check(background._firework_length_factor(1, 0.4, 0)
		!= background._firework_length_factor(1, 0.4, 1)
		and background._firework_fall_factor(0) != background._firework_fall_factor(1),
		"les bouquets utilisent plusieurs motifs et degrés de retombée")
	_check(typeof(MenuBackground.SKULL_SCALE) == TYPE_FLOAT
		and skull_width >= 1080.0 * 0.9 and skull_height >= 1920.0 * 0.68
		and MenuBackground.SKULL_CENTER.y > 960.0,
		"le crâne de défaite garde ses proportions, remplit la largeur et descend sur l'écran")
	var tall_size := Vector2(1080.0, 2400.0)
	var tall_scale := background._full_bleed_scale_for_size(tall_size)
	var tall_offset := background._full_bleed_offset_for_size(tall_size, tall_scale)
	var tall_bottom := (tall_size.y - tall_offset.y) / tall_scale
	_check(tall_bottom >= 2160.0
		and MenuBackground.PVP_ARCH_BOTTOM == 1920.0,
		"l'arche PVP atteint le bord bas, y compris sur un écran plus haut que le canevas")
	background.free()


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
	page._on_info_requested("devoracle_n1")
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
	var expected_fortune := int(StoneLoader.get_stone("devoracle_n1").get("random_blades", 0))
	var explanation_badge: Control = info.power_badges.get_child(0) if info.power_badges.get_child_count() > 0 else null
	_check(expected_fortune > 0 and explanation_badge != null and info.power_badges.get_child_count() == 1
		and explanation_badge.kind == "fortune" and explanation_badge.count == expected_fortune
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
	var all_neon_colors_match := true
	for god in StoneLoader.get_all_gods():
		PlayerData.player_god_id = str(god["id"])
		menu._refresh()
		var texture: Texture2D = menu.god_portrait.texture
		var background: MenuBackground = menu.get_node("Background")
		all_portraits_loaded = all_portraits_loaded and texture != null
		all_identities_match = all_identities_match and menu.god_name.text == str(god["name"]).to_upper()
		all_identities_match = all_identities_match and menu.god_family.text == god["family_name"]
		all_neon_colors_match = all_neon_colors_match and background.neon_primary_color == Color(str(god["color"]))
	_check(all_portraits_loaded and all_identities_match and all_neon_colors_match,
		"l'accueil charge les six portraits, identités et couleurs néon des dieux")
	_check(menu.god_portrait.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and menu.get_node("Background").mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"le portrait et le décor du refuge laissent passer les gestes vers les commandes")
	var background: MenuBackground = menu.get_node("Background")
	var first_god := StoneLoader.get_god("kharun")
	var second_god := StoneLoader.get_god("nerava")
	background.set_gods(first_god, second_god)
	_check(background.neon_primary_color == Color(str(first_god["color"]))
		and background.neon_secondary_color == Color(str(second_god["color"])),
		"le fond peut afficher les accents des deux dieux d'un même écran")
	for frame in range(6):
		await get_tree().process_frame
	var game_title: Control = menu.get_node("Content/GameTitle")
	var emblem: Control = menu.get_node("Content/Hero/PortraitArea/Emblem")
	var identity: Control = menu.get_node("Content/Hero/Identity")
	var ring_top := background.global_position.y + background.size.y * 480.0 / 1920.0
	var ring_bottom := background.global_position.y + background.size.y * 1220.0 / 1920.0
	_check(game_title.get_global_rect().end.y < ring_top
		and game_title.get_global_rect().end.y < emblem.get_global_rect().position.y,
		"le titre et son sous-titre restent au-dessus des cercles")
	_check(identity.get_global_rect().position.y > ring_bottom
		and identity.get_global_rect().position.y > emblem.get_global_rect().end.y,
		"le nom et les commandes du dieu restent sous les cercles et le portrait")
	var status: Label = menu.deck_status
	var font := status.get_theme_font("font")
	var widest_status := font.get_string_size("Deck 3 • 8/8 cartes • 79,75/80 points",
		HORIZONTAL_ALIGNMENT_LEFT, -1, status.get_theme_font_size("font_size")).x
	_check(not status.text.contains("\n") and status.get_line_count() == 1
		and widest_status <= status.size.x,
		"le numéro, les cartes et les points du deck tiennent sur une ligne à la taille de police courante")
	PlayerData.player_god_id = ""
	menu._refresh()
	_check(menu.god_portrait.texture != null and menu.god_name.text == "SANS DIEU"
		and menu.god_family.text == "Pierres neutres",
		"l'accueil affiche la stèle Sans dieu pour un profil sans dieu")
	PlayerData.player_god_id = original_god
	menu._refresh()
	menu.queue_free()
	await get_tree().process_frame


func _test_sound_settings() -> void:
	var original_music := Audio.music_volume_percent()
	var original_sfx := Audio.sfx_volume_percent()
	Audio.set_music_volume_percent(35.0, false)
	Audio.set_sfx_volume_percent(0.0, false)
	var menu: Control = (load("res://scenes/menus/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	for frame in range(3):
		await get_tree().process_frame
	var settings: SoundSettingsPopover = menu.sound_settings
	settings.open()
	await get_tree().process_frame
	var music_bus := AudioServer.get_bus_index(Audio.MUSIC_BUS)
	var sfx_bus := AudioServer.get_bus_index(Audio.SFX_BUS)
	_check(settings.is_open() and settings.dismiss_button.visible
		and settings.toggle_button.get_global_rect().position.y
		>= menu.profile_button.get_global_rect().end.y - 1.0,
		"accueil : le bouton son reste sous le profil et ouvre une carte bloquante")
	_check(is_equal_approx(settings.music_slider.value, 35.0)
		and is_equal_approx(settings.sfx_slider.value, 0.0)
		and is_equal_approx(Audio.DEFAULT_VOLUME_PERCENT, 70.0)
		and is_equal_approx(AudioServer.get_bus_volume_db(music_bus), linear_to_db(0.35))
		and AudioServer.is_bus_mute(sfx_bus),
		"audio : les deux curseurs reflètent leurs bus et zéro coupe réellement les SFX")
	settings.close()
	_check(not settings.is_open() and not settings.dismiss_button.visible,
		"accueil : fermer les réglages libère immédiatement le reste du menu")
	menu.queue_free()
	await get_tree().process_frame
	Audio.set_music_volume_percent(original_music, false)
	Audio.set_sfx_volume_percent(original_sfx, false)

## Les deux modes partagent une ligne de largeur égale, gardent leur libellé et
## n'ouvrent leur destination qu'avec un deck valide.
func _test_menu_modes() -> void:
	var god_id: String = PlayerData.player_god_id
	var slot: int = PlayerData.get_selected_deck(god_id)
	var original: Array = PlayerData.get_deck(god_id, slot)
	var menu: Control = (load("res://scenes/menus/MainMenu.tscn") as PackedScene).instantiate()
	var visited: Array = []
	menu.scene_changer = func(path: String) -> void: visited.append(path)
	add_child(menu)
	for frame in range(3):
		await get_tree().process_frame
	_check(menu.campaign_button.get_script() == TouchButtonScript
		and menu.pvp_button.get_script() == TouchButtonScript,
		"les boutons CAMPAGNE et PVP utilisent tous deux TouchButton")
	_check(menu.campaign_button.text == "CAMPAGNE" and menu.pvp_button.text == "PVP",
		"chaque mode garde un libellé permanent")
	_check(menu.mode_buttons.get_child_count() == 2
		and absf(menu.campaign_button.size.x - menu.pvp_button.size.x) <= 1.0
		and menu.campaign_button.size.y >= 108.0,
		"les deux modes partagent la même largeur tactile dans une ligne non absolue")
	_check(menu.campaign_button.get_theme_stylebox("normal")
		!= menu.pvp_button.get_theme_stylebox("normal"),
		"PVP reste distinct sans concurrencer le bouton principal")
	PlayerData._decks_by_god[god_id][slot] = []
	menu._refresh()
	menu.campaign_button.pressed.emit()
	_check(menu.deck_warning_overlay.visible
		and menu.deck_warning_message.text.contains("VEUILLEZ COMPLÉTER VOTRE DECK")
		and menu.deck_warning_message.text.contains("0 carte")
		and visited.is_empty(),
		"un deck incomplet ouvre une modale explicite sans changer de scène")
	menu.campaign_button.pressed.emit()
	menu.pvp_button.pressed.emit()
	_check(visited.is_empty() and menu.deck_warning_overlay.visible
		and menu.complete_deck_button.visible and menu.close_warning_button.visible,
		"plusieurs clics conservent une seule modale bloquante avec deux actions")
	menu.complete_deck_button.pressed.emit()
	_check(visited == ["res://scenes/menus/CollectionScreen.tscn"]
		and not menu.deck_warning_overlay.visible,
		"la modale conduit directement à la construction du deck")
	visited.clear()
	PlayerData._decks_by_god[god_id][slot] = original
	menu._refresh()
	menu.pvp_button.pressed.emit()
	_check(visited == ["res://scenes/menus/PvpLobby.tscn"],
		"un deck valide ouvre le salon PVP")
	visited.clear()
	menu.campaign_button.pressed.emit()
	_check(visited == ["res://scenes/campaign/CampaignMap.tscn"],
		"un deck valide ouvre la carte de campagne unifiée")
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
	_check(menu.visible and options.columns == 3 and options.get_child_count() == 7 and portraits_loaded,
		"le tiroir affiche les portraits de Sans dieu et des six dieux")
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
	page._on_primary_requested("de_boiteux_n1", CardActionDrawer.Source.COLLECTION)
	await get_tree().process_frame
	_check(PlayerData.get_active_deck() == ["de_boiteux_n1"] and not _shown_collection_ids(page).has("de_boiteux_n1")
		and not page.status_label.visible and _collection_cards(page)["de_boiteux_n1"] == cards["de_boiteux_n1"]
		and PlayerData.get_deck("veskar", 0) == ProfileFixture.DECK,
		"modifier le deuxième deck masque sa carte sans recréer la collection ni afficher de message de succès")
	page._on_primary_requested("de_boiteux_n1", CardActionDrawer.Source.DECK)
	_check(PlayerData.get_active_deck().is_empty() and _shown_collection_ids(page).has("de_boiteux_n1"),
		"retirer une carte agit seulement sur le deck sélectionné")
	page._select_deck(0)
	page._on_primary_requested("avortons_des_caves_n4", CardActionDrawer.Source.COLLECTION)
	_check(page.replacement_panel.visible, "un deck complet ouvre le remplacement depuis le deck sélectionné")
	page._on_replacement_requested("de_boiteux_n1")
	_check(not page.replacement_panel.visible and PlayerData.get_active_deck().has("avortons_des_caves_n4")
		and not PlayerData.get_active_deck().has("de_boiteux_n1") and PlayerData.get_deck("veskar", 1).is_empty(),
		"le remplacement immédiat enregistre uniquement l'emplacement courant")
	# Restaurer la composition initiale, puis vérifier les changements de contexte.
	page._commit_operation(DeckRules.try_replace(page._current_deck, "avortons_des_caves_n4", "de_boiteux_n1", "veskar"))
	page._select_deck(2)
	page._on_primary_requested("jumeau_de_cuivre_n1", CardActionDrawer.Source.COLLECTION)
	page._select_god("enigma")
	_check(page._current_deck.is_empty() and PlayerData.get_selected_deck() == 0,
		"changer de dieu ouvre sa banque sans copier le deck précédent")
	page._select_deck(1)
	page._on_primary_requested("porte_greffes_n1", CardActionDrawer.Source.COLLECTION)
	page._select_god("veskar")
	_check(page._current_deck == ["jumeau_de_cuivre_n1"] and PlayerData.get_selected_deck() == 2
		and PlayerData.get_deck("enigma", 1) == ["porte_greffes_n1"],
		"revenir à un dieu retrouve son dernier deck et préserve les autres banques")
	var menu: Control = (load("res://scenes/menus/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	_check(menu.deck_status.text.contains("Deck 3") and menu.deck_status.text.contains("1/8"),
		"l'accueil lit le numéro de deck actif et signale un deck incomplet")
	menu.queue_free()
	# Un ancien panneau ne doit jamais pouvoir modifier le nouveau deck.
	page._replacement_stone_id = "le_nud_hurlant_n2"
	page.replacement_panel.open_for(page._current_deck, "le_nud_hurlant_n2")
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


## La zone sûre ne décale que les conteneurs déclarés, uniquement quand une
## valeur est fournie : appliquer deux fois la même marge ne la cumule jamais.
func _test_safe_area() -> void:
	SafeArea.set_insets_for_tests({"top": 60.0, "left": 0.0, "right": 0.0})
	var page: Control = (load("res://scenes/menus/CollectionScreen.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	var content: Control = page.get_node("Content")
	_check(is_equal_approx(content.offset_top, 42.0 + 60.0),
		"zone sûre : le contenu descend de l'inset supérieur mesuré")
	_check(is_equal_approx(page.get_node("BottomNav").offset_top, -176.0),
		"zone sûre : la barre de navigation garde sa hauteur propre")
	SafeArea.set_insets_for_tests({"top": 60.0, "left": 0.0, "right": 0.0})
	_check(is_equal_approx(content.offset_top, 42.0 + 60.0),
		"zone sûre : une valeur identique ne cumule pas la marge")
	SafeArea.set_insets_for_tests({"top": 0.0, "left": 0.0, "right": 0.0})
	_check(is_equal_approx(content.offset_top, 42.0),
		"zone sûre : un appareil sans découpe retrouve la mise en page d'origine")
	var menu: Control = (load("res://scenes/menus/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	SafeArea.set_insets_for_tests({"top": 84.0, "left": 0.0, "right": 0.0})
	_check(is_equal_approx(menu.get_node("Content").offset_top, 64.0 + 84.0),
		"zone sûre : une scène déjà ouverte suit un changement de zone")
	menu.queue_free()
	page.queue_free()
	await get_tree().process_frame
	SafeArea.set_insets_for_tests(null)
	_check(SafeArea.insets()["top"] == 0.0,
		"zone sûre : hors mobile, aucune marge n'est appliquée")
	_check(is_equal_approx(SafeArea.cutout_depth([Rect2i(500, 26, 80, 48)], 2562.0), 74.0),
		"zone sûre : seule l'emprise de la caméra compte, pas la barre d'état")
	_check(is_equal_approx(SafeArea.cutout_depth([Rect2i(0, 2400, 80, 60)], 2562.0), 0.0),
		"zone sûre : une découpe basse ne pousse jamais le haut")
	_check(is_equal_approx(SafeArea.cutout_depth([], 2562.0), 0.0),
		"zone sûre : sans découpe, aucune profondeur")
	_check(is_equal_approx(SafeArea.clamp_top(115.0), 36.0),
		"zone sûre : la bande haute complète ne pousse pas l'interface")
	_check(is_equal_approx(SafeArea.clamp_top(8.0), 8.0),
		"zone sûre : une petite découpe garde sa valeur")


## Vider un deck est une action destructive confirmée : elle ne touche que
## l'emplacement affiché et laisse le joueur reconstruire immédiatement.
func _test_deck_clear() -> void:
	var original: Array = PlayerData.get_deck("veskar", 0)
	PlayerData.set_selected_deck(1)
	PlayerData.set_player_deck(["de_boiteux_n1"])
	PlayerData.set_selected_deck(2)
	PlayerData.set_player_deck(["jumeau_de_cuivre_n1"])
	PlayerData.set_selected_deck(0)
	var page: Control = (load("res://scenes/menus/CollectionScreen.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	var button: Button = page.clear_deck_button
	_check(button.get_script() == TouchButtonScript and button.text == "VIDER LE DECK"
		and not button.disabled,
		"deck : un bouton tactile permet de vider la composition affichée")
	button.pressed.emit()
	await get_tree().process_frame
	_check(page.confirm_popup.visible and page.confirm_popup.is_open()
		and page.confirm_popup.message_label.text
			== "Voulez-vous vraiment supprimer complètement ce deck ?"
		and PlayerData.get_active_deck().size() == DeckRules.DECK_SIZE,
		"deck : vider demande une confirmation bloquante avant toute écriture")
	page.confirm_popup.no_btn.pressed.emit()
	_check(not page.confirm_popup.is_open()
		and PlayerData.get_active_deck().size() == DeckRules.DECK_SIZE,
		"deck : refuser la confirmation conserve toutes les cartes")
	button.pressed.emit()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	page.confirm_popup._gui_input(click)
	_check(not page.confirm_popup.is_open()
		and PlayerData.get_active_deck().size() == DeckRules.DECK_SIZE,
		"deck : un appui à côté de la confirmation annule la suppression")
	button.pressed.emit()
	page.confirm_popup.yes_btn.pressed.emit()
	await get_tree().process_frame
	var remaining_cards := 0
	for row in page.deck_rows.get_children():
		for wrapper in row.get_children():
			if wrapper.get_child_count() > 0 and wrapper.get_child(0) is StoneCard:
				remaining_cards += 1
	_check(not page.confirm_popup.visible and PlayerData.get_active_deck().is_empty()
		and page._current_deck.is_empty() and remaining_cards == 0
		and page.deck_count_label.text.begins_with("0/8") and button.disabled
		and not page.status_label.visible,
		"deck : confirmer libère les huit cases de l'emplacement affiché")
	_check(PlayerData.get_deck("veskar", 1) == ["de_boiteux_n1"]
		and PlayerData.get_deck("veskar", 2) == ["jumeau_de_cuivre_n1"],
		"deck : vider un emplacement ne modifie jamais les deux autres")
	page._on_primary_requested("de_boiteux_n1", CardActionDrawer.Source.COLLECTION)
	await get_tree().process_frame
	_check(page._current_deck == ["de_boiteux_n1"] and not button.disabled,
		"deck : un deck vidé accepte immédiatement de nouvelles cartes")
	var save_path: String = PlayerData._save_path
	PlayerData._save_path = save_path + "/missing/profile.json"
	_expect_log("PlayerData: profil non enregistré")
	button.pressed.emit()
	page.confirm_popup.yes_btn.pressed.emit()
	_check(PlayerData.get_active_deck() == ["de_boiteux_n1"] and page.status_label.visible
		and page.status_label.text.contains("échoué")
		and not page.confirm_popup.is_open(),
		"deck : un échec d'écriture conserve la composition et affiche l'erreur")
	PlayerData._save_path = save_path
	# Les tests suivants retrouvent le deck de départ et deux emplacements vides.
	PlayerData.set_selected_deck(1)
	PlayerData.set_player_deck([])
	PlayerData.set_selected_deck(2)
	PlayerData.set_player_deck([])
	PlayerData.set_selected_deck(0)
	PlayerData.set_player_deck(original)
	page.queue_free()
	await get_tree().process_frame


func _test_battle_uses_selected_deck() -> void:
	var saved_npc := BattleContext.selected_npc_id
	var saved_first := BattleContext.forced_first_player
	PlayerData.set_selected_deck(2)
	var reordered := ProfileFixture.DECK.duplicate()
	reordered.reverse()
	PlayerData.set_player_deck(reordered)
	BattleContext.selected_npc_id = "disciple_muraille"
	BattleContext.forced_first_player = GameState.PLAYER_HUMAN
	var board: Control = (load("res://scenes/game/Board.tscn") as PackedScene).instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var state: GameState = board.turn_manager.get_state()
	_check(state.hand_of(GameState.PLAYER_HUMAN) == reordered and state.god_of(GameState.PLAYER_HUMAN) == "veskar",
		"un vrai combat reçoit les huit cartes du troisième deck et le dieu sélectionné")
	board.queue_free()
	await get_tree().process_frame
	BattleContext.selected_npc_id = saved_npc
	BattleContext.forced_first_player = saved_first
	PlayerData.set_player_deck([])
	PlayerData.set_selected_deck(0)


## Le profil ne compte plus des victoires agrégées par palier : il affiche
## sept chemins et le nombre de niveaux gagnés dans l'ordre du serpentin.
func _test_stats_progress() -> void:
	var saved_stats: Dictionary = PlayerData.stats.duplicate(true)
	PlayerData.stats["per_npc"]["bot_veskar_n1_tres_facile"] = {
		"wins": 1, "games": 1, "best_diff": 2}
	PlayerData.stats["per_npc"]["bot_veskar_n1_facile"] = {
		"wins": 1, "games": 1, "best_diff": 1}
	# Une victoire isolée d'une ancienne partie ne doit pas gonfler le compteur.
	PlayerData.stats["per_npc"]["bot_veskar_n34_tres_difficile"] = {
		"wins": 1, "games": 1, "best_diff": 0}
	var page: Control = (load("res://scenes/menus/Stats.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	var list: VBoxContainer = page.get_node("Root/Scroll/Content/NPCPanel/NPCList")
	var names: Array = []
	var all_fifteen := true
	for row in list.get_children():
		names.append(row.get_child(1).text)
		all_fifteen = all_fifteen and row.get_child(2).text.ends_with("/15")
	_check(list.get_child_count() == 7
		and names == ["Véskar", "Nérava", "Kharûn", "Ilyr", "Sylkha", "Énigma", "Pr.Stone"],
		"le profil affiche un chemin par dieu et Pr.Stone, dans l'ordre du catalogue")
	_check(all_fifteen and list.get_child(0).get_child(2).text == "2/15"
		and list.get_child(6).get_child(2).text == "0/15",
		"le profil compte les niveaux gagnés dans l'ordre et ignore une victoire isolée")
	page.queue_free()
	await get_tree().process_frame
	PlayerData.stats = saved_stats


func _test_generated_opponent_battle() -> void:
	var saved_npc := BattleContext.selected_npc_id
	var saved_opponent := BattleContext.selected_opponent
	var saved_first := BattleContext.forced_first_player
	var opponent := OpponentCatalogModel.build("enigma", "n1", "moyen")
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
		and state.god_of(GameState.PLAYER_AI) == "enigma"
		and state.hand_of(GameState.PLAYER_AI) == StoneLoader.build_hand(opponent["deck"]),
		"un combat généré reçoit le deck, le dieu et l'identifiant de la rencontre choisie")
	board.queue_free()
	await get_tree().process_frame
	BattleContext.selected_npc_id = saved_npc
	BattleContext.selected_opponent = saved_opponent
	BattleContext.forced_first_player = saved_first
	PlayerData.set_player_deck([])
	PlayerData.set_selected_deck(0)


func _test_encounter_selection() -> void:
	var page: Control = (load("res://scenes/menus/EncounterSelect.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	var grid: GridContainer = page.get_node("Root/Scroll/Content/Gods")
	var godless: VBoxContainer = page.get_node("Root/Scroll/Content/Godless")
	var first_tile: Variant = grid.get_child(0)
	var neutral_tile: Variant = godless.get_child(0)
	_check(grid.columns == UITheme.ENCOUNTER_COLUMNS and grid.get_child_count() == 6
		and godless.get_child_count() == 1,
		"les Rencontres présentent les six dieux en grille et Pr.Stone sur une ligne dédiée")
	var portraits_loaded := true
	var ids: Array = []
	for tile in grid.get_children():
		portraits_loaded = portraits_loaded and tile.has_portrait() and tile.god_id != ""
		ids.append(tile.god_id)
	_check(portraits_loaded and ids == ["veskar", "nerava", "kharun", "ilyr", "sylkha", "enigma"],
		"chaque case de dieu charge son portrait et suit l'ordre du catalogue")
	_check(neutral_tile.god_id == OpponentCatalogModel.NEUTRAL_BOT_ID
		and neutral_tile.has_portrait()
		and neutral_tile.god_name_text() == OpponentCatalogModel.NEUTRAL_BOT_NAME.to_upper(),
		"Pr.Stone reste accessible sans dieu avec son propre portrait")
	_check(first_tile.god_name_text() == "VÉSKAR"
		and first_tile.family_text_value() == "LES ALÉATORS",
		"une case affiche le nom du dieu et sa famille")
	page.queue_free()
	await get_tree().process_frame


func _test_encounter_path() -> void:
	var saved_source := BattleContext.selected_source_id
	var saved_stats: Dictionary = PlayerData.stats.duplicate(true)
	# Une victoire isolée du dernier niveau simule une ancienne sauvegarde :
	# elle ne doit ni valider ce rond ni ouvrir le suivant.
	PlayerData.stats["per_npc"]["bot_nerava_n34_tres_difficile"] = {
		"wins": 1, "games": 2, "best_diff": -1}
	BattleContext.select_source("nerava")
	var page: Control = (load("res://scenes/menus/EncounterPath.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame
	var track: Variant = page.get_node("Root/Scroll/Track")
	_check(track.node_count() == 15 and page._path.size() == 15,
		"le chemin d'un dieu propose trois paliers de cinq difficultés")
	var first: Variant = track.node_for(0)
	var second: Variant = track.node_for(1)
	var last: Variant = track.node_for(14)
	_check(first.state == EncounterPathModel.State.AVAILABLE and not first.disabled
		and second.state == EncounterPathModel.State.LOCKED and second.disabled,
		"seul le premier niveau est ouvert tant qu'aucune victoire n'est enregistrée")
	_check(last.state == EncounterPathModel.State.LOCKED and bool(page._path[14]["beaten"]),
		"une victoire hors séquence ne valide pas un rond au milieu du chemin")
	_check(page.level_label.text.contains("Niveau 1")
		and page.level_label.text.contains("Très facile")
		and page.progress_label.text.contains("0 / 15"),
		"le pied de page décrit le niveau sélectionné et la progression")
	page._select_level(1)
	_check(page._selected_index == 0, "un niveau verrouillé ne peut pas être sélectionné")
	PlayerData.stats["per_npc"]["bot_nerava_n1_tres_facile"] = {
		"wins": 1, "games": 1, "best_diff": 3}
	page._reload_path()
	page._select_level(1)
	_check(track.node_for(0).state == EncounterPathModel.State.COMPLETED
		and track.node_for(1).state == EncounterPathModel.State.AVAILABLE
		and page._selected_index == 1,
		"une victoire termine le premier rond et débloque le suivant")
	track.node_for(0).pressed.emit()
	_check(page._selected_index == 0 and page.level_label.text.contains("Très facile")
		and page.progress_label.text.contains("1 / 15"),
		"un rond terminé peut être sélectionné pour rejouer le niveau")
	track.node_for(1).pressed.emit()
	_check(page._selected_index == 1 and page.level_label.text.contains("Facile"),
		"un rond ouvert se sélectionne depuis le chemin")
	var opponent: Dictionary = page._build_opponent()
	_check(opponent.get("id", "") == "bot_nerava_n1_facile"
		and opponent.get("god_id", "") == "nerava"
		and opponent.get("bracket_id", "") == "n1"
		and opponent.get("difficulty", "") == "facile",
		"le niveau sélectionné génère exactement l'adversaire du catalogue")
	page.queue_free()
	await get_tree().process_frame
	BattleContext.select_source(OpponentCatalogModel.NEUTRAL_BOT_ID)
	var neutral_page: Control = (load("res://scenes/menus/EncounterPath.tscn") as PackedScene).instantiate()
	add_child(neutral_page)
	await get_tree().process_frame
	_check(neutral_page._path.size() == 15
		and neutral_page.god_name.text == OpponentCatalogModel.NEUTRAL_BOT_NAME.to_upper()
		and not neutral_page.portrait.visible,
		"Pr.Stone possède son propre chemin de quinze niveaux, sans portrait divin")
	neutral_page.queue_free()
	await get_tree().process_frame
	PlayerData.stats = saved_stats
	BattleContext.selected_source_id = saved_source


func _test_neutral_bot_battle() -> void:
	var saved_npc := BattleContext.selected_npc_id
	var saved_opponent := BattleContext.selected_opponent
	var saved_first := BattleContext.forced_first_player
	var opponent := OpponentCatalogModel.build_neutral("n1", "moyen")
	BattleContext.select_opponent(opponent)
	BattleContext.forced_first_player = GameState.PLAYER_HUMAN
	PlayerData.set_selected_deck(0)
	PlayerData.set_player_deck(ProfileFixture.DECK.duplicate())
	var board: Control = (load("res://scenes/game/Board.tscn") as PackedScene).instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var state: GameState = board.turn_manager.get_state()
	var all_neutral := true
	for stone_id in state.hand_of(GameState.PLAYER_AI):
		all_neutral = all_neutral and StoneLoader.stone_affinity(str(stone_id)) == "neutral"
	_check(state.npc_id == opponent["id"]
		and state.god_of(GameState.PLAYER_AI) == ""
		and state.hand_of(GameState.PLAYER_AI) == StoneLoader.build_hand(opponent["deck"])
		and all_neutral,
		"un combat contre Pr.Stone fonctionne avec huit cartes neutres et aucun dieu")
	board.queue_free()
	await get_tree().process_frame
	var prebattle: Control = (load("res://scenes/menus/PreBattle.tscn") as PackedScene).instantiate()
	add_child(prebattle)
	await get_tree().process_frame
	_check(prebattle.opponent_god_name.text == "LUI • Sans dieu"
		and prebattle.opponent_god_family.text == ""
		and prebattle.opponent_god_portrait.has_portrait(),
		"l'avant-combat montre Pr.Stone avec son portrait et sans texte technique")
	prebattle.queue_free()
	await get_tree().process_frame
	BattleContext.selected_npc_id = saved_npc
	BattleContext.selected_opponent = saved_opponent
	BattleContext.forced_first_player = saved_first
	PlayerData.set_player_deck([])
	PlayerData.set_selected_deck(0)


func _test_result_uses_generated_opponent() -> void:
	var saved_id := BattleContext.selected_npc_id
	var saved_source := BattleContext.selected_source_id
	var saved_opponent := BattleContext.selected_opponent
	var saved_winner := BattleContext.last_winner
	var saved_human := BattleContext.last_score_human
	var saved_ai := BattleContext.last_score_ai
	var opponent := OpponentCatalogModel.build("nerava", "n2", "tres_difficile")
	BattleContext.select_opponent(opponent)
	BattleContext.record_result(GameState.PLAYER_HUMAN, 42, 17)
	var page: Control = (load("res://scenes/menus/Result.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	var expected_name := UIFormat.combatant_name(str(opponent["name"]), 18)
	_check(page.result_label.text == "VICTOIRE !"
		and page.score_label.text.contains(expected_name)
		and not page.score_label.text.contains(" — Le ")
		and page.score_label.text.contains("42") and page.score_label.text.contains("17"),
		"l'écran de résultat affiche le nom court et le score de la rencontre")
	page.queue_free()
	await get_tree().process_frame
	BattleContext.selected_npc_id = saved_id
	BattleContext.selected_source_id = saved_source
	BattleContext.selected_opponent = saved_opponent
	BattleContext.record_result(saved_winner, saved_human, saved_ai)


## Le résultat propose cinq sorties et ne prépare le niveau suivant qu'après
## une victoire, dans le même chemin et hors du dernier rond.
func _test_result_actions() -> void:
	var saved_id := BattleContext.selected_npc_id
	var saved_source := BattleContext.selected_source_id
	var saved_opponent := BattleContext.selected_opponent
	var saved_winner := BattleContext.last_winner
	var saved_human := BattleContext.last_score_human
	var saved_ai := BattleContext.last_score_ai
	var levels := OpponentCatalogModel.levels_for("veskar")
	BattleContext.select_opponent(OpponentCatalogModel.build("veskar", "n1", "tres_facile"))
	BattleContext.record_result(GameState.PLAYER_HUMAN, 30, 12)
	var page: Control = (load("res://scenes/menus/Result.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	_check(page.next_btn.visible and page.next_btn.text == "Niveau suivant"
		and page.replay_btn.text == "Rejouer"
		and page.level_btn.text == "Choisir un autre niveau"
		and page.gods_btn.text == "Choisir un autre dieu"
		and page.menu_btn.text == "Accueil",
		"le résultat propose les cinq sorties de la boucle de rencontres")
	var buttons: Array[Button] = [page.next_btn, page.replay_btn, page.level_btn,
		page.gods_btn, page.menu_btn]
	var wired := true
	for button in buttons:
		wired = wired and not button.pressed.get_connections().is_empty()
	_check(wired, "les cinq boutons du résultat sont reliés à une action")
	var handlers: Array[String] = ["_on_next_level", "_on_replay", "_on_level_select",
		"_on_god_select", "_on_menu"]
	var correctly_wired := true
	for index in range(buttons.size()):
		var methods: Array = []
		for connection in buttons[index].pressed.get_connections():
			methods.append(str(connection["callable"].get_method()))
		correctly_wired = correctly_wired and methods.has(handlers[index])
	_check(correctly_wired, "chaque bouton du résultat appelle l'action attendue")
	_check(page.next_btn.visible
		and str(page._next_level().get("opponent_id", "")) == str(levels[1]["opponent_id"]),
		"après une victoire, le résultat prépare le niveau suivant du même chemin")
	BattleContext.last_result_saved = false
	BattleContext.last_save_error = ERR_FILE_CANT_WRITE
	page._refresh_actions()
	page._refresh_save_status()
	_check(not page.next_btn.visible and page.save_status.visible
		and page.retry_save_btn.visible and page.save_status.text.contains("enregistrée"),
		"une sauvegarde échouée bloque le niveau suivant et propose un nouvel essai")
	BattleContext.last_result_saved = true
	BattleContext.last_save_error = OK
	page._refresh_actions()
	page._refresh_save_status()
	var winner_color := Color(str(StoneLoader.get_god(PlayerData.player_god_id)["color"]))
	_check(page.background.room == MenuBackground.Room.AFTERMATH
		and page.background.neon_primary_color == winner_color
		and page.background._winner_firework_color(0) != page.background._winner_firework_color(1)
		and page.background._winner_firework_color(1) != page.background._winner_firework_color(2)
		and page.background._winner_firework_color(2) != page.background._winner_firework_color(3)
		and page.background._winner_firework_color(3) != page.background._winner_firework_color(4),
		"la victoire de campagne dessine des feux d'artifice aux nuances du dieu gagnant")
	BattleContext.select_opponent(OpponentCatalogModel.build("veskar", "n34", "tres_difficile"))
	page._refresh_actions()
	_check(not page.next_btn.visible and page._next_level().is_empty(),
		"le dernier niveau du chemin ne propose pas de suivant")
	BattleContext.select_opponent(OpponentCatalogModel.build("veskar", "n1", "tres_facile"))
	BattleContext.record_result(GameState.PLAYER_AI, 12, 30)
	page._refresh_actions()
	_check(not page.next_btn.visible and page.replay_btn.visible
		and page.level_btn.visible and page.gods_btn.visible and page.menu_btn.visible,
		"une défaite retire le niveau suivant et laisse les quatre autres sorties")
	BattleContext.select_opponent(OpponentCatalogModel.build("kharun", "n1", "tres_facile"))
	var defeat_page: Control = (load("res://scenes/menus/Result.tscn") as PackedScene).instantiate()
	add_child(defeat_page)
	await get_tree().process_frame
	var campaign_winner_color := Color(str(StoneLoader.get_god("kharun")["color"]))
	_check(defeat_page.background.room == MenuBackground.Room.AFTERMATH_DEFEAT
		and defeat_page.background.neon_primary_color == campaign_winner_color
		and defeat_page.background.neon_secondary_color == campaign_winner_color
		and defeat_page.background.neon_tertiary_color == campaign_winner_color,
		"la défaite de campagne affiche un crâne dans la couleur du dieu gagnant")
	defeat_page.queue_free()
	await get_tree().process_frame
	page.queue_free()
	await get_tree().process_frame
	BattleContext.selected_npc_id = saved_id
	BattleContext.selected_source_id = saved_source
	BattleContext.selected_opponent = saved_opponent
	BattleContext.record_result(saved_winner, saved_human, saved_ai)


func _test_cost_format() -> void:
	_check(UIFormat.cost(11.5) == "11,5" and UIFormat.cost(8.0) == "8",
		"les coûts s'affichent avec la virgule française, sans décimale inutile")
	_check(UIFormat.cost(1.25) == "1,25" and UIFormat.cost(3.75) == "3,75"
		and UIFormat.cost(8.25) == "8,25", "les quarts de point ne sont jamais arrondis à un dixième")
	_check(UIFormat.cost(StoneLoader.stone_cost("veilleur_bifurque_n1")) == "4,75"
		and UIFormat.cost(StoneLoader.stone_cost("echassier_des_brumes_n3")) == "11,75",
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
	var phone := BattleLayoutModel.calculate(Vector2(984.0, 2280.0), 271.0,
		40.0, float(UITheme.GAP_MEDIUM), DeckRules.DECK_SIZE)
	var tablet := BattleLayoutModel.calculate(Vector2(1104.0, 1800.0), 271.0,
		40.0, float(UITheme.GAP_MEDIUM), DeckRules.DECK_SIZE)
	_check(int(phone["hand_columns"]) == 3
		and int(tablet["hand_columns"]) == 4
		and float(phone["hand_card_size"]) > float(tablet["hand_card_size"]),
		"combat responsive : le téléphone utilise trois grandes colonnes et la tablette quatre")
	_check(float(phone["board_side"]) >= 800.0 and float(tablet["board_side"]) >= 800.0,
		"combat responsive : la main grandit sans sacrifier la lisibilité du plateau")
	var phone_available := 2280.0 - 271.0 - 3.0 * 40.0
	_check(phone_available - float(phone["board_side"]) - float(phone["hand_height"]) < 3.0,
		"combat responsive : aucun surplus vertical n'est laissé entre le plateau et la main")
	hand.size = Vector2(984.0, float(phone["hand_height"]))
	hand.configure(3, float(phone["hand_card_size"]))
	hand.refresh(["fx_plain", "fx_attack2", "fx_wall", "fx_ranged",
		"fx_target", "fx_thief", "fx_swarm_a", "fx_swarm_b"])
	await get_tree().process_frame
	_check(hand.get_child_count() == 8
		and hand.get_child(6).position.x > hand.get_child(0).position.x,
		"combat responsive : les deux cartes de la dernière rangée sont centrées")
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
	BattleContext.selected_npc_id = "disciple_muraille"
	BattleContext.forced_first_player = 0
	var page: Control = (load("res://scenes/menus/PreBattle.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	_check(page.player_god_portrait.has_portrait() and page.opponent_god_portrait.has_portrait()
		and page.player_god_name.text == "TOI • Véskar"
		and page.opponent_god_name.text == "LUI • Kharûn",
		"l'avant-combat présente les portraits et l'identité des deux dieux autour de la pièce")
	_check(page.background.neon_primary_color == Color("#e75aa8")
		and page.background.neon_secondary_color == Color("#72c7d8"),
		"les néons du rituel reprennent les couleurs du joueur et de son adversaire")
	_check(page.coin.get_script() == load("res://scripts/ui/CoinMedallion.gd")
		and page.coin.get_theme_stylebox("panel").bg_color == Color("#35282b")
		and page.coin.get_theme_stylebox("panel").border_color == Color("#b77451"),
		"la pièce a un relief sombre et un bord métallique assortis au rituel")
	## Hors du premier parcours guidé, la pièce retombe et le bouton s'active
	## aussitôt : aucun temps de lecture supplémentaire ne doit subsister.
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


## Le salon envoie le premier joueur tiré par l'hôte : l'écran de pile ou face
## doit le révéler sans retirer un nouveau nombre au hasard, et il doit parler
## au camp de l'appareil qui regarde. Deux téléphones annonçaient « LUI » à la
## fois alors que le client commençait : la face est désormais locale.
func _test_pvp_prebattle() -> void:
	PvpMatchContext.clear()
	var saved_first := BattleContext.forced_first_player
	BattleContext.forced_first_player = 0
	PvpMatchContext.begin(_pvp_config(GameState.PLAYER_TWO, []), GameState.PLAYER_TWO, 2,
		{"name": "Client", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
		{"name": "Hôte", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()})
	var page: Control = (load("res://scenes/menus/PreBattle.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	_check(page.npc_label.text == "Hôte" and page.difficulty_label.text.contains("PVP"),
		"l'avant-combat PVP nomme l'adversaire du salon et annonce le mode local")
	await get_tree().create_timer(1.6).timeout
	_check(page.coin_label.text == "TOI" and page.coin_flip_label.text == "Tu commences !",
		"le pile ou face PVP parle au joueur local : le client qui commence voit TOI")
	_check(BattleContext.forced_first_player == 0,
		"l'avant-combat PVP ne réécrit pas le tirage de la campagne")
	_check(not page.start_button.disabled,
		"le plateau s'ouvre une fois la pièce retombée, même en PVP")
	page.queue_free()
	await get_tree().process_frame

	PvpMatchContext.begin(_pvp_config(GameState.PLAYER_TWO, []), GameState.PLAYER_ONE, 1,
		{"name": "Hôte", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
		{"name": "Client", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()})
	var host_page: Control = (load("res://scenes/menus/PreBattle.tscn") as PackedScene).instantiate()
	add_child(host_page)
	await get_tree().process_frame
	await get_tree().create_timer(1.6).timeout
	_check(host_page.coin_label.text == "LUI" and host_page.coin_flip_label.text == "Client commence !",
		"le même tirage montre la face adverse sur le téléphone de l'hôte")
	_check(host_page.npc_label.text == "Client" and host_page.player_god_name.text.contains("TOI")
		and host_page.opponent_god_name.text.contains("LUI"),
		"chaque appareil garde son dieu à gauche et celui de l'adversaire à droite")
	host_page.queue_free()
	await get_tree().process_frame
	PvpMatchContext.clear()
	BattleContext.forced_first_player = saved_first


## Deux régressions corrigées : les cases bloquées étaient dessinées après le
## premier coup, et le plateau ne se rouvrait jamais après la confirmation de
## l'hôte, ce qui bloquait le joueur suivant.
func _test_pvp_board_opens_ready() -> void:
	PvpMatchContext.clear()
	PvpMatchContext.begin(_pvp_config(GameState.PLAYER_ONE, [[1.0, 2.0]]),
		GameState.PLAYER_ONE, 1,
		{"name": "Hôte", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
		{"name": "Client", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()})
	var board: Control = (load("res://scenes/game/Board.tscn") as PackedScene).instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(board.board_view.slot_at(1, 2).get_node_or_null("BlockedMark") != null,
		"les cases bloquées du salon sont marquées dès l'ouverture du plateau PVP")
	_check(board.board_view.slot_at(0, 0).get_node_or_null("BlockedMark") == null,
		"une case libre du plateau PVP ne porte pas de marque de blocage")
	_check(board.board_view.slot_at(0, 0).mouse_filter == Control.MOUSE_FILTER_STOP,
		"le premier joueur peut toucher le plateau dès son ouverture")
	var coordinator = board._driver._coordinator
	coordinator._set_can_submit(false)
	await get_tree().process_frame
	_check(board.board_view.slot_at(0, 0).mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"le plateau se referme tant que l'hôte n'a pas confirmé le tour")
	coordinator._set_can_submit(true)
	await get_tree().process_frame
	_check(board.board_view.slot_at(0, 0).mouse_filter == Control.MOUSE_FILTER_STOP,
		"la confirmation de l'hôte rouvre le plateau du joueur suivant")
	board.queue_free()
	await get_tree().process_frame
	PvpMatchContext.clear()
	LanSession.reset()


## Le salon PVP ne montre qu'un écran à la fois : choix du mode, recherche,
## puis salle d'attente. L'adresse proposée est celle du Wi-Fi, pas celle d'un
## VPN, qui n'est pas joignable depuis l'autre téléphone.
func _test_pvp_lobby_screens() -> void:
	var lobby_page := load("res://scripts/ui/pvp/PvpLobbyController.gd")
	_check(lobby_page.rank_addresses(
		["10.143.85.142", "192.168.1.98", "127.0.0.1", "169.254.2.3"]).size() == 2
		and lobby_page.rank_addresses(["10.143.85.142", "192.168.1.98"])[0] == "192.168.1.98",
		"l'adresse proposée par l'hôte est celle du Wi-Fi, pas celle d'un VPN")
	_check(lobby_page.host_only("192.168.1.98:45555") == "192.168.1.98"
		and lobby_page.host_only(" 192.168.1.98 ") == "192.168.1.98"
		and lobby_page.host_only(" :45555") == "",
		"une adresse collée avec son port reste utilisable telle quelle")
	var page: Control = (load("res://scenes/menus/PvpLobby.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	_check(page.mode_screen.visible and not page.join_screen.visible
		and not page.lobby_screen.visible,
		"le salon PVP n'ouvre que le choix du mode")
	_check(page.background.room == MenuBackground.Room.PVP,
		"le choix de mode utilise le décor d'entrée dans l'arène")
	_check(page.create_button.text == "CRÉER UNE PARTIE"
		and page.join_button.text == "REJOINDRE UNE PARTIE",
		"le choix du mode propose de créer ou de rejoindre une partie")
	var create_style := page.create_card.get_theme_stylebox("panel") as StyleBoxFlat
	var join_style := page.join_card.get_theme_stylebox("panel") as StyleBoxFlat
	_check(create_style != null and join_style != null
		and create_style.border_width_left == 3 and create_style.border_color == UITheme.COL_ACCENT
		and join_style.border_width_left == 3 and join_style.border_color == UITheme.COL_NEON
		and create_style.bg_color.a < 1.0 and join_style.bg_color.a < 1.0
		and page.create_card.get_node("CreateBox").get_child(0).name == "CreateHint"
		and page.create_card.get_node("CreateBox").get_child(2).name == "CreateButton"
		and page.join_card.get_node("JoinBox").get_child(0).name == "JoinHint"
		and page.create_card.get_node("CreateBox/CreateHint").get_theme_font_size("font_size") == 28,
		"les deux options sont des cartes encadrées, aide lisible au-dessus de chaque bouton")
	var refresh := false
	for button in page.find_children("*", "Button"):
		if str((button as Button).text).contains("ACTUALISER"):
			refresh = true
	_check(not refresh,
		"la liste des salons se met à jour toute seule, sans bouton ACTUALISER")
	page.join_button.pressed.emit()
	await get_tree().process_frame
	_check(page.join_screen.visible and not page.mode_screen.visible,
		"rejoindre ouvre directement la recherche de salons")
	_check(page.background.room == MenuBackground.Room.PVP,
		"la recherche conserve le même décor d'arène que le choix du mode")
	_check(page.address_input.visible and page.connect_button.text == "REJOINDRE"
		and page.connect_button.is_inside_tree(),
		"la saisie d'adresse reste disponible sur le même écran que la liste")
	_check(page.join_refresh.visible and page.join_refresh.text == "RELANCER",
		"la recherche conserve un bouton pour relancer l'écoute")
	page._attempted_address = "192.0.2.44"
	page._attempted_host_name = "Hôte de test"
	page._connection_attempt_pending = true
	LanSession.state = LanSession.State.CONNECTING
	page._refresh_status()
	_check(page.connection_overlay.visible and page.cancel_connection_button.visible
		and page.join_refresh.visible and page.address_row.visible,
		"la connexion s'affiche en fenêtre modale sans masquer la recherche")
	_check(page.connection_target.text.contains("Hôte de test")
		and page.connection_target.text.contains("192.0.2.44:45555"),
		"la fenêtre indique l'hôte et l'adresse réseau réellement visée")
	page.cancel_connection_button.pressed.emit()
	await get_tree().process_frame
	_check(not page.connection_overlay.visible and page.address_input.text == "192.0.2.44"
		and LanSession.state == LanSession.State.DISCOVERING,
		"annuler ferme la tentative, conserve l'adresse et reprend la recherche")
	LanSession._on_connection_failed()
	_check(LanSession.state == LanSession.State.DISCOVERING,
		"un rappel ENet tardif ne ferme pas la recherche après annulation")
	var waiting_lobby := LobbyCoordinator.new()
	waiting_lobby._is_host = true
	waiting_lobby._local["name"] = "Hôte"
	waiting_lobby._local["god_id"] = "kharun"
	waiting_lobby._local["deck_valid"] = true
	page._lobby = waiting_lobby
	page._fill_lobby()
	_check(page.mode_option.item_count == 4 and page.series_option.item_count == 3
		and page.tier_option.item_count == 4,
		"le salon expose les quatre modes, les trois formats de série et les quatre paliers")
	_check(not page.tier_row.visible,
		"le mode classique masque le palier de puissance qui ne s'applique pas")
	var popup: PopupMenu = page.mode_option.get_popup()
	var popup_panel := popup.get_theme_stylebox("panel") as StyleBoxFlat
	var popup_hover := popup.get_theme_stylebox("hover") as StyleBoxFlat
	_check(popup_panel != null and popup_hover != null
		and popup_panel.border_color == UITheme.COL_NEON
		and popup_hover.bg_color == UITheme.COL_SELECTED,
		"les listes de règles et leur fenêtre utilisent le thème néon du jeu")
	_check(not page.mode_option.disabled and not page.rules_hint.visible,
		"l'hôte peut modifier les règles sans texte redondant sous les options")
	page.mode_option.select(1)
	page.mode_option.item_selected.emit(1)
	_check(str(waiting_lobby.rules()["mode"]) == "random"
		and int(waiting_lobby.state()["rules"]["revision"]) == 1,
		"changer de mode applique la règle autoritaire et incrémente la révision")
	_check(page.tier_row.visible and not page.tier_option.disabled,
		"les modes générés affichent le palier de puissance")
	page.mode_option.select(3)
	page.mode_option.item_selected.emit(3)
	_check(str(waiting_lobby.rules()["mode"]) == "draft"
		and int(waiting_lobby.rules()["power_tier"]) >= 2
		and page.tier_option.is_item_disabled(0)
		and page.rules_hint.visible and page.rules_hint.text.contains("palier 2"),
		"Sélection désactive le palier 1 impossible et en explique la raison")
	waiting_lobby._is_host = false
	page._fill_lobby()
	_check(page.mode_option.disabled and page.series_option.disabled
		and page.tier_option.disabled and page.rules_hint.text.contains("Seul l'hôte"),
		"le client voit les règles sans pouvoir les modifier")
	waiting_lobby._is_host = true
	page._fill_lobby()
	var host_color := Color(str(StoneLoader.get_god("kharun")["color"]))
	_check(page.background.neon_primary_color == host_color
		and page.background.neon_secondary_color == host_color,
		"le salon en attente garde toutes les parties de l'arche et des épées à la couleur de l'hôte")
	waiting_lobby._remote["name"] = "Client"
	waiting_lobby._remote["god_id"] = "veskar"
	waiting_lobby._connected = true
	waiting_lobby._status = LobbyCoordinator.STATUS_CONNECTED
	page._fill_lobby()
	_check(page.background.neon_primary_color == host_color
		and page.background.neon_secondary_color
			== Color(str(StoneLoader.get_god("veskar")["color"])),
		"le salon adopte les deux couleurs une fois le dieu adverse reçu")
	page._lobby = null
	page._refresh_status()
	page._attempted_address = "192.0.2.44"
	page._attempted_host_name = "Hôte de test"
	page._connection_attempt_pending = true
	LanSession.state = LanSession.State.DISCONNECTED
	LanSession.last_notice = "Délai de connexion dépassé."
	page._refresh_status()
	_check(page.connection_overlay.visible and page.connection_error.visible
		and page.connection_error.text == "Délai de connexion dépassé."
		and page.retry_connection_button.visible and page.close_connection_button.visible,
		"un échec affiche sa cause, l'adresse tentée et les actions adaptées")
	page.close_connection_button.pressed.emit()
	await get_tree().process_frame
	_check(not page.connection_overlay.visible and page.join_screen.visible
		and LanSession.state == LanSession.State.DISCOVERING,
		"fermer l'échec ramène à la recherche et relance l'écoute")
	var abandoned_lobby := LobbyCoordinator.new()
	abandoned_lobby._connected = true
	abandoned_lobby._local["deck_valid"] = true
	abandoned_lobby._status = LobbyCoordinator.STATUS_CONNECTED
	page._lobby = abandoned_lobby
	page._refresh_status()
	_check(not page.ready_button.disabled
		and page.background.room == MenuBackground.Room.PVP,
		"un client connecté peut se déclarer prêt avant le départ de l'hôte")
	LanSession.last_notice = "L'hôte a quitté le salon."
	LanSession.state = LanSession.State.DISCONNECTED
	page._on_session_state(LanSession.State.DISCONNECTED)
	_check(page._lobby == null and page.join_screen.visible and page.ready_button.disabled
		and page.background.room == MenuBackground.Room.PVP
		and page.notice_label.visible
		and page.notice_label.text == "L'hôte a quitté le salon."
		and LanSession.state == LanSession.State.DISCOVERING,
		"le départ de l'hôte ferme le salon client, bloque PRÊT et conserve le décor commun")
	page.back_button.pressed.emit()
	await get_tree().process_frame
	_check(page.mode_screen.visible and not page.join_screen.visible,
		"le retour ramène au choix du mode au lieu de quitter le PVP")
	page.free()
	await get_tree().process_frame
	LanSession.reset()


## L'écran de fin remplace le retour au salon avec un simple message : il
## annonce le verdict et le score du joueur local, puis propose la revanche.
func _test_pvp_result() -> void:
	PvpMatchContext.clear()
	PvpMatchContext.begin(_pvp_config(GameState.PLAYER_ONE, []), GameState.PLAYER_ONE, 1,
		{"name": "Hôte", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
		{"name": "Client", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()})
	PvpMatchContext.record_result(GameState.PLAYER_ONE, 9, 4)
	var page: Control = (load("res://scenes/menus/PvpResult.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	_check(page.result_label.text == "VICTOIRE !"
		and page.score_label.text.contains("Hôte 9") and page.score_label.text.contains("4 Client"),
		"l'écran de fin PVP annonce la victoire et le score du joueur local")
	var pvp_winner_color := Color(str(StoneLoader.get_god("veskar")["color"]))
	_check(page.background.room == MenuBackground.Room.AFTERMATH
		and page.background.neon_primary_color == pvp_winner_color
		and page.background._winner_firework_color(0) != page.background._winner_firework_color(1)
		and page.background._winner_firework_color(1) != page.background._winner_firework_color(2),
		"la victoire PVP affiche les feux d'artifice du dieu vainqueur")
	_check(page.primary_button.visible and page.return_button.visible
		and page.quit_button.visible and page.primary_button.text == "REVANCHE"
		and page.return_button.text == "RETOUR AU SALON"
		and page.quit_button.text == "QUITTER",
		"l'écran de fin PVP distingue la revanche, le retour au salon et la sortie")
	_check(not page.score_label.text.contains("Série")
		and not page.score_label.text.contains("1  —  0")
		and not page.detail_label.text.contains("Série")
		and not page.status_label.text.contains("Objectif")
		and not page.result_label.text.contains("MANCHE"),
		"FT1 reste une partie simple : aucun score ni vocabulaire de série")
	# Une manche de série utilise le présentateur partagé avec la campagne.
	var series := SeriesStateModel.create("pvp-check", {"mode": "classic", "series": "ft2"}, 9)
	SeriesEngineModel.record_round(series, GameState.PLAYER_ONE, 9, 4)
	var series_view := PvpResultPresenterModel.series(SeriesEngineModel.public_state(series),
		{"winner": GameState.PLAYER_ONE, "score_one": 9, "score_two": 4},
		GameState.PLAYER_ONE, "Hôte", "Client")
	var card_view: Dictionary = series_view["series_view"]
	_check(series_view["title"] == "MANCHE 1 GAGNÉE"
		and str(series_view["score"]).contains("Hôte 9")
		and str(series_view["score"]).contains("4 Client")
		and str(card_view["score"]) == "Hôte 1  —  0 Client"
		and str(card_view["caption"]) == "Mode de jeu : Classique • FT2 : premier à 2",
		"PVP : une manche de série affiche le verdict, le score du round et le cadre commun")
	SeriesEngineModel.record_round(series, GameState.PLAYER_ONE, 9, 2)
	var final_view := PvpResultPresenterModel.series(SeriesEngineModel.public_state(series),
		{"winner": GameState.PLAYER_ONE, "score_one": 9, "score_two": 2},
		GameState.PLAYER_ONE, "Hôte", "Client")
	_check(final_view["title"] == "VICTOIRE !" and final_view["primary_text"] == "NOUVELLE SÉRIE"
		and str((final_view["series_view"] as Dictionary)["score"]) == "Hôte 2  —  0 Client",
		"PVP : la fin de série garde le menu victoire et le score final")
	page.queue_free()
	await get_tree().process_frame

	PvpMatchContext.begin(_pvp_config(GameState.PLAYER_ONE, [], "kharun", "veskar"),
		GameState.PLAYER_TWO, 2,
		{"name": "Client", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
		{"name": "Hôte", "god_id": "kharun", "deck": ProfileFixture.DECK.duplicate()})
	PvpMatchContext.record_result(GameState.PLAYER_ONE, 12, 6)
	var defeat: Control = (load("res://scenes/menus/PvpResult.tscn") as PackedScene).instantiate()
	add_child(defeat)
	await get_tree().process_frame
	_check(defeat.result_label.text == "DÉFAITE..." and defeat.score_label.text.contains("Client 6")
		and defeat.score_label.text.contains("12 Hôte"),
		"le même écran parle au client : son score reste à gauche et la défaite est annoncée")
	var pvp_remote_winner_color := Color(str(StoneLoader.get_god("kharun")["color"]))
	_check(defeat.background.room == MenuBackground.Room.AFTERMATH_DEFEAT
		and defeat.background.neon_primary_color == pvp_remote_winner_color
		and defeat.background.neon_secondary_color == pvp_remote_winner_color
		and defeat.background.neon_tertiary_color == pvp_remote_winner_color,
		"la défaite PVP affiche un crâne lié au dieu gagnant distant")
	defeat.queue_free()
	await get_tree().process_frame

	PvpMatchContext.begin(_pvp_config(GameState.PLAYER_ONE, [], "veskar", "kharun"),
		GameState.PLAYER_ONE, 1,
		{"name": "Hôte", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
		{"name": "Client", "god_id": "kharun", "deck": ProfileFixture.DECK.duplicate()})
	PvpMatchContext.record_result(GameState.PLAYER_NONE, 8, 8)
	var draw: Control = (load("res://scenes/menus/PvpResult.tscn") as PackedScene).instantiate()
	add_child(draw)
	await get_tree().process_frame
	_check(draw.background.room == MenuBackground.Room.AFTERMATH_DRAW
		and draw.background.neon_primary_color == Color(str(StoneLoader.get_god("veskar")["color"]))
		and draw.background.neon_secondary_color == Color(str(StoneLoader.get_god("kharun")["color"])),
		"une égalité montre deux épées croisées aux couleurs des dieux des deux joueurs")
	draw.queue_free()
	await get_tree().process_frame
	PvpMatchContext.clear()
	var ft2_rules := MatchRules.default_config()
	ft2_rules["series"] = MatchRules.SERIES_FT2
	var ft2_flow := LanSeriesCoordinator.new()
	ft2_flow._rules = ft2_rules.duplicate(true)
	ft2_flow._series = SeriesEngine.begin("result-ft2", ft2_rules, 7)
	ft2_flow._series.wins_one = 1
	ft2_flow._series.round_index = 2
	ft2_flow._phase = MatchRules.PHASE_ROUND_RESULT
	ft2_flow._local_side = GameState.PLAYER_ONE
	ft2_flow._is_host = false
	ft2_flow._loadout_one = Loadout.create("veskar", ProfileFixture.DECK.duplicate(),
		GameState.PLAYER_ONE, "result-ft2", "prep-1", 1, 0)
	PvpMatchContext.begin(_pvp_config(GameState.PLAYER_ONE, []), GameState.PLAYER_ONE, 1,
		{"name": "Hôte", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
		{"name": "Client", "god_id": "kharun", "deck": ProfileFixture.DECK.duplicate()})
	PvpMatchContext.series_public = SeriesEngine.public_state(ft2_flow._series)
	PvpMatchContext.series_flow = ft2_flow
	PvpMatchContext.record_result(GameState.PLAYER_ONE, 10, 4)
	var series_page: Control = (load("res://scenes/menus/PvpResult.tscn") as PackedScene).instantiate()
	add_child(series_page)
	await get_tree().process_frame
	_check(series_page.primary_button.text == "PARTIE SUIVANTE"
		and series_page.result_label.text == "MANCHE 1 GAGNÉE"
		and series_page.score_label.text == "Hôte 10  —  4 Client"
		and series_page.series_card.visible
		and series_page.series_card._score_label.text == "Hôte 1  —  0 Client"
		and series_page.series_card._caption_label.text
			== "Mode de jeu : Classique • FT2 : premier à 2"
		and series_page.return_button.visible and series_page.quit_button.visible
		and series_page.find_child("PvpPreparationPanel", true, false) == null,
		"FT2 non terminé montre le verdict et les deux scores, PARTIE SUIVANTE et aucune préparation")


## Configuration minimale d'un match PVP, identique à celle validée par l'hôte.
func _pvp_config(starting_player: int, blocked_cells: Array,
		god_one: String = "veskar", god_two: String = "veskar") -> Dictionary:
	return {
		"match_id": "check-pvp",
		"seed": 4242,
		"blocked_cells": blocked_cells,
		"starting_player": starting_player,
		"participants": [
			{"peer_id": 1, "side": GameState.PLAYER_ONE, "name": "Hôte",
				"god_id": god_one, "deck": ProfileFixture.DECK.duplicate()},
			{"peer_id": 2, "side": GameState.PLAYER_TWO, "name": "Client",
				"god_id": god_two, "deck": ProfileFixture.DECK.duplicate()},
		],
	}


func _test_hud_game_over() -> void:
	var hud := BattleHUD.new()
	add_child(hud)
	hud.set_names("Joueur", "Adversaire")
	hud.set_gods(StoneLoader.get_god("veskar"), StoneLoader.get_god("kharun"))
	hud.set_active_player(GameState.PLAYER_HUMAN)
	hud.set_game_over()
	_check(hud._banner.text == "Partie terminée" and hud._center.text == "VS",
		"en fin de partie, le bandeau n'annonce plus le tour d'un joueur")
	_check(hud._human_portrait.has_portrait() and hud._ai_portrait.has_portrait()
		and hud._human_god.text == "Véskar" and hud._ai_god.text == "Kharûn",
		"le HUD conserve l'image et le nom du dieu de chaque camp pendant le combat")
	hud.set_names("Joueur", "Miroir — Nérava — Le Reflet des Fièvres")
	hud.set_active_player(GameState.PLAYER_AI)
	_check(hud._ai_name.text == "Nérava" and hud._banner.text == "Tour de Nérava"
		and hud._banner.custom_minimum_size.x == UITheme.HUD_BANNER_WIDTH,
		"le HUD réduit les anciens noms composés dans la plaque et le bandeau de tour")
	hud.set_gods(GodIdentityModel.player("veskar"), GodIdentityModel.bot(""))
	_check(hud._ai_god.text == "Sans dieu" and hud._ai_portrait.has_portrait(),
		"le HUD identifie et illustre un adversaire sans dieu")
	hud.set_gods(GodIdentityModel.player(""), GodIdentityModel.bot(""))
	_check(hud._human_god.text == "Sans dieu" and hud._human_portrait.has_portrait()
		and hud._ai_god.text == "Sans dieu" and hud._ai_portrait.has_portrait(),
		"le HUD distingue la stèle du joueur du portrait de Pr.Stone")
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
	for definition in StoneLoader.get_lineages_for_god("veskar"):
		if DeckRules.lineage_index(PlayerData.get_active_deck(), StoneLoader.stone_lineage(definition["id"])) < 0:
			expected.append(definition["id"])
	var shown := _shown_collection_ids(page)
	var shown_sorted := shown.duplicate()
	shown_sorted.sort()
	expected.sort()
	_check(cards.size() == StoneLoader.get_lineages_for_god("veskar").size() and shown_sorted == expected,
		"la collection n'affiche pas les cartes déjà dans le deck")
	# Tri FAMILLE par défaut : la première carte est la moins chère de Véskar.
	_check(page._sort_mode == 0 and page.sort_button.text.begins_with("TRIER : FAMILLE")
		and str(StoneLoader.get_stone(shown[0])["god_id"]) == "veskar" and _is_family_order(shown, "veskar"),
		"par défaut, les cartes du dieu passent avant les neutres, chaque groupe par coût puis par nom")
	var de_boiteux_n3: StoneCard = cards["de_boiteux_n1"]
	var identity := de_boiteux_n3.get_instance_id()
	var without_de_boiteux: Array = PlayerData.get_active_deck()
	without_de_boiteux.erase("de_boiteux_n1")
	page._current_deck = without_de_boiteux
	page._refresh_all()
	await get_tree().process_frame
	var grid: GridContainer = page.collection_rows.get_child(0)
	shown = _shown_collection_ids(page)
	# Dé boiteux revient à la place que lui donnent son coût et son nom.
	_check(shown.has("de_boiteux_n1") and _is_family_order(shown, "veskar")
		and is_instance_valid(de_boiteux_n3) and de_boiteux_n3.get_instance_id() == identity and not de_boiteux_n3._selected,
		"une carte retirée du deck revient à sa place dans la collection, sans recréer de carte")
	page._select_sort(3)
	await get_tree().process_frame
	var by_name := _shown_collection_ids(page)
	_check(page.sort_button.text.begins_with("TRIER : NOM")
		and _names_ascending(by_name) and not _is_family_order(by_name, "veskar")
		and _collection_cards(page)["de_boiteux_n1"] == de_boiteux_n3,
		"le tri par nom déplace les cartes existantes sans les recréer")
	page._select_sort(0)
	await get_tree().process_frame
	grid = page.collection_rows.get_child(0)
	page._current_deck = without_de_boiteux + ["avortons_des_caves_n4"]
	page._refresh_all()
	await get_tree().process_frame
	var visible_wrappers: Array = []
	for wrapper in grid.get_children():
		if wrapper.visible:
			visible_wrappers.append(wrapper)
	# Avortons des caves masqué, les cartes visibles restent alignées sur trois colonnes.
	_check(not _shown_collection_ids(page).has("avortons_des_caves_n1") and visible_wrappers.size() == expected.size()
		and is_equal_approx(visible_wrappers[3].position.x, visible_wrappers[0].position.x)
		and visible_wrappers[3].position.y > visible_wrappers[0].position.y,
		"une carte ajoutée au deck disparaît et la grille referme le trou")
	var neutral: StoneCard = _collection_cards(page)["avortons_des_caves_n1"]
	page._collection_grid.rebuild("enigma", page._current_deck, page._sort_mode)
	await get_tree().process_frame
	var changed_god := _collection_cards(page)
	_check(page.collection_rows.get_child(0) == grid and changed_god.size() == 36
		and changed_god["avortons_des_caves_n1"] == neutral and not changed_god.has("de_boiteux_n1"),
		"changer de dieu conserve la grille et les vingt-quatre cartes neutres")
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
