## Intégration du service et du moteur : le chapitre n'a plus d'intro de niveau,
## et la ligne guidée du match doit réellement gagner sur le vrai TurnManager.
extends "res://tests/support/CombatTestSuite.gd"

const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const StoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const ServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
const PATH := "user://story_flow_checks.json"


func run() -> void:
	_cleanup()
	var graph: CampaignGraph = GraphModel.build(_content_definition())
	var progress := ProgressModel.new()
	var service := ServiceModel.new(graph, progress, StoreModel.new(PATH), [])
	CampaignContext.set_service_for_tests(service)
	StoryService._memory_states.clear()
	StoryService.stop_tutorial()
	StoryService._tutorial.start(StoryService.chapter("first_journey"),
		"res://scenes/game/Board.tscn")
	_test_journey_content()
	_test_theme_god_identity(service)
	await _test_tutorial_match_wins()
	_test_node_chapters(service)
	StoryService.stop_tutorial()
	StoryService._memory_states.clear()
	CampaignContext.reset_for_tests()
	_cleanup()


func _cleanup() -> void:
	for path in [PATH, PATH + ".tmp", PATH + ".unreadable"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _content_definition() -> Dictionary:
	var file := FileAccess.open("res://data/campaign/campaign_v2.json", FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _test_journey_content() -> void:
	_check(StoryService.play_level_start("tuto_01") == null,
		"flux scénario : tuto_01 ne joue plus d'intro générique au lancement")
	var chapter := StoryService.chapter("first_journey")
	_check(not chapter.is_empty()
		and str(chapter.get("entry_scene", "")) == "res://scenes/menus/MainMenu.tscn",
		"flux scénario : le parcours est ancré sur l'accueil")
	var setup := StoryService.match_setup_for_node("tuto_01")
	_check(not setup.is_empty() and int(setup.get("first_player", 0)) == 1
		and (setup.get("initial_stones", []) as Array).is_empty(),
		"flux scénario : le match scénarisé part d'un plateau vide")
	var node := CampaignContext.get_service().node("tuto_01")
	_check(node != null and node.forced_first_player() == int(setup.get("first_player", 0)),
		"setup tuto : l'avant-combat et le match annoncent le même premier joueur")


## Le dieu présenté par un reflet doit être une identité de dialogue réelle :
## sans cela, la politique `theme_god` n'afficherait ni nom ni portrait.
func _test_theme_god_identity(service: CampaignService) -> void:
	var saved_node := BattleContext.campaign_node_id
	var saved_service := BattleContext.campaign_service
	BattleContext.campaign_node_id = "init_veskar"
	BattleContext.campaign_service = service
	var identity := StoryService._theme_god_character()
	_check(str(identity.get("name", "")) == "Véskar"
		and str(identity.get("side", "")) == "right"
		and str(identity.get("asset", "")) != "",
		"reflets : le dieu du nœud devient le locuteur de sa présentation")
	BattleContext.campaign_node_id = saved_node
	BattleContext.campaign_service = saved_service


## Rejoue la ligne du chapitre sur le moteur réel. Le bot suit son plan ; la
## partie doit se terminer sur une victoire humaine, sans intervention du UI.
func _test_tutorial_match_wins() -> void:
	var setup := StoryService.match_setup_for_node("tuto_01")
	if setup.is_empty():
		_check(false, "match tuto : le setup est disponible")
		return
	var manager := TurnManager.new()
	add_child(manager)
	manager.start_game(
		StoneLoader.build_hand(setup.get("player_deck", [])),
		StoneLoader.build_hand(setup.get("opponent_deck", [])),
		setup.get("blocked_cells", []), "tuto_01",
		int(setup.get("first_player", 1)), "", "", 0,
		int(setup.get("board_size", 3)), setup.get("initial_stones", []))
	var state: GameState = manager.get_state()
	var human_moves := [
		{"row": 0, "col": 0, "stone_id": "gueule_de_travers_n1"},
		{"row": 2, "col": 1, "stone_id": "ecorche_angle_n1"},
		{"row": 1, "col": 1, "stone_id": "ogre_droitier_n1"},
		{"row": 0, "col": 1, "stone_id": "rampant_des_fosses_n1"},
		{"row": 2, "col": 0, "stone_id": "le_drape_du_seuil_n1"},
	]
	var plan: Array = setup.get("opponent_plan", [])
	_check(state.current_player == GameState.PLAYER_HUMAN
		and state.empty_playable_cells == 9
		and state.get_cell(0, 1)["owner"] == GameState.PLAYER_NONE,
		"match tuto : le joueur commence sur un plateau entièrement vide")
	var played := true
	for index in range(human_moves.size()):
		if not await _wait_for_player(manager, GameState.PLAYER_HUMAN):
			played = false
			break
		var move: Dictionary = human_moves[index]
		if not manager.human_play(int(move["row"]), int(move["col"]), str(move["stone_id"])):
			played = false
			break
		if index == 0:
			_check(state.get_cell(0, 0)["owner"] == GameState.PLAYER_HUMAN
				and state.get_cell(0, 1)["owner"] == GameState.PLAYER_NONE,
				"match tuto : la première pose n'est encore qu'une pose")
		if state.is_game_over:
			break
		if index < plan.size():
			if not await _wait_for_player(manager, GameState.PLAYER_AI):
				played = false
				break
			var ai_move: Dictionary = plan[index]
			if not manager.ai_play(int(ai_move.get("row", -1)), int(ai_move.get("col", -1)),
					str(ai_move.get("stone_id", ""))):
				played = false
				break
	_check(played, "match tuto : tous les coups guidés et scriptés sont valides")
	## La dernière pose publie sa présentation avant de clore la partie :
	## laisser le moteur finir son tour avant de lire le verdict.
	for _frame in range(900):
		if state.is_game_over:
			break
		await get_tree().process_frame
	_check(state.is_game_over, "match tuto : le plateau se remplit et clôt la partie")
	_check(state.winner == GameState.PLAYER_HUMAN,
		"match tuto : la ligne scénarisée fait gagner le joueur")
	_check(state.score_human == 6 and state.score_ai == 3,
		"match tuto : le score final est une victoire nette (%d-%d)" % [
			state.score_human, state.score_ai])
	_check(state.get_cell(2, 2)["owner"] == GameState.PLAYER_HUMAN,
		"match tuto : l'Écorché capture le Drap posé dans le coin opposé")
	_check(state.get_cell(0, 0)["owner"] == GameState.PLAYER_AI,
		"match tuto : le Mordeur prend réellement la première carte du joueur")
	_check(state.get_cell(1, 1)["owner"] == GameState.PLAYER_HUMAN
		and state.get_cell(1, 0)["owner"] == GameState.PLAYER_HUMAN,
		"match tuto : l'Ogre reprend le Mordeur de flanc")
	manager.queue_free()
	await get_tree().process_frame
	StoryService.mark_chapter_done("first_journey")
	_check(StoryService.match_setup_for_node("tuto_01").is_empty(),
		"setup tuto : une fois le parcours terminé, le niveau retrouve son setup normal")


## Les chapitres de niveau sont ouverts avant la création du driver : c'est
## eux qui fournissent la géométrie du plateau et ses cases bloquées.
func _test_node_chapters(service: CampaignService) -> void:
	var saved_node := BattleContext.campaign_node_id
	var saved_service := BattleContext.campaign_service
	var saved_screen := StoryService._screen_path
	var saved_auto := StoryService.auto_start_tutorials
	StoryService.auto_start_tutorials = true
	## Rester sur l'écran précédent : le chapitre attend le plateau sans
	## afficher de dialogue pendant ce test de branchement.
	StoryService._screen_path = "res://scenes/menus/PreBattle.tscn"
	## Le parcours précédent est encore ouvert : un seul chapitre à la fois.
	StoryService.stop_tutorial()
	BattleContext.campaign_service = service
	BattleContext.campaign_node_id = "tuto_02"
	StoryService.start_tutorial_for_node("tuto_02")
	_check(StoryService._tutorial.is_running()
		and str(StoryService._tutorial._chapter.get("id", "")) == "tuto_02",
		"chapitres : le niveau 2 ouvre son explication avant le match")
	StoryService.stop_tutorial()
	BattleContext.campaign_node_id = "tuto_03"
	StoryService.start_tutorial_for_node("tuto_03")
	var setup := StoryService.match_setup_for_node("tuto_03")
	_check(StoryService._tutorial.is_running()
		and int(setup.get("board_size", 0)) == 4
		and (setup.get("blocked_cells", []) as Array).size() == 2,
		"chapitres : le niveau 3 fournit un plateau de 4 avec deux cases bloquées")
	StoryService.stop_tutorial()
	StoryService.auto_start_tutorials = saved_auto
	StoryService._screen_path = saved_screen
	BattleContext.campaign_node_id = saved_node
	BattleContext.campaign_service = saved_service


func _wait_for_player(manager: TurnManager, player: int) -> bool:
	var state := manager.get_state()
	for _frame in range(600):
		if state.is_game_over:
			return false
		if state.current_player == player and manager.phase == TurnManager.Phase.WAITING_INPUT:
			return true
		await get_tree().process_frame
	return false
