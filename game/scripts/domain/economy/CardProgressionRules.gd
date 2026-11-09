## CardProgressionRules.gd
## Règles pures des copies et améliorations. Aucune sauvegarde ni interface.
class_name CardProgressionRules
extends RefCounted


static func default_entry() -> Dictionary:
	return {"unlocked_level": 0, "copies": 0}


static func sanitize_entry(lineage_id: String, raw: Variant) -> Dictionary:
	var result := default_entry()
	if not raw is Dictionary or StoneLoader.lineage_max_level(lineage_id) <= 0:
		return result
	result["unlocked_level"] = clampi(int(raw.get("unlocked_level", 0)), 0,
		StoneLoader.lineage_max_level(lineage_id))
	result["copies"] = maxi(0, int(raw.get("copies", 0)))
	return result


static func requirement(lineage_id: String, unlocked_level: int,
		config: Dictionary) -> Dictionary:
	if unlocked_level <= 0 or unlocked_level >= StoneLoader.lineage_max_level(lineage_id):
		return {}
	var first_form := StoneLoader.variant_id(lineage_id, 1)
	var rarity := StoneLoader.stone_rarity(first_form)
	var upgrades: Variant = config.get("upgrades", {})
	if not upgrades is Dictionary:
		return {}
	var by_rarity: Variant = upgrades.get(rarity, {})
	if not by_rarity is Dictionary:
		return {}
	var value: Variant = by_rarity.get(str(unlocked_level), {})
	return value.duplicate(true) if value is Dictionary else {}


## La première copie découvre la carte et compte déjà vers le prochain niveau.
static func add_copies(entry: Dictionary, amount: int, max_level: int) -> Dictionary:
	var result := entry.duplicate(true)
	if amount <= 0 or max_level <= 0:
		return result
	result["copies"] = maxi(0, int(result.get("copies", 0))) + amount
	if int(result.get("unlocked_level", 0)) == 0:
		result["unlocked_level"] = 1
	return result


static func can_upgrade(lineage_id: String, entry: Dictionary, souls: int,
		config: Dictionary) -> bool:
	var requirement_value := requirement(lineage_id,
		int(entry.get("unlocked_level", 0)), config)
	return not requirement_value.is_empty() \
		and int(entry.get("copies", 0)) >= int(requirement_value.get("copies", 0)) \
		and souls >= int(requirement_value.get("souls", 0))


static func upgrade(lineage_id: String, entry: Dictionary, souls: int,
		config: Dictionary) -> Dictionary:
	var requirement_value := requirement(lineage_id,
		int(entry.get("unlocked_level", 0)), config)
	if requirement_value.is_empty():
		return {"ok": false, "reason": "Cette carte est déjà au niveau maximal."}
	var copies_required := int(requirement_value.get("copies", 0))
	var souls_required := int(requirement_value.get("souls", 0))
	if int(entry.get("copies", 0)) < copies_required:
		return {"ok": false, "reason": "Pas assez de copies."}
	if souls < souls_required:
		return {"ok": false, "reason": "Pas assez d'âmes."}
	var next := entry.duplicate(true)
	next["copies"] = int(next.get("copies", 0)) - copies_required
	next["unlocked_level"] = int(next.get("unlocked_level", 0)) + 1
	return {"ok": true, "reason": "", "entry": next,
		"souls": souls - souls_required, "spent_souls": souls_required,
		"spent_copies": copies_required}
