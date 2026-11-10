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
	await _test_tutorial_match_wins()
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
	_check(not setup.is_empty() and int(setup.get("first_player", 0)) == 1,
		"flux scénario : le match scénarisé est disponible pour tuto_01")
	var node := CampaignContext.get_service().node("tuto_01")
	_check(node != null and node.forced_first_player() == int(setup.get("first_player", 0)),
		"setup tuto : l'avant-combat et le match annoncent le même premier joueur")


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
		{"row": 1, "col": 1, "stone_id": "ecorche_angle_n1"},
		{"row": 2, "col": 0, "stone_id": "ogre_droitier_n1"},
		{"row": 1, "col": 0, "stone_id": "rampant_des_fosses_n1"},
	]
	var plan: Array = setup.get("opponent_plan", [])
	_check(state.current_player == GameState.PLAYER_HUMAN
		and state.get_cell(0, 1)["owner"] == GameState.PLAYER_AI,
		"match tuto : le joueur commence face au Mordeur préparé")
	var played := true
	for index in range(human_moves.size()):
		if not await _wait_for_player(manager, GameState.PLAYER_HUMAN):
			played = false
			break
		var move: Dictionary = human_moves[index]
		if not manager.human_play(int(move["row"]), int(move["col"]), str(move["stone_id"])):
			played = false
			break
		if state.is_game_over:
			break
		if index >= plan.size() or not await _wait_for_player(manager, GameState.PLAYER_AI):
			played = false
			break
		var ai_move: Dictionary = plan[index]
		if not manager.ai_play(int(ai_move.get("row", -1)), int(ai_move.get("col", -1)),
				str(ai_move.get("stone_id", ""))):
			played = false
			break
		if state.is_game_over:
			break
	if not state.is_game_over:
		# Le dernier coup du bot ferme le plateau.
		if await _wait_for_player(manager, GameState.PLAYER_AI):
			var last: Dictionary = plan[plan.size() - 1]
			played = manager.ai_play(int(last.get("row", -1)), int(last.get("col", -1)),
				str(last.get("stone_id", ""))) and played
	_check(played, "match tuto : tous les coups guidés et scriptés sont valides")
	_check(state.is_game_over, "match tuto : le plateau se remplit et clôt la partie")
	_check(state.winner == GameState.PLAYER_HUMAN,
		"match tuto : la ligne scénarisée fait gagner le joueur")
	_check(state.score_human > state.score_ai,
		"match tuto : le score final est une victoire (%d-%d)" % [
			state.score_human, state.score_ai])
	_check(state.get_cell(0, 0)["owner"] == GameState.PLAYER_HUMAN
		and state.get_cell(0, 1)["owner"] == GameState.PLAYER_HUMAN,
		"match tuto : la Gueule de travers capture le Mordeur en (0,1)")
	_check(state.get_cell(1, 2)["owner"] == GameState.PLAYER_HUMAN,
		"match tuto : l'Écorché capture le Drap de la Muraille")
	_check(state.get_cell(2, 0)["owner"] == GameState.PLAYER_HUMAN,
		"match tuto : l'Ogre prend le flanc du Mordeur")
	manager.queue_free()
	await get_tree().process_frame
	StoryService.mark_chapter_done("first_journey")
	_check(StoryService.match_setup_for_node("tuto_01").is_empty(),
		"setup tuto : une fois le parcours terminé, le niveau retrouve son setup normal")


func _wait_for_player(manager: TurnManager, player: int) -> bool:
	var state := manager.get_state()
	for _frame in range(600):
		if state.is_game_over:
			return false
		if state.current_player == player and manager.phase == TurnManager.Phase.WAITING_INPUT:
			return true
		await get_tree().process_frame
	return false
