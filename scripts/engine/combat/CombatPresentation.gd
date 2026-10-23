## Une étape à révéler. Le consommateur appelle complete() à la fin réelle.
## Sans consommateur graphique, TurnManager avance à la frame suivante.
class_name CombatPresentation
extends RefCounted
signal finished
signal cancelled
enum Kind { PLACEMENT, PREPARATION, SWARM, ATTACK, EFFECTS }

var kind: Kind
var row: int
var col: int
var player: int
var events: Array
var completed: bool = false
var placement_swarm: Array = []

func _init(type: Kind, r: int, c: int, owner: int, data: Array = []) -> void:
	kind = type
	row = r
	col = c
	player = owner
	events = data

func complete() -> void:
	if completed:
		return
	completed = true
	finished.emit()

func cancel() -> void:
	if completed:
		return
	cancelled.emit()
	complete()
