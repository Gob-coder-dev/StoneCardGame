## Budget d'une définition de carte, indépendant du chargement et de l'interface.
class_name StoneCostRules
extends RefCounted

const NORMAL_BLADE_COST := 1.0
const RANDOM_BLADE_COST := 0.5
const SHIELD_COST := 0.5
## Tout pouvoir de famille fiable vaut un point fixe, quel que soit son dieu.
## Les cartes pile ou face reçoivent au contraire une réduction : leur
## orientation est inconnue quand le joueur choisit son placement.
const FAMILY_POWER_COST := 1.0
const COIN_FLIP_DISCOUNT := 1.0
## Une lame longue reste une lame en combat rapproché et gagne une attaque
## de ligne : son coût est volontairement supérieur à une lame normale.
## Ramené de 1,5 à 1,25 après le tournoi d'équilibrage des dieux (Horizon à 41 %).
const LONG_BLADE_COST := 1.25

## Le système ne produit que des quarts de point. Les comparaisons de budget
## passent par cet entier : deux coûts égaux restent exactement égaux, sans
## jamais comparer deux flottants.
const COST_SCALE: int = 4


static func cost_quarters(stone: Dictionary) -> int:
	return int(roundf(cost(stone) * float(COST_SCALE)))


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
	if _has_family_power(stone):
		total += FAMILY_POWER_COST
	if not str(stone.get("coin_flip", "")).is_empty():
		total -= COIN_FLIP_DISCOUNT
	return maxf(0.0, total)


## Les symboles spéciaux et les effets sont les seuls pouvoirs facturés.
## Une carte neutre ou une carte de famille composée uniquement de lames
## normales ne paie aucun supplément arbitraire.
static func _has_family_power(stone: Dictionary) -> bool:
	if int(stone.get("random_blades", 0)) > 0:
		return true
	var effects: Array = stone.get("effects", [])
	if not effects.is_empty():
		return true
	for field in ["shields", "long_blades"]:
		for value in stone.get(field, {}).values():
			if int(value) > 0:
				return true
	return false
