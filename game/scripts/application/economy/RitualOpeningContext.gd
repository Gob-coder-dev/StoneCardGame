## Résultat transitoire d'un achat de Rituel. Les récompenses sont déjà dans la
## sauvegarde : ce contexte ne transporte que leur présentation et disparaît à
## la fermeture du jeu, volontairement sans mécanisme de reprise.
extends Node

var _opening: Dictionary = {}


func begin(opening: Dictionary) -> bool:
	if opening.is_empty() or not opening.get("rewards", []) is Array:
		return false
	_opening = opening.duplicate(true)
	return true


func current() -> Dictionary:
	return _opening.duplicate(true)


func clear() -> void:
	_opening.clear()

