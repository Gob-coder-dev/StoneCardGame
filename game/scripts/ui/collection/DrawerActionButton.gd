## Bouton textuel réservé au tiroir de carte. Sa largeur est imposée par
## l'ancre visuelle ; le libellé ne doit jamais élargir la grille par lui-même.
class_name DrawerActionButton
extends "res://scripts/ui/input/TouchButton.gd"


func _get_minimum_size() -> Vector2:
	return Vector2.ZERO
