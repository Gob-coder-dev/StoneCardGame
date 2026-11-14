## CampaignContentLoader.gd
## Charge la définition consolidée de la campagne. Un fichier unique reste la
## forme normale ; si `regions` est déclaré, chaque région apporte ses nœuds et
## ses arêtes et le chargeur produit une seule définition, sans dupliquer les
## identifiants de campagne ni les règles.
class_name CampaignContentLoader
extends RefCounted

const Json := preload("res://scripts/data/JsonFile.gd")

const DEFAULT_PATH := "res://data/campaign/campaign_v2.json"
const REGION_DIR := "res://data/campaign/"
const ValidatorModel := preload("res://scripts/domain/campaign/CampaignValidator.gd")
const GenerationValidatorModel := preload("res://scripts/application/campaign/CampaignGenerationValidator.gd")
const ProgressionValidatorModel := preload("res://scripts/application/campaign/CampaignProgressionValidator.gd")
const LayoutValidatorModel := preload("res://scripts/data/campaign/CampaignLayoutValidator.gd")
const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")


## `validate_delivery` active les contrôles complets de livraison : génération
## réelle des rencontres et géométrie de la carte. Le runtime le laisse faux :
## préparer tous les drafts à chaque ouverture bloquait la carte plusieurs
## secondes, alors que la suite de tests couvre déjà ce même contenu.
static func read(path: String = DEFAULT_PATH,
		validate_delivery: bool = false) -> Dictionary:
	var parsed: Variant = Json.read(path)
	if not parsed is Dictionary:
		return {
			"ok": false,
			"definition": {},
			"problems": ["Campagne illisible ou JSON invalide : %s." % path],
		}
	# Le JSON produit déjà une structure neuve ; le validateur ne la modifie
	# jamais. Éviter la copie profonde des 162 nœuds raccourcit l'ouverture.
	var definition: Dictionary = parsed
	var problems: Array[String] = []
	var raw_regions: Variant = definition.get("regions", [])
	if raw_regions is Array and not (raw_regions as Array).is_empty():
		var nodes: Array = []
		var edges: Array = []
		for raw_region in raw_regions:
			var region_name := str(raw_region)
			var region_path := region_name if region_name.begins_with("res://") \
				else REGION_DIR + region_name
			var region: Variant = Json.read(region_path)
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
	if validate_delivery and problems.is_empty():
		problems.append_array(ProgressionValidatorModel.problems(definition))
		problems.append_array(GenerationValidatorModel.problems(definition))
		problems.append_array(LayoutValidatorModel.problems(GraphModel.build(definition)))
	return {
		"ok": problems.is_empty(),
		"definition": definition,
		"problems": problems,
	}
