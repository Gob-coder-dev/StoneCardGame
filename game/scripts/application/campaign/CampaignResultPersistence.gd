## Le profil enregistre d'un seul coup la manche, ses gains et le reçu à reprendre.
## La progression et les quêtes sont rejouables après redémarrage grâce à ce reçu.
extends RefCounted

const Reward := preload("res://scripts/application/campaign/CampaignRewardService.gd")
const Completion := preload("res://scripts/application/campaign/CampaignCompletionService.gd")
const Quests := preload("res://scripts/application/quests/QuestService.gd")
const Gates := preload("res://scripts/data/progression/ContentGateConfig.gd")

var reward: Dictionary = {}
var _result: Dictionary
var _service: CampaignService
var _node_id: String
var _first_victory := false
var _attempt := 1
var _finished := false
var _record_quest: Callable
var _quest_service := Quests.new()


func _init(result: Dictionary, service: CampaignService, node_id: String,
		quest_recorder: Callable = Callable()) -> void:
	_result = result.duplicate(true)
	_service = service
	_node_id = node_id
	_record_quest = quest_recorder if quest_recorder.is_valid() else _quest_service.record_event
	if service != null and service.has_node(node_id):
		_first_victory = not service.is_completed(node_id)
		_attempt = maxi(1, service.attempts_for(node_id))


func persist() -> Error:
	if _finished:
		return OK
	var error := PlayerData.record_match(_result) if _node_id == "" else _persist_campaign()
	_finished = error == OK
	return error


func _persist_campaign() -> Error:
	var error := _check_storage(_service, _node_id)
	if error != OK:
		return error
	var key := _result_key()
	var pending := PlayerData.pending_campaign_result()
	if pending.is_empty():
		error = _stage_result(key)
		if error != OK:
			return error
		pending = PlayerData.pending_campaign_result()
	elif pending.get("key") != key:
		return ERR_BUSY
	var receipt: Variant = pending.get("reward", {})
	if not receipt is Dictionary:
		return ERR_INVALID_DATA
	reward = receipt.duplicate(true)
	error = _finish_pending(_service, pending, _record_quest)
	if bool(reward.get("first_victory", false)) and _service.is_completed(_node_id):
		reward["unlocks"] = _content_unlocks()
	return error


func _stage_result(key: String) -> Error:
	var prepared: Dictionary
	if bool(_result.get("campaign_victory", false)):
		prepared = Reward.prepare_victory(_service, _node_id, _first_victory, _attempt)
		if not prepared["ok"]:
			return int(prepared.get("error", ERR_INVALID_DATA)) as Error
	else:
		prepared = {"inventory": null, "deck_override": null, "receipt": {}}
	var pending := {"key": key, "node_id": _node_id, "result": _quest_payload(),
		"reward": prepared["receipt"]}
	return PlayerData.stage_campaign_result(pending, prepared["inventory"], prepared["deck_override"])


static func resume_pending(service: CampaignService) -> Error:
	var pending := PlayerData.pending_campaign_result()
	if pending.is_empty():
		return OK
	var error := _check_storage(service, str(pending.get("node_id", "")))
	if error != OK:
		return error
	var quests := Quests.new()
	return _finish_pending(service, pending, quests.record_event)


static func _check_storage(service: CampaignService, node_id: String) -> Error:
	if PlayerData.profile_load_error != OK:
		return PlayerData.profile_load_error
	if service == null:
		return ERR_UNCONFIGURED
	if not service.is_ready():
		return service.load_error() if service.load_error() != OK else ERR_INVALID_DATA
	if not service.has_node(node_id):
		return ERR_DOES_NOT_EXIST
	return service.storage_error()


static func _finish_pending(service: CampaignService, pending: Dictionary, record_quest: Callable) -> Error:
	var key: Variant = pending.get("key")
	var result: Variant = pending.get("result")
	if not key is String or key.is_empty() or not result is Dictionary:
		return ERR_INVALID_DATA
	if bool(result.get("campaign_victory", false)):
		var completion := Completion.apply_victory(service, pending["node_id"])
		var error := int(completion.get("error", OK)) as Error
		if error != OK:
			return error
	var quest_error: Error = record_quest.call("campaign_result", result, key)
	if quest_error != OK:
		return quest_error
	return PlayerData.finish_campaign_result(key)


func _result_key() -> String:
	return "campaign:%d:%s:%d:%d" % [_service.graph().campaign_version,
		_node_id, _attempt, int(_result.get("round_index", 1))]


func _quest_payload() -> Dictionary:
	var payload := _result.duplicate(true)
	var node := _service.node(_node_id)
	payload["boss"] = node.is_boss() or node.is_mini_boss()
	payload["tutorial"] = _node_id.begins_with("tuto_")
	payload["series_complete"] = bool(_result.get("campaign_victory", false))
	return payload


func _content_unlocks() -> Array:
	var result: Array = []
	for raw in Gates.get_config().get("gates", []):
		if raw is Dictionary and str(raw.get("required_campaign_node", "")) == _node_id:
			result.append({"id": str(raw.get("id", "")), "label": str(raw.get("label", "")),
				"message": str(raw.get("unlock_message", ""))})
	return result
