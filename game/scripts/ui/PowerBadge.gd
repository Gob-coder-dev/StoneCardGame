## Même pictogramme que sur les cartes, à une taille lisible dans les règles.
extends Control

const Symbols := preload("res://scripts/ui/StoneSymbols.gd")

var kind: String = ""
var color := Color.WHITE
var count: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var radius := minf(size.y * 0.44, size.x * 0.44)
	var width := Symbols.badge_width(radius, count)
	if width > size.x - 6.0:
		radius *= (size.x - 6.0) / width
	Symbols.draw_badge(self, Vector2(radius + 3.0, size.y * 0.5), radius, kind, color, count)
