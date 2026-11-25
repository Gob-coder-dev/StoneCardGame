## Réflexion de l'IA, découpable entre plusieurs images : step() évalue des
## tirages de coups jusqu'à épuiser son budget de temps, puis rend la main.
## Une fois tout évalué, le choix du coup est confié à la fonction fournie.
extends RefCounted

var _moves: Array
var _evaluator = null  ## MoveEvaluator, ou null pour choisir sans rien évaluer
var _choose: Callable  ## (coups notés : [{ "move", "value" }]) -> coup
## Tirages à évaluer, dans l'ordre : Vector2i(indice du coup, numéro du tirage).
var _pending: Array[Vector2i] = []
var _next := 0
var _totals := PackedFloat64Array()
var _counts := PackedInt32Array()
var _chosen := {}
var _finished := false


func _init(moves: Array, evaluator, choose: Callable) -> void:
	_moves = moves
	_evaluator = evaluator
	_choose = choose
	_totals.resize(moves.size())
	_counts.resize(moves.size())
	if evaluator != null:
		for index in range(moves.size()):
			_pending.append(Vector2i(index, 0))


## Avance la préparation puis les tirages pendant environ budget_usec
## microsecondes (0 : jusqu'au bout). Un tirage peut reprendre à l'image suivante.
## Renvoie true quand le coup est choisi.
func step(budget_usec: int = 0) -> bool:
	if _finished:
		return true
	var started := Time.get_ticks_usec()
	if _evaluator != null:
		var remaining := budget_usec
		if budget_usec > 0:
			remaining = maxi(1, budget_usec - int(Time.get_ticks_usec() - started))
		if not _evaluator.prepare_step(remaining):
			return false
	while _next < _pending.size():
		var remaining := budget_usec
		if budget_usec > 0:
			remaining -= Time.get_ticks_usec() - started
			if remaining <= 0:
				return false
		var unit: Vector2i = _pending[_next]
		var outcome: Dictionary = _evaluator.evaluate(_moves[unit.x], unit.y, remaining)
		if outcome.is_empty():
			return false
		_next += 1
		_totals[unit.x] += float(outcome["value"])
		_counts[unit.x] += 1
		if unit.y == 0 and outcome["random"]:
			for sample in range(1, _evaluator.random_samples()):
				_pending.append(Vector2i(unit.x, sample))
	_finish()
	return true


func is_finished() -> bool:
	return _finished


## Coup choisi, ou {} si aucun coup n'est possible. Valide une fois step() terminé.
func chosen_move() -> Dictionary:
	return _chosen.duplicate()


func _finish() -> void:
	var scored: Array = []
	for index in range(_moves.size()):
		var value := _totals[index] / _counts[index] if _counts[index] > 0 else 0.0
		scored.append({"move": _moves[index], "value": value})
	_chosen = _choose.call(scored) if not scored.is_empty() else {}
	_finished = true
