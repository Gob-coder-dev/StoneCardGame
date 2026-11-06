## BotCardTierRules.gd
## Règle **historique des paliers de bots**, distincte du palier de puissance
## des cartes. Elle ne définit pas une seconde progression de puissance : elle
## conserve le placement des decks de campagne existants (épiques au palier 3,
## légendaires au palier 4). La formule de puissance vit uniquement dans
## CardPowerTierRules, que le PVP et la future campagne utilisent.
class_name BotCardTierRules
extends RefCounted

## Plancher de niveau effectif utilisé uniquement pour les rencontres.
## Rare reste à 1, épique et légendaire rejoignent leur palier de puissance
## d'entrée (3 et 4). Ce n'est pas `power_tier` : ne pas réutiliser cette
## valeur pour filtrer un deck joueur.
const MIN_LEVEL_BY_RARITY := {
	"common": 1,
	"rare": 1,
	"epic": 3,
	"legendary": 4,
}


static func effective_level(rarity: String, form_level: int) -> int:
	return maxi(form_level, int(MIN_LEVEL_BY_RARITY.get(rarity, form_level)))
