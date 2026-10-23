## AIPlayer.gd
## Classe de base des IA. Définit le contrat choose_move(state) -> coup.
## Un coup est { "row", "col", "stone_id" }.
class_name AIPlayer
extends RefCounted

## Délai simulé avant que l'IA joue (confort visuel).
var think_delay: float = 0.8


## À redéfinir par les sous-classes. Retourne un coup, ou {} si aucun possible.
func choose_move(_state: GameState) -> Dictionary:
	push_error("AIPlayer: choose_move() doit être implémenté par la sous-classe.")
	return {}
