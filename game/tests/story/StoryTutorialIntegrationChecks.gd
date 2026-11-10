## Intégration du parcours Pr. Stone : les vrais contrôles de l'accueil, du
## cabinet, de la carte et du plateau exposent les ancres attendues ; le match
## guidé joue le premier coup du plan ; l'échange de carte passe par le vrai
## tiroir et le vrai panneau de remplacement.
extends "res://tests/support/CombatTestSuite.gd"

const ContentModel := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const StoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const ServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const InventoryModel := preload("res://scripts/domain/economy/PlayerInventory.gd")
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")
const PATH := "user://story_tutorial_integration_checks.json"
const SWAP_PATH := "user://story_swap_checks.json"
const SWAP_DECK := [
	"gueule_de_travers_n1", "ecorche_angle_n1", "ogre_droitier_n1",
	"rampant_des_fosses_n1", "le_drape_du_seuil_n1", "avortons_des_caves_n1",
	"mordeur_des_combles_n1", "mache_mur_n1",
]
const SWAP_INCOMING := "le_sac_a_murmures_n1"


func run() -> void:
	_cleanup()
	var content := ContentModel.read()
	if not bool(content.get("ok", false)):
		_check(false, "intégration tuto : la campagne est valide")
		return
	var graph: CampaignGraph = GraphModel.build(content["definition"])
	var service := ServiceModel.new(graph, ProgressModel.new(),
		StoreModel.new(PATH), [])
	CampaignContext.set_service_for_tests(service)
	StoryService.stop_tutorial()
	StoryService._memory_states.clear()
	StoryService.auto_start_tutorials = false
	await _test_screen_anchors()
	await _test_journey_crosses_screens()
	StoryService.auto_start_tutorials = true
	await _test_board_guidance(service)
	StoryService.auto_start_tutorials = false
	await _test_collection_swap()
	await _test_replay_is_gone()
	StoryService.stop_tutorial()
	StoryService.auto_start_tutorials = false
	StoryService._memory_states.clear()
	CampaignContext.reset_for_tests()
	_cleanup()


func _cleanup() -> void:
	for path in [PATH, PATH + ".tmp", PATH + ".unreadable",
			SWAP_PATH, SWAP_PATH + ".tmp", SWAP_PATH + ".unreadable",
			SWAP_PATH + PlayerData.CATALOGUE_BACKUP_SUFFIX,
			SWAP_PATH + PlayerData.CATALOGUE_BACKUP_SUFFIX + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _wait_until(predicate: Callable, frames: int = 240) -> bool:
	for _frame in range(frames):
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())


func _close_dialogue_lines(count: int = 8) -> void:
	for _line in range(count):
		if not StoryLayer._dialogue.visible:
			return
		StoryLayer._dialogue._typing = false
		StoryLayer._dialogue._advance()
		await get_tree().process_frame


