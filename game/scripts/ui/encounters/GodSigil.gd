## GodSigil.gd
## Couche décorative d'un dieu : un motif discret, sans interaction. Elle
## ignore les gestes pour laisser les boutons de la case et du chemin réagir.
class_name GodSigil
extends Control

const GodMotifModel := preload("res://scripts/ui/encounters/GodMotif.gd")

var _god_id := ""
var _color := Color.WHITE
var _strength := 0.12


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(god_id: String, family_color: Color, strength: float = 0.12) -> void:
	_god_id = god_id
	_color = family_color
	_strength = strength
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.46
	GodMotifModel.draw(self, _god_id, size * 0.5, radius, _color, _strength)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
