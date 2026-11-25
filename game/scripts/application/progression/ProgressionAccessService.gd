## Façade applicative des accès globaux. Elle traduit la progression de
## campagne en une projection stable consommée par l'économie et les quêtes.
class_name ProgressionAccessService
extends RefCounted

const Config := preload("res://scripts/data/progression/ContentGateConfig.gd")
const Rules := preload("res://scripts/domain/progression/ContentGateRules.gd")
const AccessState := preload("res://scripts/domain/progression/ContentAccessState.gd")

var _campaign_service: Variant = null


func _init(campaign_service: Variant = null) -> void:
	_campaign_service = campaign_service


func state(preview: bool = false) -> ContentAccessState:
	if preview and _campaign_service == null:
		return Rules.resolve(Config.get_config(), CampaignContext.preview_completed_nodes())
	var completed := {}
	var service: Variant = _campaign_service
	if service == null:
		service = CampaignContext.get_service()
	if service != null and service.has_method("is_ready") and service.is_ready():
		var progress: Variant = service.progress()
		if progress != null:
			completed = progress.completed.duplicate()
	return Rules.resolve(Config.get_config(), completed)


func is_gate_unlocked(gate_id: String) -> bool:
	return state().has_gate(gate_id)


func is_rarity_unlocked(rarity: String) -> bool:
	return state().allows_rarity(rarity)


func gate_definition(gate_id: String) -> Dictionary:
	return Rules.gate(Config.get_config(), gate_id)


func locked_reason(gate_id: String, access: ContentAccessState = null) -> String:
	if gate_id == "":
		return ""
	if access == null:
		access = state()
	if access.has_gate(gate_id):
		return ""
	var definition := gate_definition(gate_id)
	var label := str(definition.get("label", "ce contenu"))
	return "%s sera débloqué après un boss de campagne." % label
