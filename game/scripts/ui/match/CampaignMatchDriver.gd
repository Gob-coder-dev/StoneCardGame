## CampaignMatchDriver.gd
## Driver de la campagne : configuration du bot et exécution de son tour.
## Le moteur, les règles et l'IA restent exactement ceux d'avant.
class_name CampaignMatchDriver
extends MatchDriver

var _ai_runner: AITurnRunner = null
var _npc_data: Dictionary = {}


func start() -> bool:
	var deck := BattleContext.effective_player_deck()
	var player_god_id := BattleContext.effective_player_god_id()
	if not DeckRules.is_deck_valid(deck, player_god_id):
		return false
	if BattleContext.selected_npc_id == "":
		return false
	_npc_data = BattleContext.current_opponent()
	if str(_npc_data.get("id", "")) != BattleContext.selected_npc_id:
		_npc_data = StoneLoader.get_npc(BattleContext.selected_npc_id)
	if _npc_data.is_empty():
		push_error("CampaignMatchDriver: adversaire '%s' introuvable." % BattleContext.selected_npc_id)
		return false

	local_side = GameState.PLAYER_ONE
	records_campaign_stats = true
	local_name = PlayerData.player_name
	opponent_name = str(_npc_data.get("name", "Adversaire"))
	var opponent_god_id := BattleContext.effective_opponent_god_id()
	var opponent_deck := BattleContext.effective_opponent_deck()
	local_god = StoneLoader.get_god(player_god_id)
	opponent_god = StoneLoader.get_god(opponent_god_id)
	if not DeckRules.is_deck_valid(opponent_deck, opponent_god_id):
		return false

	var ai := AITurnRunner.create_ai(_npc_data.get("ai", {}))
	_ai_runner = AITurnRunner.new()
	add_child(_ai_runner)
	_ai_runner.setup(ai, turn_manager)

	turn_manager.start_game(
		StoneLoader.build_hand(deck),
		StoneLoader.build_hand(opponent_deck),
		BoardSetupGenerator.generate(),
		BattleContext.selected_npc_id,
		BattleContext.forced_first_player,
		player_god_id,
		opponent_god_id
	)
	return true


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
