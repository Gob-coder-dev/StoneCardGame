## Contrôles de livraison de la courbe globale. Ces règles ne sont pas
## exécutées à chaque ouverture de la carte : elles protègent le contenu
## compilé pendant les audits et la suite de tests.
class_name CampaignProgressionValidator
extends RefCounted

const GateConfig := preload("res://scripts/data/progression/ContentGateConfig.gd")
const BalanceConfig := preload("res://scripts/data/campaign/CampaignBalanceConfig.gd")
const NodeModel := preload("res://scripts/domain/campaign/CampaignNode.gd")

const PRE_EPIC_STAGES := ["tutorial", "initiation", "early_game", "pre_epic"]
const PRE_LEGENDARY_STAGES := ["epic_intro", "epic_game", "pre_legendary"]


static func problems(definition: Dictionary) -> Array[String]:
	var result: Array[String] = []
	result.append_array(GateConfig.problems())
	result.append_array(BalanceConfig.problems())
	var nodes := {}
	for raw in definition.get("nodes", []):
		if raw is Dictionary:
			var node := NodeModel.from_dict(raw)
			nodes[node.id] = node
			_node_problems(node, result)
	var outgoing := _outgoing(definition.get("edges", []))
	var incoming := _incoming(definition.get("edges", []))
	var start := str(definition.get("start_node_id", ""))
	var final_node := str(definition.get("final_node_id", ""))
	for raw_gate in GateConfig.get_config().get("gates", []):
		if not raw_gate is Dictionary:
			continue
		var gate_id := str(raw_gate.get("required_campaign_node", ""))
		if not nodes.has(gate_id):
			result.append("Jalon de campagne absent : %s." % gate_id)
			continue
		var gate: CampaignNode = nodes[gate_id]
		if not gate.is_mandatory_mini_boss() and not gate.is_boss():
			result.append("Le jalon '%s' doit être un boss obligatoire." % gate_id)
		if _reachable(start, final_node, outgoing, gate_id):
			result.append("Le jalon '%s' peut être contourné." % gate_id)
	_boss_curve_problems(nodes, incoming, result)
	return result


static func _node_problems(node: CampaignNode, result: Array[String]) -> void:
	if node.stage_id == "":
		result.append("Étape d'équilibrage absente sur '%s'." % node.id)
	if node.balance_profile == "":
		result.append("Profil d'équilibrage absent sur '%s'." % node.id)
	if PRE_EPIC_STAGES.has(node.stage_id) and node.max_power_tier() > 2:
		result.append("Palier 3 trop précoce sur '%s'." % node.id)
	elif PRE_LEGENDARY_STAGES.has(node.stage_id) and node.max_power_tier() > 3:
		result.append("Palier 4 trop précoce sur '%s'." % node.id)
	if (node.is_mini_boss() or node.is_boss()) \
			and node.series_format() == SeriesRules.SERIES_FT1:
		result.append("Boss '%s' encore configuré en FT1." % node.id)
	var precision := float(node.ai_profile().get("precision", -1.0))
	if precision < 0.0 or precision > 1.0:
		result.append("Précision invalide sur '%s'." % node.id)
	var profile := BalanceConfig.chapter(node.chapter)
	if profile.is_empty():
		result.append("Chapitre sans profil sur '%s'." % node.id)
		return
	if node.stage_id != str(profile.get("stage_id", "")):
		result.append("Étape incohérente sur '%s'." % node.id)
	if not (profile.get("allowed_modes", []) as Array).has(node.game_mode()):
		result.append("Mode trop précoce sur '%s'." % node.id)
	var minimum := float(profile.get("precision_min", 0.0))
	var limit := float(profile.get("challenge_precision_max", 1.0)) \
		if node.balance_profile in ["challenge", "required_boss", "boss"] \
		else float(profile.get("precision_max", 1.0))
	if precision < minimum - 0.001 or precision > limit + 0.001:
		result.append("Précision hors profil sur '%s'." % node.id)
	var tier_min := int(profile.get("tier_min", 1))
	var tier_max := int(profile.get("tier_max", 4))
	if node.max_power_tier() < tier_min or node.max_power_tier() > tier_max:
		result.append("Palier hors profil sur '%s'." % node.id)


static func _outgoing(raw_edges: Variant) -> Dictionary:
	var result := {}
	if not raw_edges is Array:
		return result
	for raw in raw_edges:
		if not raw is Dictionary:
			continue
		var source := str(raw.get("from", ""))
		var target := str(raw.get("to", ""))
		if not result.has(source):
			result[source] = []
		(result[source] as Array).append(target)
	return result


static func _incoming(raw_edges: Variant) -> Dictionary:
	var result := {}
	if not raw_edges is Array:
		return result
	for raw in raw_edges:
		if not raw is Dictionary:
			continue
		var source := str(raw.get("from", ""))
		var target := str(raw.get("to", ""))
		if not result.has(target):
			result[target] = []
		(result[target] as Array).append(source)
	return result


static func _boss_curve_problems(nodes: Dictionary, incoming: Dictionary,
		result: Array[String]) -> void:
	var required_gap := float(
		BalanceConfig.get_config().get("required_boss_precision_gap", 0.06))
	for node_id in nodes:
		var boss: CampaignNode = nodes[node_id]
		if not boss.is_mandatory_mini_boss() and not boss.is_boss():
			continue
		for raw_parent_id in incoming.get(node_id, []):
			var parent_id := str(raw_parent_id)
			if not nodes.has(parent_id):
				continue
			var parent: CampaignNode = nodes[parent_id]
			var boss_precision := float(boss.ai_profile().get("precision", 0.0))
			var parent_precision := float(parent.ai_profile().get("precision", 0.0))
			if boss_precision + 0.001 < parent_precision + required_gap:
				result.append("Boss '%s' moins exigeant que son approche '%s'." % [
					boss.id, parent.id])
			if boss.max_power_tier() < parent.max_power_tier():
				result.append("Boss '%s' d'un palier inferieur a son approche '%s'." % [
					boss.id, parent.id])
			if parent.balance_profile != "boss_approach":
				result.append("Approche de boss non identifiee sur '%s'." % parent.id)


static func _reachable(start: String, target: String, outgoing: Dictionary,
		blocked: String) -> bool:
	if start == blocked or target == blocked:
		return false
	var pending: Array[String] = [start]
	var visited := {}
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if current == target:
			return true
		if current == blocked or visited.has(current):
			continue
		visited[current] = true
		for raw_next in outgoing.get(current, []):
			var next := str(raw_next)
			if next != blocked and not visited.has(next):
				pending.append(next)
	return false
