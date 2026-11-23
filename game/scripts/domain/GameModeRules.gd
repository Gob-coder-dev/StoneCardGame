## Règles génériques des modes de jeu, partagées par la campagne et le PVP.
## Cette classe ne connaît ni salon, ni réseau, ni format de série.
class_name GameModeRules
extends RefCounted

const MODE_CLASSIC := "classic"
const MODE_RANDOM := "random"
const MODE_MIRROR := "mirror"
const MODE_DRAFT := "draft"
const MODES: Array[String] = [MODE_CLASSIC, MODE_RANDOM, MODE_MIRROR, MODE_DRAFT]
## Les noms décrivent la règle plutôt que de la nommer : « Classique » ou
## « Sélection » ne disent pas au joueur ce qu'il doit préparer.
const MODE_LABELS := {
	MODE_CLASSIC: "Duel classique",
	MODE_RANDOM: "Decks aléatoires",
	MODE_MIRROR: "Même deck",
	MODE_DRAFT: "Choix de cartes",
}
## Une phrase concrète accompagne chaque mode dans la fiche de campagne et le
## salon PVP. Le libellé seul reste affiché, mais ne porte jamais l'explication.
const MODE_DESCRIPTIONS := {
	MODE_CLASSIC: "Chacun joue son propre deck.",
	MODE_RANDOM: "Les deux decks sont générés au hasard.",
	MODE_MIRROR: "Les deux camps reçoivent un deck identique.",
	MODE_DRAFT: "Chacun compose son deck parmi une sélection de cartes.",
}
## Libellés des anciennes rencontres enregistrées. Ils ne sont plus affichés,
## mais la lecture d'une sauvegarde doit encore les reconnaître comme un mode.
const LEGACY_MODE_LABELS: Array[String] = ["Classique", "Aléatoire", "Miroir", "Sélection"]

const MIN_POWER_TIER := CardPowerTierRules.MIN_TIER
const MAX_POWER_TIER := CardPowerTierRules.MAX_TIER
const DEFAULT_POWER_TIER: int = MAX_POWER_TIER


static func mode_label(mode: String) -> String:
	return str(MODE_LABELS.get(mode, mode))


static func mode_description(mode: String) -> String:
	return str(MODE_DESCRIPTIONS.get(mode, ""))


static func is_mode_label(value: String) -> bool:
	return MODE_LABELS.values().has(value) or LEGACY_MODE_LABELS.has(value)


static func minimum_power_tier(mode: String) -> int:
	# Le draft public requiert seize lignées par dieu pour préparer huit paires.
	return 2 if mode == MODE_DRAFT else MIN_POWER_TIER


static func normalized(config: Dictionary) -> Dictionary:
	var mode := str(config.get("mode", MODE_CLASSIC))
	if not MODES.has(mode):
		mode = MODE_CLASSIC
	var tier := int(config.get("power_tier", DEFAULT_POWER_TIER))
	tier = clampi(tier, minimum_power_tier(mode), MAX_POWER_TIER)
	return {"mode": mode, "power_tier": tier}


static func validation_problem(config: Dictionary) -> String:
	var mode := str(config.get("mode", ""))
	if not MODES.has(mode):
		return "Mode de jeu inconnu."
	var tier := int(config.get("power_tier", -1))
	if tier < minimum_power_tier(mode) or tier > MAX_POWER_TIER:
		return "Limite de palier invalide."
	return ""


static func generates_loadout(mode: String) -> bool:
	return mode == MODE_RANDOM or mode == MODE_MIRROR


static func requires_draft(mode: String) -> bool:
	return mode == MODE_DRAFT


static func requires_preparation(mode: String) -> bool:
	return generates_loadout(mode) or requires_draft(mode)

