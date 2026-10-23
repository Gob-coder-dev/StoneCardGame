## Budget d'une définition de carte, indépendant du chargement et de l'interface.
class_name StoneCostRules
extends RefCounted

static func cost(stone: Dictionary) -> float:
	if stone.is_empty():
		return 0.0
	var b: Dictionary = stone["blades"]
	var total := float(int(b.get("top", 0)) + int(b.get("bottom", 0)) + int(b.get("left", 0)) + int(b.get("right", 0)))
	total += float(stone.get("random_blades", 0)) * 0.5
	for value in stone.get("shields", {}).values():
		total += float(value) * 0.5
	# Une lame longue reste une lame en combat rapproché et gagne une attaque
	# de ligne : son coût initial est volontairement supérieur à une lame normale.
	for value in stone.get("long_blades", {}).values():
		total += float(value) * 1.5
	total += float(stone.get("power_cost", 0.0))
	return total
