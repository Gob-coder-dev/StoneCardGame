## Conversion déterministe des anciens decks lors du remplacement du catalogue.
## Les identifiants actuels ne sont jamais interprétés comme des alias de combat.
extends RefCounted

static func requires_conversion(cards: Array) -> bool:
	for raw in cards:
		var id := str(raw)
		if not StoneLoader.has_stone(id) and StoneLoader.has_stone(StoneLoader.resolve_saved_id(id)):
			return true
	return false


static func convert(cards: Array, god_id: String) -> Array:
	if not requires_conversion(cards):
		return DeckRules.sanitize_deck(cards, god_id)
	var entries: Array = []
	var seen := {}
	var current_lineages := {}
	for raw in cards:
		var source := str(raw)
		var target := StoneLoader.resolve_saved_id(source)
		if seen.has(source) or not StoneLoader.is_stone_available_to_god(target, god_id):
			continue
		var current := StoneLoader.has_stone(source)
		var lineage := StoneLoader.stone_lineage(target)
		if current and current_lineages.has(lineage):
			continue
		if current:
			current_lineages[lineage] = true
		seen[source] = true
		entries.append({"id": target, "current": current})
		if entries.size() == DeckRules.DECK_SIZE:
			break
	var definitions := StoneLoader.get_stones_for_god(god_id)
	var minimums := {}
	for definition in definitions:
		var lineage := str(definition["lineage_id"])
		var cost := StoneCostRules.cost(definition)
		minimums[lineage] = minf(float(minimums.get(lineage, INF)), cost)
	var deck: Array = []
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var target := StoneLoader.get_stone(entry["id"])
		var remaining := entries.slice(index + 1)
		var protected := {}
		for future in remaining:
			if future["current"]:
				protected[StoneLoader.stone_lineage(future["id"])] = true
		var candidates := definitions.duplicate()
		candidates.sort_custom(func(a: Dictionary, b: Dictionary):
			var score_a := _distance(a, target)
			var score_b := _distance(b, target)
			return str(a["id"]) < str(b["id"]) if is_equal_approx(score_a, score_b) else score_a < score_b)
		for candidate in candidates:
			var lineage := str(candidate["lineage_id"])
			if protected.has(lineage) or (entry["current"] and lineage != target["lineage_id"]):
				continue
			var operation := DeckRules.try_add(deck, candidate["id"], god_id)
			if operation["success"] and _can_complete(operation["deck"], remaining, minimums):
				deck = operation["deck"]
				break
	return deck


static func _distance(candidate: Dictionary, target: Dictionary) -> float:
	if candidate["id"] == target["id"]:
		return -1.0
	var distance := 0.0 if candidate["god_id"] == target["god_id"] else 1000.0
	if candidate.get("effects", []) != target.get("effects", []) or candidate.get("coin_flip", "") != target.get("coin_flip", ""):
		distance += 100.0
	for field in ["blades", "shields", "long_blades"]:
		for side in StoneSide.ALL:
			distance += absf(float(candidate.get(field, {}).get(side, 0)) - float(target.get(field, {}).get(side, 0)))
	distance += absf(float(candidate.get("random_blades", 0)) - float(target.get("random_blades", 0)))
	return distance + absf(StoneCostRules.cost(candidate) - StoneCostRules.cost(target)) * 0.1


## Réserve le prix des formes les moins coûteuses des lignées restantes, pour
## garder un deck complet sans dépasser le budget après une fusion d'anciennes cartes.
static func _can_complete(deck: Array, remaining: Array, minimums: Dictionary) -> bool:
	var used := {}
	for id in deck:
		used[StoneLoader.stone_lineage(str(id))] = true
	var cost := DeckRules.deck_cost(deck)
	var protected := {}
	for future in remaining:
		if future["current"]:
			var lineage := StoneLoader.stone_lineage(future["id"])
			if used.has(lineage) or protected.has(lineage):
				return false
			protected[lineage] = true
			cost += float(minimums[lineage])
	var prices: Array[float] = []
	for lineage in minimums:
		if not used.has(lineage) and not protected.has(lineage):
			prices.append(float(minimums[lineage]))
	prices.sort()
	var needed := remaining.size() - protected.size()
	if prices.size() < needed:
		return false
	for index in range(needed):
		cost += prices[index]
	return cost <= DeckRules.DECK_BUDGET
