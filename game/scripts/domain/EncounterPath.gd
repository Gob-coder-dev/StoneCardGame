## EncounterPath.gd
## Règle pure de progression d'un chemin de rencontres : un niveau s'ouvre
## seulement quand le précédent a été gagné. Aucune interface, aucune
## sauvegarde : l'ordre des niveaux et le prédicat de victoire sont fournis
## par l'appelant.
class_name EncounterPath
extends RefCounted

enum State { LOCKED, AVAILABLE, COMPLETED }


## Ajoute à chaque niveau son état de progression. Le chemin est strictement
## linéaire : seuls les niveaux d'un préfixe gagné sont terminés, et un seul
## niveau reste ouvert. Une victoire antérieure hors séquence est conservée
## dans le profil, mais elle n'ouvre pas le chemin : elle compte dès que les
## niveaux précédents ont été gagnés.
static func states(levels: Array, is_beaten: Callable) -> Array:
	var result: Array = []
	var frontier_open := true
	for level in levels:
		var entry: Dictionary = level.duplicate(true)
		var beaten := bool(is_beaten.call(str(entry.get("opponent_id", ""))))
		var completed := beaten and frontier_open
		var state := State.LOCKED
		if completed:
			state = State.COMPLETED
		elif frontier_open:
			state = State.AVAILABLE
		entry["beaten"] = beaten
		entry["completed"] = completed
		entry["state"] = state
		entry["playable"] = completed or frontier_open
		frontier_open = completed
		result.append(entry)
	return result


## Premier niveau encore à gagner, pour l'ouvrir par défaut. Si le parcours
## est terminé, le dernier niveau reste sélectionné.
static func current_index(path: Array) -> int:
	for index in range(path.size()):
		if int(path[index].get("state", State.LOCKED)) == State.AVAILABLE:
			return index
	return maxi(0, path.size() - 1)


## Niveau qui suit immédiatement `opponent_id_value` dans un chemin ordonné.
## Renvoie un dictionnaire vide si l'adversaire est absent ou au dernier rond.
static func next_level(levels: Array, opponent_id_value: String) -> Dictionary:
	for index in range(levels.size() - 1):
		if str(levels[index].get("opponent_id", "")) == opponent_id_value:
			return levels[index + 1]
	return {}


static func completed_count(path: Array) -> int:
	var count := 0
	for level in path:
		if bool(level.get("completed", false)):
			count += 1
	return count


static func is_complete(path: Array) -> bool:
	return not path.is_empty() and completed_count(path) == path.size()
