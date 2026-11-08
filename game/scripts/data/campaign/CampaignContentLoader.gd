## CampaignContentLoader.gd
## Charge la définition consolidée de la campagne. Un fichier unique reste la
## forme normale ; si `regions` est déclaré, chaque région apporte ses nœuds et
## ses arêtes et le chargeur produit une seule définition, sans dupliquer les
## identifiants de campagne ni les règles.
class_name CampaignContentLoader
extends RefCounted

const DEFAULT_PATH := "res://data/campaign/campaign_v2.json"
const REGION_DIR := "res://data/campaign/"
const ValidatorModel := preload("res://scripts/domain/campaign/CampaignValidator.gd")


static func read(path: String = DEFAULT_PATH) -> Dictionary:
	var parsed: Variant = _parse(path)
	if not parsed is Dictionary:
		return {
			"ok": false,
			"definition": {},
			"problems": ["Campagne illisible ou JSON invalide : %s." % path],
		}
	var definition: Dictionary = (parsed as Dictionary).duplicate(true)
	var problems: Array[String] = []
	var raw_regions: Variant = definition.get("regions", [])
	if raw_regions is Array and not (raw_regions as Array).is_empty():
		var nodes: Array = []
		var edges: Array = []
		for raw_region in raw_regions:
			var region_name := str(raw_region)
			var region_path := region_name if region_name.begins_with("res://") \
				else REGION_DIR + region_name
			var region: Variant = _parse(region_path)
			if not region is Dictionary:
				problems.append("Région de campagne illisible : %s." % region_path)
				continue
			var region_nodes: Variant = (region as Dictionary).get("nodes", [])
			var region_edges: Variant = (region as Dictionary).get("edges", [])
			if not region_nodes is Array or not region_edges is Array:
				problems.append("Région sans tableaux nodes/edges : %s." % region_path)
				continue
			nodes.append_array(region_nodes)
			edges.append_array(region_edges)
		definition["nodes"] = nodes
		definition["edges"] = edges
	problems.append_array(ValidatorModel.problems(definition))
	return {
		"ok": problems.is_empty(),
		"definition": definition,
		"problems": problems,
	}


static func _parse(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
