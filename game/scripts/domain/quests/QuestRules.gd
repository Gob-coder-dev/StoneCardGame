## QuestRules.gd
## Règles pures d'une quête : paliers cumulatifs, prochain palier et récompense.
## Aucun accès au profil, au catalogue de contenu ni à une scène.
class_name QuestRules
extends RefCounted


static func tiers(definition: Dictionary) -> Array:
	var raw: Variant = definition.get("tiers", [])
	return raw if raw is Array else []


static func threshold(definition: Dictionary, tier: int) -> int:
	var values := tiers(definition)
	if tier < 0 or tier >= values.size() or not values[tier] is Dictionary:
		return 0
	var value: Dictionary = values[tier]
	return maxi(0, int(value.get("threshold", 0)))


## Un palier peut payer en âmes, en bougies, en copies de cartes ou avec un
## Rituel offert. Les cartes restent des données : le service les résout ensuite.
static func reward(definition: Dictionary, tier: int, bonus_candles: int = 0) -> Dictionary:
	var values := tiers(definition)
	var souls := 0
	var candles := 0
	var cards: Array = []
	var ritual := ""
	if tier >= 0 and tier < values.size() and values[tier] is Dictionary:
		var value: Dictionary = values[tier]
		souls = maxi(0, int(value.get("souls", 0)))
		candles = maxi(0, int(value.get("candles", 0)))
		cards = _cards(value)
		ritual = str(value.get("ritual", ""))
	return {"souls": souls, "candles": candles + maxi(0, bonus_candles),
		"cards": cards, "ritual": ritual}


static func _cards(value: Dictionary) -> Array:
	var result: Array = []
	var raw: Variant = value.get("cards", [])
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				result.append((entry as Dictionary).duplicate(true))
	return result


## Nombre de paliers atteints mais pas encore réclamés, dans l'ordre croissant.
## Un compteur qui dépasse plusieurs seuils laisse donc plusieurs récoltes.
static func claimable_count(definition: Dictionary, claimed: int, value: int) -> int:
	var values := tiers(definition)
	var count := 0
	var index := maxi(0, claimed)
	while index < values.size():
		if value < threshold(definition, index):
			break
		count += 1
		index += 1
	return count


static func next_tier(definition: Dictionary, claimed: int) -> int:
	return claimed if claimed >= 0 and claimed < tiers(definition).size() else -1
