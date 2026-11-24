## CampaignSaveMigration.gd
## Migration paresseuse et idempotente de l'ancienne progression par adversaire.
## La conversion lit une copie des anciens compteurs. Le service les retire
## ensuite du profil après sauvegarde de la campagne. Les victoires ambiguës
## sont archivées dans ce fichier au lieu d'être devinées.
class_name CampaignSaveMigration
extends RefCounted

const Integer := preload("res://scripts/domain/IntegerValue.gd")
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
		var legacy_id := legacy_opponent_id(node)
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
		var wins := Integer.read(entry.get("wins")) if entry is Dictionary else 0
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
		if entry is Dictionary and Integer.read(entry.get("wins")) > 0:
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

## Reconstruction réservée à la conversion des anciennes sauvegardes.
static func legacy_opponent_id(node: CampaignNode) -> String:
	if node == null or node.game_mode() != GameModeRules.MODE_CLASSIC:
		return ""
	var declared := node.declared_legacy_opponent_id()
	if declared != "":
		return declared
	if node.opponent_god_policy() != CampaignNode.GOD_FIXED:
		return ""
	var difficulty := _legacy_difficulty(node.ai_profile())
	if difficulty == "":
		return ""
	var bracket := _legacy_bracket(node.max_power_tier())
	if node.fixed_god_id() == "":
		return "bot_pr_stone_%s_%s" % [bracket, difficulty]
	return "bot_%s_%s_%s" % [node.fixed_god_id(), bracket, difficulty]


static func _legacy_bracket(tier: int) -> String:
	if tier <= 1:
		return "n1"
	if tier == 2:
		return "n2"
	return "n34"


static func _legacy_difficulty(ai: Dictionary) -> String:
	var precision := float(ai.get("precision", -1.0))
	var anticipation := bool(ai.get("anticipation", false))
	if is_equal_approx(precision, 0.0) and not anticipation:
		return "tres_facile"
	if is_equal_approx(precision, 0.25) and not anticipation:
		return "facile"
	if is_equal_approx(precision, 0.5) and not anticipation:
		return "moyen"
	if is_equal_approx(precision, 0.75) and not anticipation:
		return "difficile"
	if is_equal_approx(precision, 1.0) and anticipation:
		return "tres_difficile"
	return ""
