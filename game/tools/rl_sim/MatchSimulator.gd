## Simulateur synchrone utilise par le trainer RL.
## Il orchestre le moteur existant sans animation ni attente de frame.
class_name MatchSimulator
extends RefCounted

const ProfileAIModel := preload("res://scripts/ai/ProfileAI.gd")
const AIProfileModel := preload("res://scripts/ai/AIProfile.gd")
const MoveEvaluatorModel := preload("res://scripts/ai/MoveEvaluator.gd")

var state: GameState = null
var _opponent_rng := RandomNumberGenerator.new()


func reset(config: Dictionary) -> Dictionary:
	var problem := _validate_config(config)
	if problem != "":
		return {"success": false, "error": problem}
	var seed := int(config["seed"])
	var setup_rng := RandomNumberGenerator.new()
	setup_rng.seed = seed
	state = GameState.new()
	state.set_random_seed(seed)
	state.human_god_id = str(config["human_god"])
	state.ai_god_id = str(config["ai_god"])
	state.setup_hands(config["human_deck"], config["ai_deck"])
	var blocked: Array = config["blocked"].duplicate(true) if config.has("blocked") else _draw_blocked(setup_rng)
	var blocked_problem := _validate_blocked(blocked)
	if blocked_problem != "":
		state = null
		return {"success": false, "error": blocked_problem}
	state.apply_blocked_cells(blocked)
	var first_player := int(config.get("first_player", 0))
	if first_player == 0:
		first_player = GameState.PLAYER_HUMAN if setup_rng.randi_range(0, 1) == 0 else GameState.PLAYER_AI
	if first_player != GameState.PLAYER_HUMAN and first_player != GameState.PLAYER_AI:
		state = null
		return {"success": false, "error": "first_player doit valoir 1 ou 2"}
	state.current_player = first_player
	_update_outcome()
	_opponent_rng.seed = seed ^ 0x5A17C9
	return {"success": true, "blocked": blocked, "first_player": first_player}


func legal_actions() -> Array:
	if state == null or state.is_game_over:
		return []
	return RulesEngine.get_valid_moves(state, state.current_player)


func step(action: Dictionary) -> Dictionary:
	if state == null:
		return {"success": false, "error": "aucune partie active"}
	if state.is_game_over:
		return {"success": false, "error": "la partie est terminee"}
	var player := state.current_player
	var result := CombatResolver.apply_move(state, int(action.get("row", -1)), int(action.get("col", -1)), str(action.get("stone_id", "")), player)
	if not bool(result.get("success", false)):
		return {"success": false, "error": str(result.get("reason", "action invalide"))}
	_update_outcome()
	if not state.is_game_over:
		state.current_player = _other_player(player)
	return {
		"success": true,
		"player": player,
		"captures": result.get("captures", []),
		"effects": result.get("effects", []),
		"placement_effects": result.get("placement", {}).get("placement_effects", []),
		"done": state.is_game_over,
		"winner": state.winner
	}


func choose_profile_action(profile_data: Dictionary) -> Dictionary:
	if state == null or state.is_game_over:
		return {"success": false, "error": "aucune decision possible"}
	var problems := AIProfileModel.problems(profile_data)
	if not problems.is_empty():
		return {"success": false, "error": "; ".join(problems)}
	var ai := ProfileAIModel.new(AIProfileModel.new(profile_data))
	ai.rng.state = _opponent_rng.state
	var ai_view := state.clone()
	if state.current_player == GameState.PLAYER_HUMAN:
		_swap_players(ai_view)
	var move := ai.choose_move(ai_view.clone_for_ai())
	_opponent_rng.state = ai.rng.state
	if move.is_empty():
		return {"success": false, "error": "ProfileAI ne trouve aucun coup"}
	return {"success": true, "action": move}


## Conséquences publiques utilisées par la politique tactique RL. Cette méthode
## ne choisit aucun coup et travaille exclusivement sur des clones de l'état.
func tactical_action_scores(observer: int) -> Dictionary:
	if state == null or state.is_game_over or state.current_player != observer:
		return {}
	var view := state.clone()
	if observer == GameState.PLAYER_HUMAN:
		_swap_players(view)
	view = view.clone_for_ai()
	var moves := RulesEngine.get_valid_moves(view, GameState.PLAYER_AI)
	var immediate_evaluator := MoveEvaluatorModel.new(view, false)
	var anticipated_evaluator := MoveEvaluatorModel.new(view, true)
	var scores := {}
	for move in moves:
		var immediate := _average_move_value(immediate_evaluator, move)
		var anticipated := _average_move_value(anticipated_evaluator, move)
		var hand_slot := view.ai_hand.find(str(move["stone_id"]))
		if hand_slot < 0:
			continue
		var action := hand_slot * 16 + int(move["row"]) * 4 + int(move["col"])
		var definition := StoneLoader.get_stone(str(move["stone_id"]))
		var stochastic := int(definition.get("random_blades", 0)) > 0 \
			or str(definition.get("coin_flip", "")) != ""
		scores[str(action)] = [
			immediate,
			anticipated,
			maxf(0.0, immediate - anticipated),
			1.0 if stochastic else 0.0,
			1.0 + 2.0 * immediate,
		]
	return scores


