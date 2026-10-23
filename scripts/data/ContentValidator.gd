## Validation des catalogues après chargement.
extends RefCounted

static func validate(stones: Array, gods: Dictionary, npcs: Array, default_god_id: String) -> void:
	if not gods.has(default_god_id):
		push_error("StoneLoader: dieu par défaut inconnu '%s'." % default_god_id)
	for stone in stones:
		var stone_id := str(stone.get("id", ""))
		var god_id := str(stone.get("god_id", "neutral"))
		if god_id != "neutral" and not gods.has(god_id):
			push_error("StoneLoader: famille inconnue '%s' sur '%s'." % [god_id, stone_id])
		var random_count := int(stone.get("random_blades", 0))
		if random_count > 0 and str(stone.get("coin_flip", "")) != "":
			push_error("StoneLoader: les deux pouvoirs Fortune sont combinés sur '%s'." % stone_id)
		var decline_power_count := 0
		for effect in stone.get("effects", []):
			if effect == "weaken_adjacent" or effect == "weaken_enemies_on_miss":
				decline_power_count += 1
		if decline_power_count > 1:
			push_error("StoneLoader: plusieurs pouvoirs Déclin sont combinés sur '%s'." % stone_id)
		var capacity := 0
		for side in StoneSide.ALL:
			var base := int(stone.get("blades", {}).get(side, 0))
			var long_count := int(stone.get("long_blades", {}).get(side, 0))
			var shield_count := int(stone.get("shields", {}).get(side, 0))
			if base < 0 or long_count < 0 or shield_count < 0 or base + long_count + shield_count > 4:
				push_error("StoneLoader: plus de 4 symboles ou valeur négative sur %s/%s." % [stone_id, side])
			capacity += maxi(0, 4 - base - long_count - shield_count)
		if random_count < 0 or random_count > capacity:
			push_error("StoneLoader: lames aléatoires impossibles sur '%s'." % stone_id)
	for npc in npcs:
		var npc_id := str(npc.get("id", ""))
		var god_id := str(npc.get("god_id", ""))
		if not gods.has(god_id):
			push_error("StoneLoader: dieu inconnu pour le NPC '%s'." % npc_id)
		var seen: Array = []
		for stone_id in npc.get("deck", []):
			if seen.has(stone_id) or not StoneLoader.is_stone_available_to_god(str(stone_id), god_id):
				push_error("StoneLoader: deck incompatible pour le NPC '%s'." % npc_id)
			seen.append(stone_id)
