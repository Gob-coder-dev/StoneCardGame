## CampaignMatchDriver.gd
## Driver de la campagne : configuration du bot et exécution de son tour.
## Le moteur, les règles et l'IA restent exactement ceux d'avant. Un chapitre
## guidé peut fournir un setup de match (mains, monstres initiales, premier
## joueur et plan du bot) ; ce setup reste une donnée du scénario, pas du niveau.
class_name CampaignMatchDriver
extends MatchDriver

const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")
const MatchSetup := preload("res://scripts/domain/campaign/CampaignMatchSetup.gd")

var _ai_runner: AITurnRunner = null
var _npc_data: Dictionary = {}


func start() -> bool:
	if BattleContext.selected_npc_id == "":
		return false
	_npc_data = BattleContext.current_opponent()
	if _npc_data.is_empty():
		push_error("CampaignMatchDriver: adversaire '%s' introuvable." % BattleContext.selected_npc_id)
		return false
	var story := StoryService.match_setup_for_node(BattleContext.campaign_node_id)
	var encounter_setup: Dictionary = _npc_data.get("match_setup", {})
	var match_setup := MatchSetup.resolve(encounter_setup, story, BattleContext.forced_first_player)
	var player_god_id := BattleContext.effective_player_god_id()
	var opponent_god_id := BattleContext.effective_opponent_god_id()
	var hands := _prepare_hands(story, match_setup, player_god_id,
		bool(encounter_setup.get("allow_incomplete_player_deck", false)))
	if hands.is_empty():
		start_error = "Les decks disponibles ne permettent pas de préparer les mains de cette rencontre."
		return false
	var player_hand := MonsterLoader.build_hand(hands["player"])
	var opponent_hand := MonsterLoader.build_hand(hands["opponent"])
	start_error = MatchSetup.problem(match_setup, player_hand.size(), opponent_hand.size())
	if start_error != "":
		return false
	var board_size := int(match_setup["board_size"])
	var blocked: Array = BoardSetupGenerator.generate(board_size) \
		if match_setup["random_blocked_cells"] else match_setup["blocked_cells"]
	local_side = GameState.PLAYER_ONE
	records_campaign_stats = true
	local_name = PlayerData.player_name
	opponent_name = UIFormat.campaign_combatant_name(_npc_data)
	local_god = GodIdentityModel.player(player_god_id)
	opponent_god = GodIdentityModel.bot(opponent_god_id)
	_ai_runner = AITurnRunner.new()
	add_child(_ai_runner)
	_ai_runner.setup(_create_ai(story), turn_manager)
	turn_manager.start_game(player_hand, opponent_hand, blocked,
		BattleContext.selected_npc_id, match_setup["first_player"], player_god_id,
		opponent_god_id, 0, board_size, match_setup["initial_monsters"])
	return true


## Les scénarios peuvent fournir des mains courtes ; les rencontres ordinaires
## conservent la validation complète du deck et les tailles déclarées.
func _prepare_hands(story: Dictionary, match_setup: Dictionary, player_god_id: String,
		allow_incomplete: bool) -> Dictionary:
	var story_match := not story.is_empty()
	var deck: Array = BattleContext.effective_player_deck()
	if story_match and story.get("player_deck") is Array:
		deck = (story.get("player_deck") as Array).duplicate()
	var player_hand_size := clampi(int(match_setup["player_hand_size"]), 1, DeckRules.DECK_SIZE)
	var opponent_hand_size := clampi(int(match_setup["opponent_hand_size"]), 1, DeckRules.DECK_SIZE)
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


func request_move(row: int, col: int, monster_id: String) -> bool:
	return turn_manager.human_play(row, col, monster_id)


func on_turn_started(player: int) -> void:
	if player != local_side and _ai_runner != null:
		_ai_runner.run_turn()


func shutdown() -> void:
	if _ai_runner != null:
		_ai_runner.cancel()
