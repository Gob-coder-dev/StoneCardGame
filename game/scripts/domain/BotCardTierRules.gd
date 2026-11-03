## Puissance utilisée uniquement pour répartir les cartes dans les decks de bots.
class_name BotCardTierRules
extends RefCounted

const MIN_LEVEL_BY_RARITY := {
	"common": 1,
	"rare": 1,
	"epic": 3,
	"legendary": 4,
}


static func effective_level(rarity: String, form_level: int) -> int:
	return maxi(form_level, int(MIN_LEVEL_BY_RARITY.get(rarity, form_level)))
