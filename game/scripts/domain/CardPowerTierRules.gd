## CardPowerTierRules.gd
## Règle de domaine générale du palier de puissance d'une carte.
##
## Le palier de puissance n'est pas le niveau de forme : une carte de niveau N
## vaut N + offset de rareté. Une exception explicite `power_tier` dans les
## données remplace cette valeur calculée (cartes à puissance exceptionnelle).
##
## La règle est pure : elle ne lit ni scène, ni réseau, ni sauvegarde. Le
## catalogue peut l'appeler avec une définition déjà fusionnée par StoneLoader.
class_name CardPowerTierRules
extends RefCounted

const MIN_TIER: int = 1
const MAX_TIER: int = 4

## common : 0, rare : 1, epic : 2, legendary : 3.
const RARITY_OFFSET := {
	"common": 0,
	"rare": 1,
	"epic": 2,
	"legendary": 3,
}

const RARITIES: Array[String] = ["common", "rare", "epic", "legendary"]


static func rarity_offset(rarity: String) -> int:
	return int(RARITY_OFFSET.get(rarity.to_lower(), -1))


## Palier calculé par la formule par défaut, ou -1 pour une rareté/niveau
## inconnus. Le résultat n'est pas borné ici : la validation le signale.
static func computed_tier(rarity: String, form_level: int) -> int:
	var offset := rarity_offset(rarity)
	if offset < 0 or form_level < 1:
		return -1
	return form_level + offset


## Palier effectif : le champ explicite `power_tier` s'il est valide, sinon la
## formule rareté + niveau. Une valeur explicite invalide retombe sur la
## formule ; `tier_problem()` la refuse explicitement au validateur.
static func effective_tier(definition: Dictionary) -> int:
	var raw: Variant = definition.get("power_tier")
	if raw is int or raw is float:
		var declared := float(raw)
		if declared == floorf(declared) and declared >= MIN_TIER and declared <= MAX_TIER:
			return int(declared)
	return computed_tier(str(definition.get("rarity", "")), int(definition.get("level", 0)))


## Décrit pourquoi une définition ne respecte pas les bornes ou la formule.
## Chaîne vide si la définition est valide.
static func tier_problem(definition: Dictionary) -> String:
	var computed := computed_tier(str(definition.get("rarity", "")), int(definition.get("level", 0)))
	if computed < MIN_TIER or computed > MAX_TIER:
		return "palier de puissance calculé hors bornes sur '%s'." % str(definition.get("id", ""))
	var raw: Variant = definition.get("power_tier")
	if raw == null:
		return ""
	if not (raw is int or raw is float) or float(raw) != floorf(float(raw)):
		return "power_tier non entier sur '%s'." % str(definition.get("id", ""))
	var declared := int(raw)
	if declared < MIN_TIER or declared > MAX_TIER:
		return "power_tier hors bornes sur '%s'." % str(definition.get("id", ""))
	return ""


## Une carte est autorisée pour une limite N si son palier effectif est <= N.
static func is_allowed(definition: Dictionary, max_tier: int) -> bool:
	if max_tier < MIN_TIER or max_tier > MAX_TIER:
		return false
	if tier_problem(definition) != "":
		return false
	return effective_tier(definition) <= max_tier


## Vérifie une lignée complète : bornes, formule par défaut, cohérence des
## formes et absence de baisse de palier lors d'une évolution.
static func lineage_problems(lineage: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var lineage_id := str(lineage.get("id", ""))
	var rarity := str(lineage.get("rarity", ""))
	if rarity_offset(rarity) < 0:
		problems.append("rareté inconnue '%s' dans la lignée '%s'." % [rarity, lineage_id])
	var forms: Variant = lineage.get("levels")
	if not forms is Array:
		return problems
	var common := lineage.duplicate(true)
	common.erase("levels")
	var previous := 0
	for index in range((forms as Array).size()):
		var form: Variant = (forms as Array)[index]
		if not form is Dictionary:
			continue
		var definition := common.duplicate(true)
		definition.merge(form, true)
		# Le niveau et la rareté appartiennent à la lignée ; une forme ne les
		# redéfinit pas, mais le validateur les fournit à la règle pure.
		definition["rarity"] = rarity
		definition["level"] = index + 1
		var form_id := str(definition.get("id", ""))
		var problem := tier_problem(definition)
		if problem != "":
			problems.append("%s (%s)." % [problem, form_id])
			continue
		var tier := effective_tier(definition)
		if tier < previous:
			problems.append("le palier de '%s' baisse de %d à %d dans la lignée '%s'." % [
				form_id, previous, tier, lineage_id])
		previous = maxi(previous, tier)
		if not definition.has("power_tier") \
				and tier != computed_tier(rarity, index + 1):
			problems.append("palier incohérent avec la formule sur '%s'." % form_id)
	return problems
