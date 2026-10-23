## Valeur d'un coup de l'IA, en nombre de captures. Le coup est joué par le
## résolveur de la partie sur une copie de l'état reçu par l'IA :
## - gain : captures du coup ;
## - avec anticipation : moins la riposte attendue de l'adversaire, c'est-à-dire
##   la meilleure riposte de sa main, en moyenne sur les mains possibles ;
## - avec anticipation, à ENDGAME_CELLS cases libres ou moins : calcul exact
##   jusqu'à la fin de la partie, chaque riposte étant pondérée de la même façon.
## Chaque tirage fixe le hasard de la copie : un coup qui utilise le hasard est
## évalué en moyenne sur plusieurs tirages, sans jamais lire le hasard réel.
extends RefCounted

const Resolver := preload("res://scripts/engine/CombatResolver.gd")
const Opponent := preload("res://scripts/ai/OpponentModel.gd")

## Tirages d'un coup aléatoire (Fortune, Pillage…), hors fin de partie.
const RANDOM_SAMPLES := 8
## En fin de partie, chaque tirage explore tout l'arbre restant.
const ENDGAME_RANDOM_SAMPLES := 2
const ENDGAME_CELLS := 3
## Poids de la riposte : une capture subie compte autant qu'une capture gagnée.
const RISK_WEIGHT := 1.0

var _state: GameState
var _anticipation := false
var _endgame := false
## Cartes que l'adversaire peut avoir, et nombre de cartes de sa main.
var _possible_cards: Array[String] = []
var _hand_size := 0
## Orientations possibles de chaque carte adverse, préparées une seule fois.
var _threats: Array = []
var _threat_weights := PackedFloat64Array()


func _init(state: GameState, anticipation: bool) -> void:
	_state = state
	_anticipation = anticipation
	if not anticipation:
		return
	_possible_cards = Opponent.possible_cards(state)
	_hand_size = state.human_hand.size()
	_endgame = state.empty_playable_cells <= ENDGAME_CELLS
	if not _endgame:
		_threats = Opponent.attack_variants(_possible_cards)
		_threat_weights = Opponent.rank_weights(_possible_cards.size(), _hand_size)


func is_endgame() -> bool:
	return _endgame


## Nombre total de tirages d'un coup dont la simulation a utilisé le hasard.
func random_samples() -> int:
	return ENDGAME_RANDOM_SAMPLES if _endgame else RANDOM_SAMPLES


## Évalue un tirage d'un coup : { "value": float, "random": bool }.
## "random" signale que le coup a consommé du hasard et mérite d'autres tirages.
func evaluate(move: Dictionary, sample: int) -> Dictionary:
	var stone_id: String = move["stone_id"]
	var row: int = move["row"]
	var col: int = move["col"]
	var simulation := _state.clone()
	simulation.set_random_seed(hash("preview:%s:%d:%d:%d" % [stone_id, row, col, sample]))
	var seeded_state := simulation.random_state
	var result := Resolver.apply_move(simulation, row, col, stone_id, GameState.PLAYER_AI)
	var used_random := simulation.random_state != seeded_state
	var value: float
	if _endgame:
		# Les coups adverses sont choisis parmi toutes ses cartes possibles.
		simulation.human_hand = _possible_cards.duplicate()
		value = _human_turn_value(simulation, _hand_size)
	else:
		value = float(result.get("captures", []).size())
		if _anticipation:
			value -= RISK_WEIGHT * threat(simulation)
	return {"value": value, "random": used_random}


## Riposte attendue : pour chaque carte possible, le plus grand nombre de
## pierres de l'IA qu'elle capturerait aussitôt depuis une case libre (les deux
## orientations d'un pile ou face comptent chacune pour moitié), puis la
## meilleure de ces valeurs dans la main adverse, en moyenne sur ses mains possibles.
func threat(simulation: GameState) -> float:
	if _threats.is_empty() or _threat_weights.is_empty():
		return 0.0
	var free_cells := RulesEngine.get_free_cells(simulation)
	var values: Array[float] = []
	for variants in _threats:
		var best := 0.0
		for cell in free_cells:
			var total := 0
			for stone in variants:
				total += Resolver.find_captures(simulation, cell["row"], cell["col"],
					GameState.PLAYER_HUMAN, stone).size()
			best = maxf(best, float(total) / variants.size())
		values.append(best)
	values.sort()
	values.reverse()
	return Opponent.expected_best(values, _threat_weights)


## Fin de partie, au tour de l'IA : son meilleur coup (élagage alpha-bêta).
func _ai_turn_value(simulation: GameState, hand_size: int, alpha: float, beta: float) -> float:
	var moves := RulesEngine.get_valid_moves(simulation, GameState.PLAYER_AI)
	if moves.is_empty():
		return _final_value(simulation)
	var best := -INF
	for move in moves:
		var child := simulation.clone()
		Resolver.apply_move(child, move["row"], move["col"], move["stone_id"], GameState.PLAYER_AI)
		best = maxf(best, _human_turn_value(child, hand_size))
		alpha = maxf(alpha, best)
		if alpha >= beta:
			break
	return best


## Fin de partie, au tour de l'adversaire : chaque carte possible donne sa
## meilleure riposte, puis la meilleure de sa main est prise en moyenne sur les
## mains possibles, comme pour threat().
func _human_turn_value(simulation: GameState, hand_size: int) -> float:
	var cards: Array = simulation.human_hand.duplicate()
	var free_cells := RulesEngine.get_free_cells(simulation)
	if cards.is_empty() or hand_size <= 0 or free_cells.is_empty():
		return _final_value(simulation)
	var values: Array[float] = []
	for card in cards:
		var best := INF
		for cell in free_cells:
			var child := simulation.clone()
			Resolver.apply_move(child, cell["row"], cell["col"], card, GameState.PLAYER_HUMAN)
			# Seule une riposte plus forte que la meilleure trouvée pour cette carte compte.
			best = minf(best, _ai_turn_value(child, hand_size - 1, -INF, best))
		values.append(best)
	values.sort()
	return Opponent.expected_best(values, Opponent.rank_weights(cards.size(), hand_size))


## Écart final des scores, divisé par deux pour rester en captures (une capture
## change l'écart de deux points).
func _final_value(simulation: GameState) -> float:
	var score := RulesEngine.calculate_score(simulation)
	return (score["ai"] - score["human"]) / 2.0
