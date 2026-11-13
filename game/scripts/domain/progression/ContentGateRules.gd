## Résolution pure des accès à partir des identifiants de niveaux terminés.
class_name ContentGateRules
extends RefCounted

const AccessState := preload("res://scripts/domain/progression/ContentAccessState.gd")


static func resolve(config: Dictionary, completed: Dictionary) -> ContentAccessState:
	var rarities := {}
	for value in config.get("default_rarities", []):
		rarities[str(value)] = true
	var gates := {}
	var revision := 0
	for raw in config.get("gates", []):
		if not raw is Dictionary:
			continue
		var gate: Dictionary = raw
		var required := str(gate.get("required_campaign_node", ""))
		if required == "" or not bool(completed.get(required, false)):
			continue
		var gate_id := str(gate.get("id", ""))
		if gate_id != "":
			gates[gate_id] = true
			revision += 1
		for rarity in gate.get("unlocked_rarities", []):
			rarities[str(rarity)] = true
	return AccessState.build(gates, rarities, revision)


static func gate(config: Dictionary, gate_id: String) -> Dictionary:
	for raw in config.get("gates", []):
		if raw is Dictionary and str(raw.get("id", "")) == gate_id:
			return (raw as Dictionary).duplicate(true)
	return {}
