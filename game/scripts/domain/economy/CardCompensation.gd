## CardCompensation.gd
## Valeur en âmes d'un lot de copies lorsque la lignée est déjà au niveau
## maximal. Partagée par les Rituels et les quêtes : une seule règle.
extends RefCounted

const EconomyConfigModel := preload("res://scripts/data/economy/EconomyConfig.gd")


## Même barème que les Rituels : la moitié du prix unitaire de la rareté.
static func souls_for(lineage_id: String, copies: int) -> int:
	var stone_id := StoneLoader.variant_id(lineage_id, 1)
	var rarity := StoneLoader.stone_rarity(stone_id)
	var rule: Dictionary = EconomyConfigModel.get_config().get("shop", {}).get(rarity, {})
	var unit_price := int(rule.get("fixed_price", 0))
	if unit_price <= 0:
		unit_price = int(rule.get("souls_per_copy", 0))
	return int(ceil(float(maxi(0, copies) * maxi(0, unit_price)) * 0.5))
