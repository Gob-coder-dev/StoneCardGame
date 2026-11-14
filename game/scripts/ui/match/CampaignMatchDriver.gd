## CampaignMatchDriver.gd
## Driver de la campagne : configuration du bot et exécution de son tour.
## Le moteur, les règles et l'IA restent exactement ceux d'avant. Un chapitre
## guidé peut fournir un setup de match (mains, pierres initiales, premier
## joueur et plan du bot) ; ce setup reste une donnée du scénario, pas du niveau.
class_name CampaignMatchDriver
extends MatchDriver

const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")

var _ai_runner: AITurnRunner = null
var _npc_data: Dictionary = {}


func start() -> bool:
	if BattleContext.selected_npc_id == "":
		return false
	_npc_data = BattleContext.current_opponent()
	if str(_npc_data.get("id", "")) != BattleContext.selected_npc_id:
		_npc_data = StoneLoader.get_npc(BattleContext.selected_npc_id)
	if _npc_data.is_empty():
		push_error("CampaignMatchDriver: adversaire '%s' introuvable." % BattleContext.selected_npc_id)
		return false
	var story := StoryService.match_setup_for_node(BattleContext.campaign_node_id)
	var encounter_setup: Dictionary = _npc_data.get("match_setup", {})
	var board_size := clampi(int(story.get("board_size", encounter_setup.get("board_size",
		GameState.DEFAULT_BOARD_SIZE))), GameState.MIN_BOARD_SIZE, GameState.MAX_BOARD_SIZE)
	var player_god_id := BattleContext.effective_player_god_id()
	var opponent_god_id := BattleContext.effective_opponent_god_id()
	var hands := _prepare_hands(story, encounter_setup, player_god_id)
	if hands.is_empty():
		return false
	var board := _prepare_board(story, encounter_setup, board_size)
	local_side = GameState.PLAYER_ONE
	records_campaign_stats = true
	local_name = PlayerData.player_name
	opponent_name = UIFormat.combatant_name(str(
		_npc_data.get("combatant_name", _npc_data.get("name", "Adversaire"))), 18)
	local_god = GodIdentityModel.player(player_god_id)
	opponent_god = GodIdentityModel.bot(opponent_god_id)
	_ai_runner = AITurnRunner.new()
	add_child(_ai_runner)
	_ai_runner.setup(_create_ai(story), turn_manager)
	turn_manager.start_game(StoneLoader.build_hand(hands["player"]),
		StoneLoader.build_hand(hands["opponent"]), board["blocked"],
		BattleContext.selected_npc_id, board["first_player"], player_god_id,
		opponent_god_id, 0, board_size, board["initial_stones"])
	return true


## Les scénarios peuvent fournir des mains courtes ; les rencontres ordinaires
## conservent la validation complète du deck et les tailles déclarées.
func _prepare_hands(story: Dictionary, encounter_setup: Dictionary, player_god_id: String) -> Dictionary:
	var story_match := not story.is_empty()
	var deck: Array = BattleContext.effective_player_deck()
	if story_match and story.get("player_deck") is Array:
		deck = (story.get("player_deck") as Array).duplicate()
	var player_hand_size := clampi(int(story.get("player_hand_size",
		encounter_setup.get("player_hand_size", DeckRules.DECK_SIZE))), 1, DeckRules.DECK_SIZE)
	var opponent_hand_size := clampi(int(story.get("opponent_hand_size",
		encounter_setup.get("opponent_hand_size", DeckRules.DECK_SIZE))), 1, DeckRules.DECK_SIZE)
	var allow_incomplete := bool(encounter_setup.get("allow_incomplete_player_deck", false))
	if story_match:
		player_hand_size = mini(player_hand_size, deck.size())
		if player_hand_size <= 0:
			return {}
	elif (not allow_incomplete and not DeckRules.is_deck_valid(deck, player_god_id)) \
			or deck.size() < player_hand_size:
		return {}
	if deck.size() < player_hand_size:
		return {}
	deck = deck.slice(0, player_hand_size)
	var opponent_deck: Array = BattleContext.effective_opponent_deck()
	if story_match and story.get("opponent_deck") is Array:
		opponent_deck = (story.get("opponent_deck") as Array).duplicate()
	if story_match:
		opponent_hand_size = mini(opponent_hand_size, opponent_deck.size())
	if opponent_deck.size() < opponent_hand_size:
		return {}
	opponent_deck = opponent_deck.slice(0, opponent_hand_size)
	return {"player": deck, "opponent": opponent_deck}


func _prepare_board(story: Dictionary, encounter_setup: Dictionary, board_size: int) -> Dictionary:
	var story_match := not story.is_empty()
	var blocked: Array = (encounter_setup.get("blocked_cells", []) as Array).duplicate(true)
	if story_match and story.get("blocked_cells") is Array:
		blocked = (story.get("blocked_cells") as Array).duplicate(true)
	elif not story_match and bool(encounter_setup.get("random_blocked_cells", true)):
		blocked = BoardSetupGenerator.generate(board_size)
	var first_player := BattleContext.forced_first_player
	if story_match:
		var scripted_first := int(story.get("first_player", 0))
		if scripted_first == GameState.PLAYER_HUMAN or scripted_first == GameState.PLAYER_AI:
			first_player = scripted_first
	var initial_stones: Array = []
	if story_match and story.get("initial_stones") is Array:
		initial_stones = (story.get("initial_stones") as Array).duplicate(true)
	return {"blocked": blocked, "first_player": first_player, "initial_stones": initial_stones}


func _create_ai(story: Dictionary) -> AIPlayer:
	var plan: Variant = story.get("opponent_plan", [])
	if plan is Array and not plan.is_empty():
		return ScriptedAI.new(plan)
	return AITurnRunner.create_ai(_npc_data.get("ai", {}))


func can_submit() -> bool:
	var state := turn_manager.get_state()
	return state != null and not state.is_game_over \
		and state.current_player == local_side \
		and turn_manager.phase == TurnManager.Phase.WAITING_INPUT


func request_move(row: int, col: int, stone_id: String) -> bool:
	return turn_manager.human_play(row, col, stone_id)


func on_turn_started(player: int) -> void:
	if player != local_side and _ai_runner != null:
		_ai_runner.run_turn()


func shutdown() -> void:
	if _ai_runner != null:
		_ai_runner.cancel()
