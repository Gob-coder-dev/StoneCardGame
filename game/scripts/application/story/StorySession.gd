## StorySession.gd
## Une séquence en cours de lecture. Le service la met en file, la couche
## d'affichage la consomme, et les contrôleurs peuvent attendre `finished` sans
## connaître l'interface.
class_name StorySession
extends RefCounted

signal finished

var sequence_id: String = ""
var sequence: Dictionary = {}
var context: Dictionary = {}
var trigger: Dictionary = {}
var replay: bool = false
var _finished := false


func finish() -> void:
	if _finished:
		return
	_finished = true
	finished.emit()


func is_finished() -> bool:
	return _finished
