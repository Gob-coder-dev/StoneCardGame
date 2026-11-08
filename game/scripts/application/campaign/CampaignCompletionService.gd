## CampaignCompletionService.gd
## Applique une victoire une seule fois et ne confirme le déblocage qu'après le
## succès de la sauvegarde. Le service de carte reste propriétaire de l'état.
class_name CampaignCompletionService
extends RefCounted


static func apply_victory(service: CampaignService, node_id: String) -> Dictionary:
	if service == null:
		return {"applied": false, "error": ERR_UNCONFIGURED,
			"reason": "Service de campagne absent."}
	if not service.has_node(node_id):
		return {"applied": false, "error": ERR_DOES_NOT_EXIST,
			"reason": "Nœud de campagne inconnu."}
	if service.is_completed(node_id):
		return {"applied": false, "error": OK, "reason": ""}
	var error := service.complete_node(node_id)
	return {
		"applied": error == OK,
		"error": error,
		"reason": "" if error == OK else "La progression n'a pas pu être enregistrée (%s)." % error_string(error),
	}