func _test_screen_anchors() -> void:
	var menu: Control = (load("res://scenes/menus/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	_check(StoryService.get_anchor("nav.deck") != null
		and StoryService.get_anchor("nav.home") != null
		and StoryService.get_anchor("menu.campaign") != null,
		"accueil : les onglets DECKS/ACCUEIL et la Campagne sont des ancres réelles")
	menu.queue_free()
	await get_tree().process_frame

	var map: Control = (load("res://scenes/campaign/CampaignMap.tscn") as PackedScene).instantiate()
	add_child(map)
	var node_ready := await _wait_until(func() -> bool:
		return StoryService.get_anchor("map.node.tuto_01") != null, 180)
	_check(node_ready, "carte : Le Seuil est une ancre réelle")
	var opened := [false]
	var handler := func(name: String, _payload: Dictionary) -> void:
		if name == "campaign_node_opened":
			opened[0] = true
	StoryService.event_received.connect(handler)
	if node_ready:
		map._on_node_activated("tuto_01")
	await get_tree().process_frame
	_check(opened[0] and StoryService.get_anchor("map.launch") != null,
		"carte : ouvrir Le Seuil publie l'événement et expose AFFRONTER")
	StoryService.event_received.disconnect(handler)
	map.queue_free()
	await get_tree().process_frame


func _test_journey_crosses_screens() -> void:
	StoryService.auto_start_tutorials = true
	var menu: Control = (load("res://scenes/menus/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	var started := await _wait_until(func() -> bool:
		return StoryLayer._dialogue.visible and StoryLayer._dialogue._lines.size() >= 3, 180)
	_check(started, "parcours : Pr. Stone ouvre le parcours dès l'accueil")
	if not started:
		StoryService.stop_tutorial()
		menu.queue_free()
		StoryService.auto_start_tutorials = false
		return
	_check(str(StoryLayer._dialogue._lines[0].get("text", "")).contains("Refuge"),
		"parcours : la première phrase présente le Refuge")
	await _close_dialogue_lines(6)
	var deck_ready := await _wait_until(func() -> bool:
		return StoryLayer._spotlight.visible and StoryService._tutorial._wait_for == "screen_opened", 180)
	_check(deck_ready and StoryLayer._spotlight._target == StoryService.get_anchor("nav.deck"),
		"parcours : DECKS est mis en surbrillance après l'accueil")
	menu.queue_free()
	await get_tree().process_frame

	var fixture := ProfileFixture.new()
	var collection: Control = (load("res://scenes/menus/CollectionScreen.tscn") as PackedScene).instantiate()
	add_child(collection)
	var deck_intro := await _wait_until(func() -> bool:
		return StoryLayer._dialogue.visible and StoryService._tutorial._current_step.get("id", "") == "deck_intro", 240)
	_check(deck_intro, "parcours : ouvrir DECKS reprend le chapitre sur le cabinet")
	if deck_intro:
		await _close_dialogue_lines(6)
		var deck_spot := await _wait_until(func() -> bool:
			return StoryLayer._spotlight.visible and StoryService._tutorial._wait_for == "tutorial_advance" and StoryLayer._spotlight._target == StoryService.get_anchor("collection.deck_panel"), 180)
		_check(deck_spot and StoryLayer._spotlight._advance_button.visible,
			"parcours : le deck est présenté avec SUIVANT")
		StoryLayer._spotlight._advance_button.pressed.emit()
		var home_spot := await _wait_until(func() -> bool:
			return StoryLayer._spotlight.visible and StoryLayer._spotlight._target == StoryService.get_anchor("nav.home"), 180)
		_check(home_spot and StoryLayer._spotlight._prompt.text.contains("ACCUEIL"),
			"parcours : le retour à l'accueil est guidé")
	collection.queue_free()
	fixture.restore()
	StoryService.stop_tutorial()
	StoryService.auto_start_tutorials = false
	await get_tree().process_frame


func _test_board_guidance(service: CampaignService) -> void:
	var saved_node := BattleContext.campaign_node_id
	var saved_npc := BattleContext.selected_npc_id
	var saved_opponent := BattleContext.selected_opponent
	var saved_first := BattleContext.forced_first_player
	var saved_service := BattleContext.campaign_service
	BattleContext.campaign_node_id = "tuto_01"
	BattleContext.selected_npc_id = "disciple_muraille"
	BattleContext.selected_opponent = {}
	BattleContext.forced_first_player = GameState.PLAYER_AI
	BattleContext.campaign_service = service
	var chapter := StoryService.chapter("first_journey")
	var first_card_index := -1
	var steps: Array = chapter.get("steps", [])
	for index in range(steps.size()):
		if str(steps[index].get("id", "")) == "first_card":
			first_card_index = index
			break
	if first_card_index < 0:
		_check(false, "guidage : l'étape de la première carte existe")
		return
	StoryService._tutorial.start(chapter, "res://scenes/game/Board.tscn")
	StoryService._tutorial._step_index = first_card_index
	StoryService._tutorial._waiting = false
	StoryService._tutorial._current_step = {}
	StoryService._tutorial._wait_for = ""
	var board: Control = (load("res://scenes/game/Board.tscn") as PackedScene).instantiate()
	add_child(board)
	var card_step := await _wait_until(func() -> bool:
		return StoryLayer._dialogue.visible and StoryService._tutorial._current_step.get("id", "") == "first_card", 240)
	var card_ready := false
	if card_step:
		await _close_dialogue_lines(6)
		card_ready = await _wait_until(func() -> bool:
			return StoryLayer._spotlight.visible and StoryService._tutorial._wait_for == "card_selected", 120)
	_check(card_ready and StoryLayer._spotlight._target
			== StoryService.get_anchor("board.hand.card.gueule_de_travers_n1"),
		"guidage : la Gueule de travers est la carte mise en surbrillance")
	var state: GameState = board.turn_manager.get_state()
	_check(state.current_player == GameState.PLAYER_HUMAN
		and state.empty_playable_cells == 9
		and state.get_cell(0, 1)["owner"] == GameState.PLAYER_NONE,
		"guidage : le plateau du tutoriel démarre entièrement vide")
	if card_ready:
		board._on_card_selected("gueule_de_travers_n1")
		var place_step := await _wait_until(func() -> bool:
			return StoryLayer._dialogue.visible and StoryService._tutorial._current_step.get("id", "") == "place_first", 180)
		if place_step:
			await _close_dialogue_lines(4)
		var placement_ready := await _wait_until(func() -> bool:
			return StoryLayer._spotlight.visible and StoryService._tutorial._wait_for == "stone_placed", 180)
		var cell: Control = StoryService.get_anchor("board.cell.0.0")
		_check(placement_ready and StoryLayer._spotlight._target == cell
			and cell != null and cell.mouse_filter == Control.MOUSE_FILTER_STOP,
			"guidage : la case (0,0) est la seule cible de pose")
		if placement_ready:
			board._on_cell_pressed(0, 0)
	var placed := await _wait_until(func() -> bool:
		return state.get_cell(0, 0)["owner"] == GameState.PLAYER_HUMAN, 120)
	_check(placed and state.get_cell(0, 1)["owner"] == GameState.PLAYER_NONE,
		"guidage : la première pose ne capture encore rien")
	var bot_played := await _wait_until(func() -> bool:
		return state.get_cell(2, 2)["owner"] == GameState.PLAYER_AI and str(state.get_cell(2, 2)["stone_id"]) == "le_drape_du_seuil_n1", 420)
	_check(bot_played, "guidage : le bot pose le Drap dans le coin opposé, sans hasard")
	StoryService.stop_tutorial()
	board.queue_free()
	await get_tree().process_frame
	BattleContext.campaign_node_id = saved_node
	BattleContext.selected_npc_id = saved_npc
	BattleContext.selected_opponent = saved_opponent
	BattleContext.forced_first_player = saved_first
	BattleContext.campaign_service = saved_service


func _test_collection_swap() -> void:
	var deck: Array = SWAP_DECK.duplicate()
	if not DeckRules.is_deck_valid(deck, ""):
		_check(false, "échange : le deck de test doit être valide")
		return
	var previous_profile := PlayerData.get_profile()
	var previous_path := PlayerData._save_path
	PlayerData._save_path = SWAP_PATH
	var profile := Codec.starter_profile()
	profile["player_god_id"] = ""
	profile["decks_by_god"]["neutral"][0] = deck.duplicate()
	profile["selected_deck_by_god"]["neutral"] = 0
	var inventory := InventoryModel.from_dict(profile.get("inventory", {}))
	for stone_id in deck + [SWAP_INCOMING]:
		inventory.add_copies(StoneLoader.stone_lineage(str(stone_id)), 1)
	profile["inventory"] = inventory.to_dict()
	PlayerData._apply_profile(profile)
	_check(PlayerData.owns_stone(SWAP_INCOMING)
		and PlayerData.get_active_deck().size() == DeckRules.DECK_SIZE,
		"échange : le profil de test possède la nouvelle carte et un deck plein")
	var collection: Control = (load("res://scenes/menus/CollectionScreen.tscn") as PackedScene).instantiate()
	add_child(collection)
	var anchor_ready := await _wait_until(func() -> bool:
		return StoryService.get_anchor("collection.card.%s" % SWAP_INCOMING) != null, 180)
	_check(anchor_ready, "échange : la nouvelle carte est une ancre réelle")
	if anchor_ready:
		var wrapper := StoryService.get_anchor("collection.card.%s" % SWAP_INCOMING) as VBoxContainer
		collection._open_card_actions(SWAP_INCOMING, wrapper, CardActionDrawer.Source.COLLECTION)
		var action_ready := await _wait_until(func() -> bool:
			return StoryService.get_anchor("collection.action.primary") != null, 60)
		_check(action_ready, "échange : UTILISER est exposé dans le tiroir")
		collection._request_use(SWAP_INCOMING)
		var target_ready := await _wait_until(func() -> bool:
			return StoryService.get_anchor("collection.replace.first") != null and collection.replacement_panel.visible, 60)
		_check(target_ready, "échange : une carte du deck à remplacer est mise en surbrillance")
		if target_ready:
			var target := StoryService.get_anchor("collection.replace.first")
			var old_card := target.get_child(0) as StoneCard
			var old_id := old_card.get_stone_id()
			collection._on_replacement_requested(old_id)
			var current := PlayerData.get_active_deck()
			_check(current.has(SWAP_INCOMING) and not current.has(old_id),
				"échange : la nouvelle carte remplace l'ancienne dans le deck")
			_check(not collection.replacement_panel.visible,
				"échange : le panneau se referme après le remplacement")
	collection.queue_free()
	await get_tree().process_frame
	PlayerData._apply_profile(previous_profile)
	PlayerData._save_path = previous_path
	_cleanup()


func _test_replay_is_gone() -> void:
	var dialog: CampaignLevelDialog = (load("res://scenes/campaign/CampaignLevelDialog.tscn") as PackedScene).instantiate()
	add_child(dialog)
	dialog.open({"id": "tuto_01", "name": "Le Seuil"}, 2)
	_check(not dialog.replay_button.visible,
		"replay : l'ancienne intro supprimée ne propose plus REVOIR")
	dialog.queue_free()
	await get_tree().process_frame
