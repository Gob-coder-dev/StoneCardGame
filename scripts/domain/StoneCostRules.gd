## Budget d'une définition de carte, indépendant du chargement et de l'interface.
class_name StoneCostRules
extends RefCounted

const NORMAL_BLADE_COST := 1.0
const RANDOM_BLADE_COST := 0.5
const SHIELD_COST := 0.5
## Une lame longue reste une lame en combat rapproché et gagne une attaque
## de ligne : son coût est volontairement supérieur à une lame normale.
const LONG_BLADE_COST := 1.5

static func cost(stone: Dictionary) -> float:
	if stone.is_empty():
		return 0.0
	var b: Dictionary = stone["blades"]
	var total := float(int(b.get("top", 0)) + int(b.get("bottom", 0)) + int(b.get("left", 0)) + int(b.get("right", 0))) * NORMAL_BLADE_COST
	total += float(stone.get("random_blades", 0)) * RANDOM_BLADE_COST
	for value in stone.get("shields", {}).values():
		total += float(value) * SHIELD_COST
	for value in stone.get("long_blades", {}).values():
		total += float(value) * LONG_BLADE_COST
	total += float(stone.get("power_cost", 0.0))
	return total