func _average_move_value(evaluator, move: Dictionary) -> float:
	var first: Dictionary = evaluator.evaluate(move, 0)
	var total := float(first["value"])
	var count := 1
	if bool(first["random"]):
		for sample in range(1, evaluator.random_samples()):
			total += float(evaluator.evaluate(move, sample)["value"])
			count += 1
	return total / count


func _update_outcome() -> void:
	var score := RulesEngine.calculate_score(state)
	state.score_human = int(score["human"])
	state.score_ai = int(score["ai"])
	state.is_game_over = RulesEngine.is_game_over(state)
	state.winner = RulesEngine.determine_winner(state) if state.is_game_over else GameState.PLAYER_NONE


func _validate_config(config: Dictionary) -> String:
	var seed_value = config.get("seed")
	if not (seed_value is int or seed_value is float) or float(seed_value) != floor(float(seed_value)):
		return "seed entier obligatoire"
	for side in ["human", "ai"]:
		var god_key := "%s_god" % side
		var deck_key := "%s_deck" % side
		if StoneLoader.get_god(str(config.get(god_key, ""))).is_empty():
			return "dieu inconnu pour %s" % side
		var deck = config.get(deck_key, [])
		if not deck is Array:
			return "%s doit etre un tableau" % deck_key
		var validation := DeckRules.validate_deck(deck, true, str(config[god_key]))
		if not bool(validation["valid"]):
			return "%s invalide: %s" % [deck_key, validation["reason"]]
	return ""


func _validate_blocked(blocked: Array) -> String:
	if blocked.size() > 2:
		return "le terrain accepte au maximum deux cases bloquees"
	var seen := {}
	for raw_pos in blocked:
		if not raw_pos is Array or raw_pos.size() != 2:
			return "chaque case bloquee doit etre [row, col]"
		var row := int(raw_pos[0])
		var col := int(raw_pos[1])
		if row < 0 or row >= GameState.BOARD_SIZE or col < 0 or col >= GameState.BOARD_SIZE:
			return "case bloquee hors plateau"
		var key := "%d:%d" % [row, col]
		if seen.has(key):
			return "case bloquee dupliquee"
		seen[key] = true
	if GameState.total_cells() - blocked.size() > DeckRules.DECK_SIZE * 2:
		return "pas assez de cartes pour remplir le plateau"
	return ""


func _draw_blocked(rng: RandomNumberGenerator) -> Array:
	var roll := rng.randi_range(0, 99)
	var count := 0 if roll < 40 else (1 if roll < 75 else 2)
	var cells: Array = []
	for index in range(GameState.total_cells()):
		cells.append([index / GameState.BOARD_SIZE, index % GameState.BOARD_SIZE])
	var blocked: Array = []
	for _index in range(count):
		blocked.append(cells.pop_at(rng.randi_range(0, cells.size() - 1)))
	return blocked


func _other_player(player: int) -> int:
	return GameState.PLAYER_AI if player == GameState.PLAYER_HUMAN else GameState.PLAYER_HUMAN


## ProfileAI est historiquement ecrit pour PLAYER_AI. Cette vue symetrique lui
## permet de jouer PLAYER_HUMAN sans modifier les regles ni exposer la main adverse.
func _swap_players(view: GameState) -> void:
	var previous_human_hand := view.human_hand
	view.human_hand = view.ai_hand
	view.ai_hand = previous_human_hand
	var previous_human_god := view.human_god_id
	view.human_god_id = view.ai_god_id
	view.ai_god_id = previous_human_god
	var previous_human_score := view.score_human
	view.score_human = view.score_ai
	view.score_ai = previous_human_score
	view.current_player = _other_player(view.current_player)
	if view.winner != GameState.PLAYER_NONE:
		view.winner = _other_player(view.winner)
	for cell in view.board:
		if int(cell["owner"]) != GameState.PLAYER_NONE:
			cell["owner"] = _other_player(int(cell["owner"]))
		if int(cell["placed_by"]) != GameState.PLAYER_NONE:
			cell["placed_by"] = _other_player(int(cell["placed_by"]))
		var stone = cell.get("stone")
		if stone != null and stone.temporary_weakness_owner != GameState.PLAYER_NONE:
			stone.temporary_weakness_owner = _other_player(stone.temporary_weakness_owner)
