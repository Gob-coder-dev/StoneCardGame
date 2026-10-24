## Règles pures des niveaux. Les statistiques de chaque forme restent dans le catalogue.
class_name StoneEvolutionRules
extends RefCounted

const MAX_PREVIEW_LEVEL := 4
const LEVELS_BY_RARITY := {"common": 4, "rare": 3, "epic": 2, "legendary": 1}

static func max_level(rarity: String) -> int:
	return int(LEVELS_BY_RARITY.get(rarity, 0))

static func is_valid_level(level: int, maximum: int) -> bool:
	return level >= 1 and level <= maximum

## La saturation est réservée aux aperçus ; une écriture doit être validée strictement.
static func preview_level(requested: int, maximum: int) -> int:
	return clampi(requested, 1, maxi(1, maximum))
