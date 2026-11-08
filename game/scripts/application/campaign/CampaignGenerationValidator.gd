## CampaignGenerationValidator.gd
## Validation coûteuse des générations réelles de campagne. Elle appartient à
## l'application car elle orchestre ModePreparationService et LoadoutGenerator ;
## elle n'est exécutée que par les tests et les outils de livraison.
class_name CampaignGenerationValidator
extends RefCounted

const NodeModel := preload("res://scripts/domain/campaign/CampaignNode.gd")
const LoadoutGeneratorModel := preload("res://scripts/domain/LoadoutGenerator.gd")
const ModePreparationServiceModel := preload("res://scripts/application/ModePreparationService.gd")


static func problems(definition: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var version := int(definition.get("campaign_version", 0))
	var raw_nodes: Variant = definition.get("nodes", [])
	if not raw_nodes is Array:
		return result
	for raw in raw_nodes:
		if raw is Dictionary:
			_node_problems(NodeModel.from_dict(raw), version, result)
	return result


static func node_problems(node: CampaignNode, version: int) -> Array[String]:
	var result: Array[String] = []
	_node_problems(node, version, result)
	return result


static func _node_problems(node: CampaignNode, version: int,
		result: Array[String]) -> void:
	var mode := node.game_mode()
	var tier := node.max_power_tier()
	var seed := node.resolved_seed(version, 0)
	if mode == GameModeRules.MODE_RANDOM or mode == GameModeRules.MODE_MIRROR:
		var service := ModePreparationServiceModel.new()
		var prepared := service.prepare_immediate(mode, seed, tier, {}, {},
			node.generation_constraints())
		if not bool(prepared.get("ok", false)):
			result.append("génération impossible sur '%s' : %s." % [
				node.id, str(prepared.get("reason", ""))])
			return
		var minimum := node.generator_min_god_cards()
		var god_id := node.generator_god_id()
		if minimum > 0 and god_id != "":
			for key in ["loadout_one", "loadout_two"]:
				var loadout: GameLoadout = prepared.get(key) as GameLoadout
				if loadout == null or _god_card_count(loadout.deck, god_id) < minimum:
					result.append("génération de '%s' : minimum de %d cartes '%s' non respecté." % [
						node.id, minimum, god_id])
					return
		return
	if mode == GameModeRules.MODE_DRAFT:
		var opponent_god := node.fixed_god_id()
		if node.opponent_god_policy() == NodeModel.GOD_FIXED and opponent_god == "":
			result.append("Sélection '%s' : dieu adverse requis." % node.id)
			return
		var service := ModePreparationServiceModel.new()
		for god in StoneLoader.get_all_gods():
			var player_god := str(god.get("id", ""))
			var target_god := opponent_god if opponent_god != "" else player_god
			var created := service.create_draft(seed, tier,
				{"god_id": player_god}, {"god_id": target_god})
			if not bool(created.get("ok", false)):
				result.append("draft impossible sur '%s' pour le dieu '%s' : %s." % [
					node.id, player_god, str(created.get("reason", ""))])
				return
		return
	if node.opponent_deck_policy() != NodeModel.DECK_GENERATED:
		return
	var god_id := node.fixed_god_id()
	if node.opponent_god_policy() == NodeModel.GOD_FIXED and god_id != "":
		var generated := LoadoutGeneratorModel.new().generate_for_god(seed, god_id, tier)
		if not bool(generated.get("ok", false)):
			result.append("deck généré impossible sur '%s' : %s." % [
				node.id, str(generated.get("reason", ""))])
		return
	if node.opponent_god_policy() == NodeModel.GOD_PROFILE:
		var generator := LoadoutGeneratorModel.new()
		for god in StoneLoader.get_all_gods():
			var generated := generator.generate_for_god(seed, str(god.get("id", "")), tier)
			if not bool(generated.get("ok", false)):
				result.append("deck généré impossible sur '%s' pour '%s'." % [
					node.id, str(god.get("id", ""))])
				return


static func _god_card_count(deck: Array, god_id: String) -> int:
	var count := 0
	for stone_id in deck:
		if StoneLoader.stone_affinity(str(stone_id)) == god_id:
			count += 1
	return count
