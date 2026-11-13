## Contrats des jalons globaux : les raretes, Rituels et validateurs partagent
## la meme projection issue de la progression de campagne.
extends "res://tests/support/CombatTestSuite.gd"

const GateConfig := preload("res://scripts/data/progression/ContentGateConfig.gd")
const GateRules := preload("res://scripts/domain/progression/ContentGateRules.gd")
const RitualConfigModel := preload("res://scripts/data/economy/RitualConfig.gd")
const RitualRules := preload("res://scripts/domain/economy/RitualAccessRules.gd")
const ContentLoader := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const ProgressionValidator := preload("res://scripts/application/campaign/CampaignProgressionValidator.gd")


func run() -> void:
	var config := GateConfig.get_config()
	_check(GateConfig.problems(config).is_empty(),
		"progression : les jalons globaux sont valides")
	var initial := GateRules.resolve(config, {})
	var epic := GateRules.resolve(config, {"r04_gate": true})
	var legendary := GateRules.resolve(config, {"r04_gate": true, "r07_gate": true})
	_check(initial.rarities() == ["common", "rare"] and initial.revision == 0,
		"progression : le nouveau joueur ne voit que communes et rares")
	_check(epic.rarities() == ["common", "rare", "epic"] and epic.revision == 1,
		"progression : la Porte des Fontes ouvre les cartes epiques")
	_check(legendary.rarities() == ["common", "rare", "epic", "legendary"] \
		and legendary.revision == 2,
		"progression : la Cloche de Seve ouvre les cartes legendaires")

	var small_initial := RitualRules.resolve(RitualConfigModel.definition("small"), initial)
	var small_epic := RitualRules.resolve(RitualConfigModel.definition("small"), epic)
	var basic_epic := RitualRules.resolve(RitualConfigModel.definition("basic"), epic)
	var basic_legendary := RitualRules.resolve(
		RitualConfigModel.definition("basic"), legendary)
	var grand_initial := RitualRules.resolve(RitualConfigModel.definition("grand"), initial)
	var grand_legendary := RitualRules.resolve(
		RitualConfigModel.definition("grand"), legendary)
	_check(_rarities(small_initial.get("lucky", [])) == ["common", "rare", "rare"] \
		and _rarities(small_epic.get("lucky", [])) == ["common", "rare", "epic"],
		"progression : le Petit rituel remplace l'epique tant que son jalon est ferme")
	_check(bool(basic_epic.get("available", false)) \
		and not _rarities(basic_epic.get("lucky", [])).has("legendary") \
		and _rarities(basic_legendary.get("lucky", [])).has("legendary"),
		"progression : le Rituel basique suit les deux jalons")
	_check(not bool(grand_initial.get("available", true)) \
		and bool(grand_legendary.get("available", false)),
		"progression : le Grand rituel attend les legendaires")

	var content := ContentLoader.read()
	_check(bool(content.get("ok", false)) \
		and ProgressionValidator.problems(content.get("definition", {})).is_empty(),
		"progression : les deux boss-jalons sont incontournables et la courbe est valide")


static func _rarities(groups: Variant) -> Array[String]:
	var result: Array[String] = []
	if groups is Array:
		for raw in groups:
			if not raw is Dictionary:
				continue
			for _index in range(int(raw.get("slots", 0))):
				result.append(str(raw.get("rarity", "")))
	return result
