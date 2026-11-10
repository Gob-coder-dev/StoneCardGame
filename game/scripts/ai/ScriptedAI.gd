## ScriptedAI.gd
## IA de mise en scène : elle joue les coups fournis par le scénario dans
## l'ordre, sans aucun tirage. Si un coup préparé n'est plus possible parce que
## le joueur a occupé sa case, elle passe au suivant ; en dernier recours, elle
## prend le premier coup valide dans l'ordre stable du plateau et de la main.
## Elle n'est utilisée que par les matchs narratifs qui fournissent un plan.
class_name ScriptedAI
extends AIPlayer

const MoveSearchModel := preload("res://scripts/ai/MoveSearch.gd")

var _plan: Array = []
var _next_plan_index := 0


func _init(plan: Array = []) -> void:
	_plan = plan.duplicate(true)
	think_delay = 0.65


func start_search(state: GameState) -> MoveSearch:
	var move := _next_move(state)
	if move.is_empty():
		return null
	return MoveSearchModel.new([move], null, func(_scored: Array) -> Dictionary:
		return move.duplicate())


func _next_move(state: GameState) -> Dictionary:
	if state == null:
		return {}
	var valid := RulesEngine.get_valid_moves(state, GameState.PLAYER_AI)
	if valid.is_empty():
		return {}
	while _next_plan_index < _plan.size():
		var raw: Variant = _plan[_next_plan_index]
		_next_plan_index += 1
		if not raw is Dictionary:
			continue
		var candidate := _normalized(raw)
		for move in valid:
			if _same_move(move, candidate):
				return candidate
	# Plan épuisé ou cases devenues indisponibles : l'ordre du moteur reste
	# déterministe, aucune décision n'est laissée au hasard.
	return (valid[0] as Dictionary).duplicate()


func _normalized(source: Dictionary) -> Dictionary:
	return {
		"row": int(source.get("row", -1)),
		"col": int(source.get("col", -1)),
		"stone_id": str(source.get("stone_id", "")),
	}


func _same_move(first: Dictionary, second: Dictionary) -> bool:
	return int(first.get("row", -1)) == int(second.get("row", -1)) \
		and int(first.get("col", -1)) == int(second.get("col", -1)) \
		and str(first.get("stone_id", "")) == str(second.get("stone_id", ""))
