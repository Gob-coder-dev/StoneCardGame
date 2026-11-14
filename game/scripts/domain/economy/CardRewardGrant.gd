## Attribution commune des cartes gagnées : collection, coffre ou compensation.
## Travaille sur l'inventaire candidat ; aucune sauvegarde ni interface ici.
extends RefCounted

const Compensation := preload("res://scripts/domain/economy/CardCompensation.gd")


static func apply(inventory: PlayerInventory, raw: Variant,
		compensate_maxed: bool = true) -> Dictionary:
	if inventory == null or not raw is Dictionary:
		return _fail("Récompense de carte invalide.")
	var reward: Dictionary = raw.duplicate(true)
	var lineage_id := str(reward.get("lineage_id", ""))
	var copies := int(reward.get("copies", 0))
	var stone_id := StoneLoader.variant_id(lineage_id, 1)
	if stone_id == "" or copies <= 0:
		return _fail("Récompense de carte inconnue ou quantité invalide : %s." % lineage_id)
	var affinity := StoneLoader.stone_affinity(stone_id)
	if compensate_maxed and inventory.unlocked_level(lineage_id) \
			>= StoneLoader.lineage_max_level(lineage_id):
		var souls := Compensation.souls_for(lineage_id, copies)
		inventory.souls += souls
		reward["maxed"] = true
		reward["compensation_souls"] = souls
	elif affinity != "neutral" and not inventory.has_god(affinity):
		if not inventory.defer_copies(lineage_id, copies):
			return _fail("Impossible de réserver la carte : %s." % lineage_id)
		reward["deferred"] = true
		reward["god_id"] = affinity
	elif not inventory.add_copies(lineage_id, copies):
		return _fail("Impossible d'ajouter la carte : %s." % lineage_id)
	return {"ok": true, "reason": "", "reward": reward}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
