## Résout la variante d'un Rituel pour les accès courants. La définition
## retournée est complète et peut être affichée ou tirée sans règle implicite.
class_name RitualAccessRules
extends RefCounted

const PROFILE_ORDER: Array[String] = ["base", "epic_cards", "legendary_cards"]


static func resolve(definition: Dictionary, access: ContentAccessState) -> Dictionary:
	var result := definition.duplicate(true)
	var profiles: Variant = definition.get("progression_profiles", {})
	if profiles is Dictionary:
		for profile_id in PROFILE_ORDER:
			if profile_id != "base" and not access.has_gate(profile_id):
				continue
			var override: Variant = profiles.get(profile_id, {})
			if override is Dictionary:
				for key in override:
					result[key] = (override as Dictionary)[key]
	var required_gate := str(result.get("required_gate", ""))
	result["available"] = access.has_gate(required_gate)
	result["required_gate"] = required_gate
	result["allowed_rarities"] = access.rarities()
	result.erase("progression_profiles")
	return result
