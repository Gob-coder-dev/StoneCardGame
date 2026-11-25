## Accord entre les deux joueurs après une manche. Le coordinateur reste
## responsable de l'envoi et de la préparation du match.
extends RefCounted

enum Kind { NONE, NEXT_ROUND, REMATCH }

var _local: Dictionary[Kind, bool] = {}
var _remote: Dictionary[Kind, bool] = {}


static func can_request(kind: Kind, series: SeriesState, phase: String) -> bool:
	if series == null:
		return false
	match kind:
		Kind.NEXT_ROUND:
			return not series.finished and phase == MatchRules.PHASE_ROUND_RESULT
		Kind.REMATCH:
			return (series.finished and phase == MatchRules.PHASE_SERIES_COMPLETE) \
				or (phase == MatchRules.PHASE_ROUND_RESULT and series.series_format == MatchRules.SERIES_FT1)
	return false


static func request_id(kind: Kind, series_id: String) -> String:
	return "rematch-" + series_id if kind == Kind.REMATCH else series_id


func receive(id: String, series: SeriesState, phase: String) -> Kind:
	if series == null:
		return Kind.NONE
	for kind in [Kind.NEXT_ROUND, Kind.REMATCH]:
		if id == request_id(kind, series.series_id) and can_request(kind, series, phase):
			_remote[kind] = true
			return kind
	return Kind.NONE


func requested_locally(kind: Kind) -> bool:
	return _local.has(kind)


func set_local(kind: Kind, requested: bool) -> void:
	if requested:
		_local[kind] = true
	else:
		_local.erase(kind)


func agreed(kind: Kind) -> bool:
	return _local.has(kind) and _remote.has(kind)


func reset() -> void:
	_local.clear()
	_remote.clear()
