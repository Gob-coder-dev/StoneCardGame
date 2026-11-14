## Persiste un résultat immuable par étapes reprenables : profil, récompense,
## progression et quêtes. Une étape réussie n'est pas rejouée lors d'un réessai
## dans la session courante.
## Le contexte d'écran ne possède ni transaction ni décision de récompense.
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
var _stats_saved := false
var _reward_saved := false
var _completion_saved := false
var _quests_saved := false
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
		_attempt = maxi(1, service.progress().attempts_for(node_id))


func persist() -> Error:
	if _node_id != "" and (_service == null or not _service.has_node(_node_id)):
		return ERR_UNCONFIGURED
	if not _stats_saved:
		var error := PlayerData.record_game(str(_result["npc_id"]), int(_result["winner"]),
			int(_result["score_local"]), int(_result["score_opponent"]), int(_result["captures"]))
		if error != OK:
			return error
		_stats_saved = true
	if _node_id == "":
		return OK
	if bool(_result.get("campaign_victory", false)):
		var error := _persist_victory()
		if error != OK:
			return error
	if not _quests_saved:
		var error: Error = _record_quest.call("campaign_result", _quest_payload(), _quest_key())
		if error != OK:
			return error
		_quests_saved = true
	return OK


func _persist_victory() -> Error:
	if not _reward_saved:
		var granted := Reward.apply_victory(_service, _node_id, _first_victory, _attempt)
		if not bool(granted.get("ok", false)):
			return int(granted.get("error", ERR_FILE_CANT_WRITE)) as Error
		reward = granted.duplicate(true)
		_reward_saved = true
	if not _completion_saved:
		var completion := Completion.apply_victory(_service, _node_id)
		var error := int(completion.get("error", OK)) as Error
		if error != OK:
			return error
		_completion_saved = true
		if bool(completion.get("applied", false)):
			reward["unlocks"] = _content_unlocks()
	return OK


func _quest_key() -> String:
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
