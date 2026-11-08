## CampaignProgress.gd
## Progression sauvegardable de la campagne. La source de vérité est
## l'identifiant du nœud, jamais le dieu ni l'identifiant d'un ancien parcours.
## Aucune donnée de combat temporaire n'entre ici.
class_name CampaignProgress
extends RefCounted

const PROGRESS_VERSION: int = 1

var campaign_version: int = 0
var completed: Dictionary = {}
var attempts: Dictionary = {}
var last_selected: String = ""
var tutorial_states: Dictionary = {}
## Trace de migration : version convertie et statistiques non convertibles
## conservées telles quelles. Le profil d'origine n'est jamais modifié.
var migration: Dictionary = {}


static func from_dict(source: Dictionary) -> CampaignProgress:
	var progress := CampaignProgress.new()
	progress.campaign_version = int(source.get("campaign_version", 0))
	var raw_completed: Variant = source.get("completed_node_ids", [])
	if raw_completed is Array:
		for value in raw_completed:
			var node_id := str(value)
			if node_id != "":
				progress.completed[node_id] = true
	var raw_attempts: Variant = source.get("attempts_by_node", {})
	if raw_attempts is Dictionary:
		for key in raw_attempts:
			progress.attempts[str(key)] = maxi(0, int(raw_attempts[key]))
	progress.last_selected = str(source.get("last_selected_node_id", ""))
	var raw_tutorials: Variant = source.get("tutorial_states", {})
	if raw_tutorials is Dictionary:
		progress.tutorial_states = (raw_tutorials as Dictionary).duplicate(true)
	var raw_migration: Variant = source.get("legacy", {})
	if raw_migration is Dictionary:
		progress.migration = (raw_migration as Dictionary).duplicate(true)
	return progress


func to_dict() -> Dictionary:
	var ids: Array = completed.keys()
	ids.sort()
	return {
		"progress_version": PROGRESS_VERSION,
		"campaign_version": campaign_version,
		"completed_node_ids": ids,
		"attempts_by_node": attempts.duplicate(true),
		"last_selected_node_id": last_selected,
		"tutorial_states": tutorial_states.duplicate(true),
		"legacy": migration.duplicate(true),
	}


func duplicate_progress() -> CampaignProgress:
	return CampaignProgress.from_dict(to_dict())


func is_completed(node_id: String) -> bool:
	return completed.has(node_id)


func completed_ids() -> Array:
	var ids: Array = completed.keys()
	ids.sort()
	return ids


func completed_count() -> int:
	return completed.size()


## Renvoie true seulement si l'état a réellement changé. Le service écrit
## ensuite une copie complète : aucune progression n'est validée avant que le
## disque ait accepté la sauvegarde.
func mark_completed(node_id: String) -> bool:
	if node_id == "" or completed.has(node_id):
		return false
	completed[node_id] = true
	return true


func remove_completed(node_id: String) -> void:
	completed.erase(node_id)


func attempts_for(node_id: String) -> int:
	return int(attempts.get(node_id, 0))


## Incrémente et renvoie le numéro de la tentative qui va commencer.
func record_attempt(node_id: String) -> int:
	var next := attempts_for(node_id) + 1
	attempts[node_id] = next
	return next


func set_attempts(node_id: String, value: int) -> void:
	attempts[node_id] = maxi(0, value)


func set_last_selected(node_id: String) -> void:
	last_selected = node_id


func tutorial_state(tutorial_id: String) -> String:
	return str(tutorial_states.get(tutorial_id, "pending"))


func set_tutorial_state(tutorial_id: String, state: String) -> void:
	if tutorial_id == "":
		return
	tutorial_states[tutorial_id] = state


func migration_version() -> int:
	return int(migration.get("legacy_version", 0))


func set_migration_version(version: int) -> void:
	migration["legacy_version"] = version
