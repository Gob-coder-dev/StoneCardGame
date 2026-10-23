## AIPlayer.gd
## Contrat commun des IA. La réflexion se fait en deux temps pour être répartie
## sur plusieurs images : start_search(état) prépare une MoveSearch, que
## AITurnRunner avance puis interroge. choose_move() fait tout d'un coup.
## Un coup est { "row", "col", "stone_id" }.
class_name AIPlayer
extends RefCounted

const MoveSearch := preload("res://scripts/ai/MoveSearch.gd")

## Délai minimal avant que l'IA joue, en secondes (confort visuel).
var think_delay: float = 0.8


## À redéfinir. L'état reçu est une copie où la main humaine est masquée.
func start_search(_state: GameState) -> MoveSearch:
	push_error("AIPlayer: start_search() doit être implémenté par la sous-classe.")
	return null


## Réflexion complète en une seule fois (tests et outils) : même choix que la
## réflexion découpée. Renvoie {} si aucun coup n'est possible.
func choose_move(state: GameState) -> Dictionary:
	var search := start_search(state)
	if search == null:
		return {}
	search.step()
	return search.chosen_move()
