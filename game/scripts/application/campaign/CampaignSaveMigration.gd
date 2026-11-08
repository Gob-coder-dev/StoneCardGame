## CampaignSaveMigration.gd
## Migration paresseuse et idempotente de l'ancienne progression par adversaire.
## Elle ne modifie jamais PlayerData : les statistiques d'origine restent la
## source historique, et les victoires ambiguës sont archivées dans le fichier
## de campagne au lieu d'être devinées.
class_name CampaignSaveMigration
extends RefCounted

const FactoryModel := preload("res://scripts/application/campaign/CampaignEncounterFactory.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")


static func migrate(graph: CampaignGraph, legacy_stats: Dictionary,
		progress: CampaignProgress) -> Dictionary:
	if graph == null or progress == null:
		return {"changed": false, "converted": [], "archived": {},
			"path_nodes_completed": [], "progress": progress}
	var version := graph.campaign_version
	if version <= 0 or progress.migration_version() >= version:
		return {"changed": false, "converted": [], "archived": {},
			"path_nodes_completed": [], "progress": progress}

	var claims := {}
	for node in graph.nodes():
		var legacy_id := FactoryModel.legacy_opponent_id(node)
		if legacy_id == "":
			continue
		if not claims.has(legacy_id):
			claims[legacy_id] = []
		(claims[legacy_id] as Array).append(node.id)

	var per_npc: Dictionary = {}
	if legacy_stats.get("per_npc") is Dictionary:
		per_npc = legacy_stats["per_npc"]
	var converted: Array = []
	var archived := {}
	for legacy_id in claims:
		var entry: Variant = per_npc.get(legacy_id, {})
		var wins := int(entry.get("wins", 0)) if entry is Dictionary else 0
		if wins <= 0:
			continue
		var node_ids: Array = claims[legacy_id]
		if node_ids.size() == 1:
			var node_id := str(node_ids[0])
			if progress.mark_completed(node_id):
				converted.append(node_id)
		else:
			# Plusieurs nœuds partagent cette rencontre : le profil ne permet pas
			# de savoir lequel a été gagné. On archive sans choisir à sa place.
			archived[str(legacy_id)] = (entry as Dictionary).duplicate(true)

	for legacy_id in per_npc:
		if claims.has(str(legacy_id)):
			continue
		var entry: Variant = per_npc[legacy_id]
		if entry is Dictionary and int(entry.get("wins", 0)) > 0:
			archived[str(legacy_id)] = (entry as Dictionary).duplicate(true)

	# Une ancienne sauvegarde peut avoir terminé un mini-boss facultatif avant
	# que ses niveaux d'approche existent. Ils font partie de la même branche :
	# les marquer évite de rejouer une impasse déjà vaincue.
	var path_nodes_completed := _complete_optional_paths(graph, progress)

	progress.campaign_version = version
	progress.migration["legacy_version"] = version
	progress.migration["archived_stats"] = archived
	return {
		"changed": true,
		"converted": converted,
		"archived": archived,
		"path_nodes_completed": path_nodes_completed,
		"progress": progress,
	}


static func _complete_optional_paths(graph: CampaignGraph,
		progress: CampaignProgress) -> Array[String]:
	var completed_paths: Array[String] = []
	for boss in graph.nodes():
		if not boss.is_optional_mini_boss() or not progress.is_completed(boss.id):
			continue
		var prefix: String = str(boss.id) + "_path_"
		for node in graph.nodes():
			if node.id.begins_with(prefix) and progress.mark_completed(node.id):
				completed_paths.append(node.id)
	return completed_paths
