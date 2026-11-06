## Préparation PVP : nouvelle composition du draft, deck local actualisé,
## deck final en deux colonnes, textes courts et retour individuel au salon.
extends "res://tests/support/CombatTestSuite.gd"

const Fake := preload("res://tests/support/FakeLanTransport.gd")
const SeriesCoordinator := preload("res://scripts/network/LanSeriesCoordinator.gd")
const LobbyCoordinator := preload("res://scripts/network/LanLobbyCoordinator.gd")
const SessionLink := preload("res://scripts/network/LanSessionLink.gd")
const RulesModel := preload("res://scripts/domain/MatchRules.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")


class MockSession extends Node:
	signal message_received(from_peer: int, kind: String, payload: Dictionary)
	signal peer_joined(peer_id: int)
	signal peer_left(peer_id: int)
	signal connected_to_host()

	func send_to(_peer_id: int, _kind: String, _payload: Dictionary) -> bool:
		return true

	func broadcast(_kind: String, _payload: Dictionary) -> bool:
		return true

	func local_peer_id() -> int:
		return 1

	func is_online() -> bool:
		return true


func _profiles() -> Dictionary:
	return {
		"host": {"name": "Hote", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
		"client": {"name": "Client", "god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
	}


func _draft_profiles() -> Dictionary:
	return {
		"host": {"name": "Hote", "god_id": "veskar", "deck": []},
		"client": {"name": "Client", "god_id": "nerava", "deck": []},
	}


func _rules(mode: String, series: String) -> Dictionary:
	var rules := RulesModel.default_config()
	rules["mode"] = mode
	rules["series"] = series
	rules["power_tier"] = 4
	rules["locked"] = true
	return rules


func _pair(mode: String, series: String) -> Dictionary:
	var profiles := _draft_profiles() if mode == RulesModel.MODE_DRAFT else _profiles()
	var host_transport := Fake.new()
	host_transport.local_id = 1
	var client_transport := Fake.new()
	client_transport.local_id = 2
	host_transport.remote = client_transport
	client_transport.remote = host_transport
	var rules := _rules(mode, series)
	var host := SeriesCoordinator.new()
	var client := SeriesCoordinator.new()
	host.attach(host_transport, true, GameState.PLAYER_ONE, 2,
		profiles["host"], profiles["client"], rules, 424242)
	client.attach(client_transport, false, GameState.PLAYER_TWO, 0,
		profiles["client"], profiles["host"], rules)
	host.host_start_series()
	return {
		"host": host, "client": client, "profiles": profiles, "rules": rules,
		"host_transport": host_transport, "client_transport": client_transport,
	}


func _make_page(pair: Dictionary, parent: Node = null) -> Dictionary:
	PvpMatchContext.close_presence()
	PvpMatchContext.clear()
	var link := SessionLink.new()
	var session := MockSession.new()
	add_child(session)
	link.attach(session)
	PvpMatchContext.begin_preparation(pair["host"], link, GameState.PLAYER_ONE, 1, 2,
		pair["profiles"]["host"], pair["profiles"]["client"], pair["rules"],
		(pair["host"] as LanSeriesCoordinator).public_state())
	var routes: Array = []
	var page: Control = (load("res://scenes/menus/PvpPreparation.tscn") as PackedScene).instantiate()
	page.scene_changer = _capture_route.bind(routes)
	if parent == null:
		add_child(page)
	else:
		parent.add_child(page)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return {"page": page, "routes": routes, "link": link, "session": session}


func _capture_route(path: String, routes: Array) -> void:
	routes.append(path)


func _close_pair(pair: Dictionary) -> void:
	(pair["host"] as LanSeriesCoordinator).close()
	(pair["client"] as LanSeriesCoordinator).close()


func run() -> void:
	await _test_draft_composition_and_live_deck()
	await _test_opponent_pair_uses_viewer_step()
	await _test_responsive_draft_layout()
	await _test_final_deck_two_columns()
	await _test_character_texts_and_ready()
	await _test_presence_return_and_lobby()
	await _test_generated_loadouts_are_discarded_on_lobby_return()
	await _test_result_return_keeps_link()
	await _test_quit_closes_session()
	_cleanup_context()


func _test_draft_composition_and_live_deck() -> void:
	var pair := _pair(RulesModel.MODE_DRAFT, RulesModel.SERIES_FT1)
	var opened := _make_page(pair)
	var page: Control = opened["page"]
	await get_tree().create_timer(0.20).timeout
	_check(page.draft_panel.visible and not page.reveal_panel.visible,
		"draft : la zone de sélection est affichée")
	_check(page.find_child("OpponentTitle", true, false).text.contains("PROPOSITIONS DE L'ADVERSAIRE"),
		"draft : les propositions adverses sont identifiées en haut")
	_check(page.opponent_info.text.contains("Adversaire : 0 / 8 cartes choisies"),
		"draft : le compteur adverse réel est affiché sans révéler ses cartes")
	_check(page.find_child("DraftDeckTitle", true, false).text.contains("VOTRE DECK — 0 / 8"),
		"draft : le deck en construction est identifié avec son compte")
	_check(page.local_grid.size.x >= page.local_grid.get_parent().size.x - 1.0,
		"draft : les offres locales remplissent la largeur disponible")
	_check(page.opponent_grid.get_child_count() == 2 and page.local_grid.get_child_count() == 2,
		"draft : deux cartes adverses et deux cartes locales sont visibles")
	var opponent_read_only := true
	var local_interactive := true
	for wrapper in page.opponent_grid.get_children():
		var card: StoneCard = wrapper.get_child(0)
		opponent_read_only = opponent_read_only and card._texture != null \
			and card.mouse_filter == Control.MOUSE_FILTER_IGNORE
	for wrapper in page.local_grid.get_children():
		var card: StoneCard = wrapper.get_child(0)
		local_interactive = local_interactive and card._texture != null \
			and card.mouse_filter == Control.MOUSE_FILTER_PASS
	_check(opponent_read_only, "draft : les propositions adverses sont illustrées et non interactives")
	_check(local_interactive, "draft : les propositions locales sont illustrées et interactives")
	var host: LanSeriesCoordinator = pair["host"]
	var offers: Array = host.public_state()["draft"]["own_offers"]
	page.local_grid._cards[0].card_pressed.emit(str(offers[0]))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(page.draft_deck_grid.get_child_count() == 1
		and page.draft_deck_title.text.contains("1 / 8"),
		"draft : le deck inférieur gagne une carte après le choix accepté")
	_check(page.draft_status.text.contains("Choix enregistré"),
		"draft : un toucher affiche un texte court, sans explication de glissement")
	var forbidden := "Un glissement ne sélectionne rien."
	_check(not _labels_contain(page, forbidden),
		"draft : aucun texte explicatif de glissement n'est affiché")
	for step in range(1, DeckRules.DECK_SIZE):
		var current: Array = host.public_state()["draft"]["own_offers"]
		if (page.local_grid._cards as Array).is_empty():
			break
		page.local_grid._cards[0].card_pressed.emit(str(current[0]))
		await get_tree().process_frame
		await get_tree().process_frame
	_check(page.draft_deck_grid.get_child_count() == 8,
		"draft : les huit choix sont reflétés dans le deck en construction")
	_check(not page.draft_panel.visible and page.reveal_panel.visible,
		"draft : la fin du deck local ouvre sa présentation sans attendre l'adversaire")
	page.queue_free()
	await get_tree().process_frame
	_cleanup_context()
	(pair["client"] as LanSeriesCoordinator).close()


func _test_opponent_pair_uses_viewer_step() -> void:
	var pair := _pair(RulesModel.MODE_DRAFT, RulesModel.SERIES_FT1)
	var host: LanSeriesCoordinator = pair["host"]
	var client: LanSeriesCoordinator = pair["client"]
	# Le client est à l'étape 5, l'hôte à l'étape 0. L'écran de l'hôte doit
	# afficher la paire n° 0 du client, pas celle de son écran courant.
	for index in range(5):
		var offers: Array = client.public_state()["draft"]["own_offers"]
		client.choose_local(str(offers[0]))
	var opened := _make_page(pair)
	var page: Control = opened["page"]
	await get_tree().create_timer(0.20).timeout
	var expected: Array = host._draft.offers_for_step(GameState.PLAYER_TWO, 0)
	_check(host.public_state()["draft"]["offers_two"] == expected,
		"projection UI : l'hôte reçoit la paire adverse de son étape 0")
	_check(_grid_ids(page.opponent_grid) == expected,
		"projection UI : la grille adverse affiche la paire de l'étape locale 0")
	_check(page.opponent_info.text.contains("Adversaire : 5 / 8 cartes choisies"),
		"projection UI : le compteur 5 / 8 reste celui de la progression réelle")
	_check(_grid_ids(page.local_grid) == host._draft.offers_for_step(GameState.PLAYER_ONE, 0),
		"projection UI : les offres locales restent celles de l'étape 0")
	page.queue_free()
	await get_tree().process_frame
	_cleanup_context()
	host.close()
	client.close()


func _test_responsive_draft_layout() -> void:
	var pair := _pair(RulesModel.MODE_DRAFT, RulesModel.SERIES_FT1)
	var frame := Control.new()
	# Avec canvas_items/expand, les appareils de référence exposent environ
	# 1080x2400 (téléphone) et 1200x1920 (tablette) au layout Godot.
	frame.size = Vector2(1080, 2400)
	add_child(frame)
	var opened := _make_page(pair, frame)
	var page: Control = opened["page"]
	var host: LanSeriesCoordinator = pair["host"]
	await get_tree().create_timer(0.25).timeout
	var phone_card: int = page.local_grid._card_size
	_check(page.local_grid.size.x >= page.local_grid.get_parent().size.x - 1.0,
		"responsive téléphone : la grille locale occupe la largeur")
	# Sept choix représentent le pire cas encore visible : deux lignes presque
	# pleines dans le deck inférieur, sans basculer sur la présentation finale.
	for index in range(7):
		var offers: Array = host.public_state()["draft"]["own_offers"]
		if (page.local_grid._cards as Array).is_empty():
			break
		page.local_grid._cards[0].card_pressed.emit(str(offers[0]))
		await get_tree().process_frame
		await get_tree().process_frame
	await get_tree().create_timer(0.20).timeout
	_check(page.draft_deck_grid.columns == 4,
		"responsive téléphone : le deck en construction garde quatre colonnes lisibles")
	_check(not _grid_overflows(page.draft_deck_grid, page.draft_deck_grid.size.x)
			and not _grid_overflows(page.local_grid, page.local_grid.size.x),
		"responsive téléphone : aucun débordement horizontal")
	var phone_bar: VScrollBar = page.scroll.get_v_scroll_bar()
	_check(phone_bar.max_value <= phone_bar.page + 1.0,
		"responsive téléphone : les sept picks tiennent sans défilement")
	frame.size = Vector2(1200, 1920)
	await get_tree().create_timer(0.25).timeout
	_check(page.local_grid._card_size < phone_card,
		"responsive tablette : la hauteur réduit les choix (%d contre %d)" % [
			page.local_grid._card_size, phone_card])
	_check(not _grid_overflows(page.draft_deck_grid, page.draft_deck_grid.size.x)
			and not _grid_overflows(page.local_grid, page.local_grid.size.x),
		"responsive tablette : aucun débordement horizontal")
	var tablet_bar: VScrollBar = page.scroll.get_v_scroll_bar()
	_check(tablet_bar.max_value <= tablet_bar.page + 1.0,
		"responsive tablette : les choix et les picks tiennent entièrement sans scroll")
	page.queue_free()
	frame.queue_free()
	await get_tree().process_frame
	_cleanup_context()
	host.close()
	(pair["client"] as LanSeriesCoordinator).close()


func _grid_ids(grid: LoadoutCardGrid) -> Array:
	var ids: Array = []
	for card in grid._cards:
		ids.append(card.get_stone_id())
	return ids


func _grid_overflows(grid: LoadoutCardGrid, available_width: float) -> bool:
	var gap := float(UITheme.GAP_MEDIUM) * float(maxi(0, grid.columns - 1))
	return float(grid._card_size) * float(grid.columns) + gap > available_width + 1.0


func _test_final_deck_two_columns() -> void:
	var pair := _pair(RulesModel.MODE_RANDOM, RulesModel.SERIES_FT1)
	var frame := Control.new()
	frame.size = Vector2(1200, 1920)
	add_child(frame)
	var opened := _make_page(pair, frame)
	var page: Control = opened["page"]
	await get_tree().create_timer(0.30).timeout
	_check(page.deck_grid.get_child_count() == DeckRules.DECK_SIZE
		and page.deck_grid.columns == 2,
		"deck final : huit cartes sont disposées sur deux colonnes")
	var rows := ceili(float(page.deck_grid.get_child_count()) / float(page.deck_grid.columns))
	_check(rows == 4, "deck final : les huit cartes forment quatre lignes logiques")
	var tablet_card: int = page.deck_grid._card_size
	var tablet_bar: VScrollBar = page.scroll.get_v_scroll_bar()
	_check(tablet_bar.max_value <= tablet_bar.page + 1.0,
		"deck final tablette : les quatre lignes et le dieu tiennent sans scroll")
	var widest := 0.0
	for wrapper in page.deck_grid.get_children():
		var card: StoneCard = wrapper.get_child(0)
		widest = maxf(widest, card.size.x)
	_check(page.scroll.size.x <= 0.0 or widest * 2.0 <= page.scroll.size.x + 1.0,
		"deck final : deux cartes tiennent dans la largeur, sans débordement horizontal")
	frame.size = Vector2(1080, 2400)
	await get_tree().create_timer(0.30).timeout
	_check(page.deck_grid._card_size >= tablet_card,
		"deck final téléphone : la hauteur supplémentaire conserve de grandes cartes")
	var phone_bar: VScrollBar = page.scroll.get_v_scroll_bar()
	_check(phone_bar.max_value <= phone_bar.page + 1.0,
		"deck final téléphone : les huit cartes tiennent sans scroll")
	page.queue_free()
	frame.queue_free()
	await get_tree().process_frame
	_cleanup_context()
	_close_pair(pair)


func _test_character_texts_and_ready() -> void:
	var pair := _pair(RulesModel.MODE_RANDOM, RulesModel.SERIES_FT1)
	var opened := _make_page(pair)
	var page: Control = opened["page"]
	await get_tree().create_timer(0.15).timeout
	_check(not _labels_contain(page, "Votre deck est affiché seul. Aucun deck adverse n'est exposé."),
		"textes : l'ancienne explication de confidentialité est absente")
	_check(not _labels_contain(page, "Confirmez votre deck."),
		"textes : le joueur ne confirme pas son deck, il se met PRÊT")
	_check(not _labels_contain(page, "Un glissement ne sélectionne rien."),
		"textes : l'explication de glissement est absente")
	page._on_confirm()
	await get_tree().process_frame
	_check(page.confirm_button.disabled and page.confirm_button.text == "PRÊT ✓",
		"PRÊT : le bouton se désactive après activation et affiche PRÊT ✓")
	_check(page.opponent_ready_label.text.contains("pas encore prêt"),
		"PRÊT : l'attente est formulée sans demander de confirmation de deck")
	page.queue_free()
	await get_tree().process_frame
	_cleanup_context()
	_close_pair(pair)


func _labels_contain(page: Control, fragment: String) -> bool:
	for label in page.find_children("*", "Label"):
		if (label as Label).text.contains(fragment):
			return true
	return false


func _cleanup_context() -> void:
	PvpMatchContext.close_presence()
	PvpMatchContext.clear()
	LanSession.reset()


## Le retour individuel est couvert séparément du rendu : la présence ne porte
## aucune navigation distante et le salon se déverrouille seulement aux retours.
func _test_presence_return_and_lobby() -> void:
	var host_transport := Fake.new()
	host_transport.local_id = 1
	var client_transport := Fake.new()
	client_transport.local_id = 2
	host_transport.remote = client_transport
	client_transport.remote = host_transport
	var host_presence := LanPvpPresence.new()
	var client_presence := LanPvpPresence.new()
	host_presence.attach(host_transport, 2)
	client_presence.attach(client_transport, 1)
	host_presence.set_local(LanPvpPresence.RESULT)
	client_presence.set_local(LanPvpPresence.RESULT)
	var lobby := LobbyCoordinator.new()
	lobby.attach(host_transport, true, 2, host_presence)
	lobby.resume(_profiles()["host"], _profiles()["client"], _rules(RulesModel.MODE_RANDOM,
		RulesModel.SERIES_FT2))
	_check(lobby.state()["remote_in_game"] and not bool(lobby.state()["can_ready"]),
		"retour : EN PARTIE désactive PRÊT pour l'adversaire encore en jeu")
	_check(not bool(lobby.set_rule("mode", RulesModel.MODE_MIRROR).get("ok", true)),
		"retour : les règles restent verrouillées tant que l'adversaire est EN PARTIE")
	host_presence.set_local(LanPvpPresence.LOBBY)
	_check(client_presence.remote_presence() == LanPvpPresence.LOBBY,
		"retour : seul le joueur qui agit annonce LOBBY")
	_check(host_transport.is_online() and client_transport.is_online(),
		"retour : la connexion ENet reste ouverte")
	client_presence.set_local(LanPvpPresence.LOBBY)
	await get_tree().process_frame
	_check(not lobby.state()["remote_in_game"] and bool(lobby.state()["can_ready"]),
		"retour : le second joueur revenu rouvre le salon")
	_check(not bool(lobby.state()["rules"]["locked"])
		and not bool(lobby.state()["host"]["ready"])
		and not bool(lobby.state()["client"]["ready"]),
		"retour : les deux joueurs sont PAS PRÊT et les règles sont déverrouillées")
	_check(lobby.series_coordinator() == null,
		"retour : l'ancienne série est nettoyée")
	lobby.close()
	client_presence.close()


func _test_result_return_keeps_link() -> void:
	_cleanup_context()
	PvpMatchContext.begin(_match_config(), GameState.PLAYER_ONE, 1,
		PvpMatchContext.local_profile(), PvpMatchContext.remote_profile())
	PvpMatchContext.local_profile()
	var session := MockSession.new()
	add_child(session)
	var link := SessionLink.new()
	link.attach(session)
	var page: Control = (load("res://scenes/menus/PvpResult.tscn") as PackedScene).instantiate()
	page._link = link
	var routes: Array = []
	page.scene_changer = _capture_route.bind(routes)
	add_child(page)
	await get_tree().process_frame
	page._press_return_lobby()
	_check(routes == [Routes.PVP_LOBBY], "résultat : RETOUR AU SALON navigue localement")
	_check(link.is_attached() and PvpMatchContext.lobby_resume.get("link") == link,
		"résultat : le retour conserve le lien ENet")
	_check(PvpMatchContext.series_flow == null and PvpMatchContext.series_link == null,
		"résultat : le retour abandonne la série sans fermer la connexion")
	page.queue_free()
	await get_tree().process_frame
	PvpMatchContext.close_presence()
	PvpMatchContext.clear()
	link.detach()
	session.queue_free()


## Les participants de la manche portent volontairement un dieu et un deck
## différents. Aucun des trois modes générés ne doit les réinjecter dans le
## salon lorsqu'une nouvelle série Classique est ensuite choisie.
func _test_generated_loadouts_are_discarded_on_lobby_return() -> void:
	for mode in [RulesModel.MODE_RANDOM, RulesModel.MODE_MIRROR, RulesModel.MODE_DRAFT]:
		_cleanup_context()
		var original := _profiles()
		var session := MockSession.new()
		add_child(session)
		var link := SessionLink.new()
		link.attach(session)
		var rules := _rules(mode, RulesModel.SERIES_FT1)
		PvpMatchContext.begin_preparation(null, link, GameState.PLAYER_ONE, 1, 2,
			original["host"], original["client"], rules, {})
		var generated_config := _match_config()
		generated_config["participants"] = [
			{"peer_id": 1, "side": GameState.PLAYER_ONE, "name": "Hote",
				"god_id": "nerava", "deck": ["temporaire-local"]},
			{"peer_id": 2, "side": GameState.PLAYER_TWO, "name": "Client",
				"god_id": "sylkha", "deck": ["temporaire-distant"]},
		]
		# Sélection garde les dieux du profil mais remplace tout de même les decks.
		if mode == RulesModel.MODE_DRAFT:
			generated_config["participants"][0]["god_id"] = original["host"]["god_id"]
			generated_config["participants"][1]["god_id"] = original["client"]["god_id"]
		PvpMatchContext.begin(generated_config, GameState.PLAYER_ONE, 1,
			original["host"], original["client"], true, rules)
		_check(PvpMatchContext.local_deck == ["temporaire-local"],
			"%s : le combat utilise bien le deck temporaire" % RulesModel.mode_label(mode))
		var page: Control = (load("res://scenes/menus/PvpResult.tscn") as PackedScene).instantiate()
		page._link = link
		var routes: Array = []
		page.scene_changer = _capture_route.bind(routes)
		add_child(page)
		await get_tree().process_frame
		page._press_return_lobby()
		var resume: Dictionary = PvpMatchContext.lobby_resume
		_check(resume.get("local", {}) == original["host"]
			and resume.get("remote", {}) == original["client"],
			"%s : le retour restaure les deux profils originaux du salon" % [
				RulesModel.mode_label(mode)])
		_check((resume.get("local", {}) as Dictionary).get("deck", [])
			== ProfileFixture.DECK,
			"%s : le deck temporaire est détruit avant une partie Classique" % [
				RulesModel.mode_label(mode)])
		var lobby_transport := Fake.new()
		lobby_transport.local_id = 1
		var resumed_lobby := LobbyCoordinator.new()
		resumed_lobby.attach(lobby_transport, true, 2)
		resumed_lobby.resume(resume["local"], resume["remote"], resume["rules"], 2)
		var classic_change := resumed_lobby.set_rule("mode", RulesModel.MODE_CLASSIC)
		_check(bool(classic_change.get("ok", false))
			and resumed_lobby.host_summary()["god_id"] == original["host"]["god_id"]
			and resumed_lobby.host_summary()["deck"] == original["host"]["deck"]
			and resumed_lobby.client_summary()["god_id"] == original["client"]["god_id"]
			and resumed_lobby.client_summary()["deck"] == original["client"]["deck"],
			"%s : une nouvelle partie Classique lit uniquement les profils d'origine" % [
				RulesModel.mode_label(mode)])
		resumed_lobby.close()
		page.queue_free()
		await get_tree().process_frame
		PvpMatchContext.clear()
		link.detach()
		session.queue_free()


func _test_quit_closes_session() -> void:
	_cleanup_context()
	PvpMatchContext.begin(_match_config(), GameState.PLAYER_ONE, 1,
		{}, {})
	var session := MockSession.new()
	add_child(session)
	var link := SessionLink.new()
	link.attach(session)
	var page: Control = (load("res://scenes/menus/PvpResult.tscn") as PackedScene).instantiate()
	page._link = link
	var routes: Array = []
	page.scene_changer = _capture_route.bind(routes)
	add_child(page)
	await get_tree().process_frame
	page._quit()
	_check(routes == [Routes.PVP_LOBBY] and not link.is_attached()
		and PvpMatchContext.presence == null,
		"QUITTER ferme le lien et nettoie la présence")
	page.queue_free()
	await get_tree().process_frame
	LanSession.reset()
	session.queue_free()


func _match_config() -> Dictionary:
	return {
		"match_id": "result-match",
		"seed": 4242,
		"blocked_cells": [],
		"starting_player": GameState.PLAYER_ONE,
		"participants": [
			{"peer_id": 1, "side": GameState.PLAYER_ONE, "name": "Hote",
				"god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
			{"peer_id": 2, "side": GameState.PLAYER_TWO, "name": "Client",
				"god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
		],
	}
