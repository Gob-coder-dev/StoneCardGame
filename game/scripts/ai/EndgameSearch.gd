## Explore les placements jusqu'à la fin, par tranches de cartes adverses.
## La main adverse reste supposée et le hasard est fixé par chaque simulation :
## l'exploration des coups est complète, pas celle de toutes les issues du hasard.
extends RefCounted

const Resolver := preload("res://scripts/engine/CombatResolver.gd")
const Opponent := preload("res://scripts/ai/OpponentModel.gd")

var _simulation: GameState
var _hand_size: int
var _cards: Array
var _free_cells: Array
var _values: Array[float] = []
var _result := 0.0
var _finished := false


func _init(simulation: GameState, hand_size: int) -> void:
	_simulation = simulation
	_hand_size = hand_size
	_cards = simulation.human_hand.duplicate()
	_free_cells = RulesEngine.get_free_cells(simulation)
	if _cards.is_empty() or hand_size <= 0 or _free_cells.is_empty():
		_result = _final_value(simulation)
		_finished = true


## Une carte est l'unité de travail : après la pose de l'IA, il reste au plus
## une case au seuil de fin de partie actuel. Un budget nul termine le calcul.
func step(budget_usec: int = 0) -> bool:
	if _finished:
		return true
	var started := Time.get_ticks_usec()
	while _values.size() < _cards.size():
		_values.append(_reply_value(_cards[_values.size()]))
		if budget_usec > 0 and Time.get_ticks_usec() - started >= budget_usec:
			return false
	_result = Opponent.expected_from_variants(_cards, _values, _hand_size, false)
	_finished = true
	return true


func value() -> float:
	return _result


## Au tour de l'IA, choisit son meilleur placement. La borne bêta permet une
## coupure à plus grande profondeur ; avec le seuil actuel de deux cases,
## ce tour arrive sur un plateau plein et aucune branche n'est coupée.
static func _ai_turn_value(simulation: GameState, hand_size: int, alpha: float, beta: float) -> float:
	var moves := RulesEngine.get_valid_moves(simulation, GameState.PLAYER_AI)
	if moves.is_empty():
		return _final_value(simulation)
	var best := -INF
	for move in moves:
		var child := simulation.clone()
		Resolver.apply_move(child, move["row"], move["col"], move["monster_id"], GameState.PLAYER_AI)
		best = maxf(best, evaluate(child, hand_size))
		alpha = maxf(alpha, best)
		if alpha >= beta:
			break
	return best

## Au tour humain, suppose chaque carte possible, choisit sa meilleure case,
## puis pondère ces valeurs par les mains cachées de la taille donnée.
static func evaluate(simulation: GameState, hand_size: int) -> float:
	var search := new(simulation, hand_size)
	search.step()
	return search.value()


func _reply_value(card: String) -> float:
	var best := INF
	for cell in _free_cells:
		var child := _simulation.clone()
		Resolver.apply_move(child, cell["row"], cell["col"], card, GameState.PLAYER_HUMAN)
		if RulesEngine.is_game_over(child):
			best = minf(best, _final_value(child))
			continue
		var used_lineage := MonsterLoader.monster_lineage(card)
		child.human_hand = child.human_hand.filter(func(other): return MonsterLoader.monster_lineage(str(other)) != used_lineage)
		# Seule une riposte plus forte que la meilleure trouvée pour cette carte compte.
		best = minf(best, _ai_turn_value(child, _hand_size - 1, -INF, best))
	return best

## Écart final divisé par deux : une capture change l'écart de deux points.
static func _final_value(simulation: GameState) -> float:
	var score := RulesEngine.calculate_score(simulation)
	return (score["ai"] - score["human"]) / 2.0
