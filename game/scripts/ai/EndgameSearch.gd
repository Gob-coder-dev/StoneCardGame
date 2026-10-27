## Explore les placements jusqu'à la fin, sans état conservé dans ce service.
## La main adverse reste supposée et le hasard est fixé par chaque simulation :
## l'exploration des coups est complète, pas celle de toutes les issues du hasard.
extends RefCounted

const Resolver := preload("res://scripts/engine/CombatResolver.gd")
const Opponent := preload("res://scripts/ai/OpponentModel.gd")

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
		Resolver.apply_move(child, move["row"], move["col"], move["stone_id"], GameState.PLAYER_AI)
		best = maxf(best, evaluate(child, hand_size))
		alpha = maxf(alpha, best)
		if alpha >= beta:
			break
	return best

## Au tour humain, suppose chaque carte possible, choisit sa meilleure case,
## puis pondère ces valeurs par les mains cachées de la taille donnée.
static func evaluate(simulation: GameState, hand_size: int) -> float:
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
			var used_lineage := StoneLoader.stone_lineage(str(card))
			child.human_hand = child.human_hand.filter(func(other): return StoneLoader.stone_lineage(str(other)) != used_lineage)
			# Seule une riposte plus forte que la meilleure trouvée pour cette carte compte.
			best = minf(best, _ai_turn_value(child, hand_size - 1, -INF, best))
		values.append(best)
	return Opponent.expected_from_variants(cards, values, hand_size, false)

## Écart final divisé par deux : une capture change l'écart de deux points.
static func _final_value(simulation: GameState) -> float:
	var score := RulesEngine.calculate_score(simulation)
	return (score["ai"] - score["human"]) / 2.0
