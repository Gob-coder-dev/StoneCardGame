## LoadoutGenerator.gd
## Fabrique pure de loadouts : dieux aléatoires, decks au même total exact,
## miroir et contraintes du draft. Partagée par campagne et PVP.
##
## Toutes les comparaisons de coût utilisent des quarts de point entiers. Un
## même `seed` produit exactement les mêmes dieux, cartes et totaux.
class_name LoadoutGenerator
extends RefCounted

const Shuffle := preload("res://scripts/domain/SeededShuffle.gd")

const PowerTierRules := preload("res://scripts/domain/CardPowerTierRules.gd")

var deck_size: int = DeckRules.DECK_SIZE
var budget_quarters: int = DeckRules.DECK_BUDGET * MonsterCostRules.COST_SCALE

var _cards: Array = []
var _cards_by_id: Dictionary = {}
var _available_cache: Dictionary = {}
var _lineage_cache: Dictionary = {}
var _reachable_cache: Dictionary = {}

## Le total reste variable, mais les decks sont tirés dans la moitié supérieure
## des totaux réellement atteignables afin de conserver des parties consistantes.
const TARGET_POOL_DIVISOR: int = 2

## Pouvoirs qu'une rencontre de campagne peut exiger dans les decks générés.
## Les clés correspondent aux champs des définitions de monstres.
const POWER_TAGS: Array[String] = ["random_blades", "coin_flip"]


## `pool` permet aux tests et à la future campagne d'injecter un catalogue
## réduit. Vide, le générateur lit le catalogue réel sans dépendre d'une scène.
func _init(pool: Array = [], size: int = DeckRules.DECK_SIZE,
		budget_points: float = float(DeckRules.DECK_BUDGET)) -> void:
	deck_size = size
	budget_quarters = int(roundf(budget_points * float(MonsterCostRules.COST_SCALE)))
	var source: Array = pool
	if source.is_empty():
		source = MonsterLoader.get_all_monsters()
	_ingest(source)


func _ingest(source: Array) -> void:
	for raw in source:
		if not raw is Dictionary:
			continue
		var definition: Dictionary = (raw as Dictionary).duplicate(true)
		var id := str(definition.get("id", ""))
		if id == "" or _cards_by_id.has(id):
			continue
		if PowerTierRules.tier_problem(definition) != "":
			continue
		var tier := PowerTierRules.effective_tier(definition)
		if tier < PowerTierRules.MIN_TIER or tier > PowerTierRules.MAX_TIER:
			continue
		var card_data := {
			"id": id,
			"lineage": str(definition.get("lineage_id", id)),
			"god_id": str(definition.get("god_id", "neutral")),
			"rarity": str(definition.get("rarity", "")),
			"level": int(definition.get("level", 1)),
			"tier": tier,
			"cost_q": _cost_quarters(definition),
			"power_tags": _power_tags(definition),
		}
		if int(card_data["cost_q"]) < 0:
			continue
		_cards.append(card_data)
		_cards_by_id[id] = card_data


func _cost_quarters(definition: Dictionary) -> int:
	if definition.has("cost_q"):
		return int(definition["cost_q"])
	if definition.has("cost_points"):
		return int(roundf(float(definition["cost_points"]) * float(MonsterCostRules.COST_SCALE)))
	return MonsterCostRules.cost_quarters(definition)


static func definition_has_power(definition: Dictionary, tag: String) -> bool:
	match tag:
		"random_blades":
			return int(definition.get("random_blades", 0)) > 0
		"coin_flip":
			return str(definition.get("coin_flip", "")) != ""
	return false


static func _power_tags(definition: Dictionary) -> Array[String]:
	var tags: Array[String] = []
	for tag in POWER_TAGS:
		if definition_has_power(definition, tag):
			tags.append(tag)
	return tags


## Vérifie la forme des minimums avant de lancer le solveur. Une contrainte
## inconnue ou hors bornes doit être refusée, jamais ignorée silencieusement.
static func power_constraint_problem(min_powers: Dictionary) -> String:
	for key in min_powers:
		var tag := str(key)
		if not POWER_TAGS.has(tag):
			return "Pouvoir inconnu : '%s'." % tag
		var minimum := int(min_powers[key])
		if minimum < 0 or minimum > DeckRules.DECK_SIZE:
			return "Minimum de cartes '%s' hors bornes." % tag
	return ""


static func _rng(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


## ─── Lectures du catalogue filtré ───────────────────────────────────────────

func cards_for_god(god_id: String, max_tier: int) -> Array:
	var key := "%s|%d" % [god_id, max_tier]
	if _available_cache.has(key):
		return (_available_cache[key] as Array).duplicate()
	var result: Array = []
	for card_data in _cards:
		if int(card_data["tier"]) > max_tier:
			continue
		var affinity := str(card_data["god_id"])
		if affinity != "neutral" and affinity != god_id:
			continue
		result.append((card_data as Dictionary).duplicate())
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["id"]) < str(b["id"]))
	_available_cache[key] = result
	return result.duplicate()


func lineages_for_god(god_id: String, max_tier: int) -> Dictionary:
	var key := "%s|%d" % [god_id, max_tier]
	if _lineage_cache.has(key):
		return (_lineage_cache[key] as Dictionary).duplicate(true)
	var options := {}
	for card_data in cards_for_god(god_id, max_tier):
		var lineage := str(card_data["lineage"])
		if not options.has(lineage):
			options[lineage] = []
		(options[lineage] as Array).append(card_data)
	for lineage in options:
		(options[lineage] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var cost_a := int(a["cost_q"])
			var cost_b := int(b["cost_q"])
			return cost_a < cost_b if cost_a != cost_b else str(a["id"]) < str(b["id"]))
	_lineage_cache[key] = options
	return options.duplicate(true)


func card(monster_id: String) -> Dictionary:
	return (_cards_by_id.get(monster_id, {}) as Dictionary).duplicate(true)


func cost_quarters(monster_id: String) -> int:
	return int((_cards_by_id.get(monster_id, {}) as Dictionary).get("cost_q", -1))


func lineage_of(monster_id: String) -> String:
	return str((_cards_by_id.get(monster_id, {}) as Dictionary).get("lineage", ""))


## ─── Totaux réalisables ─────────────────────────────────────────────────────

## Tous les totaux en quarts réalisables avec exactement `deck_size` lignées
## distinctes, une carte par lignée, sous la limite de palier et le budget.
func reachable_totals(god_id: String, max_tier: int) -> Array:
	var key := "%s|%d" % [god_id, max_tier]
	if _reachable_cache.has(key):
		return (_reachable_cache[key] as Array).duplicate()
	var options := lineages_for_god(god_id, max_tier)
	if options.size() < deck_size:
		_reachable_cache[key] = []
		return []
	var layers: Array = []
	for index in range(deck_size + 1):
		layers.append({})
	layers[0][0] = true
	for lineage in options:
		var next: Array = []
		for layer in layers:
			next.append((layer as Dictionary).duplicate())
		var costs := {}
		for card_value in options[lineage]:
			costs[int((card_value as Dictionary)["cost_q"])] = true
		for count in range(deck_size - 1, -1, -1):
			for total in (layers[count] as Dictionary).keys():
				for cost in costs:
					var candidate := int(total) + int(cost)
					if candidate <= budget_quarters:
						next[count + 1][candidate] = true
		layers = next
	var totals: Array = (layers[deck_size] as Dictionary).keys()
	totals.sort()
	_reachable_cache[key] = totals.duplicate()
	return totals


static func _common_totals(first: Array, second: Array) -> Array:
	var lookup := {}
	for total in first:
		lookup[int(total)] = true
	var common: Array = []
	for total in second:
		if lookup.has(int(total)):
			common.append(int(total))
	common.sort()
	return common


## ─── Modes Aléatoire et Miroir ──────────────────────────────────────────────

## Choisit deux dieux puis deux decks légaux ayant exactement le même total.
func generate_random(generation_seed: int, god_ids: Array, max_tier: int,
		min_god_cards: int = 0, min_powers: Dictionary = {}) -> Dictionary:
	if min_god_cards < 0 or min_god_cards > deck_size:
		return _fail("Le minimum de cartes du dieu est hors bornes.")
	var power_problem := power_constraint_problem(min_powers)
	if power_problem != "":
		return _fail(power_problem)
	var valid := _valid_gods(god_ids, max_tier)
	if valid.is_empty():
		return _fail("Aucun dieu ne permet un deck complet avec cette limite.")
	var rng := _rng(generation_seed)
	# Tirer les dieux avant de vérifier leur intersection rendait le palier 1
	# aléatoirement impossible. On tire désormais parmi les couples jouables.
	var pairs: Array = []
	for god_one_value in valid:
		for god_two_value in valid:
			var god_one := str(god_one_value)
			var god_two := str(god_two_value)
			var common := _common_totals(reachable_totals(god_one, max_tier),
				reachable_totals(god_two, max_tier))
			if not common.is_empty():
				pairs.append({"god_one": god_one, "god_two": god_two, "totals": common})
	if pairs.is_empty():
		return _fail("Aucun couple de dieux ne possède de total de deck commun.")
	Shuffle.apply(pairs, rng)
	for pair_value in pairs:
		var pair: Dictionary = pair_value
		for target_value in _targets_for_constraint(pair["totals"], rng,
				min_god_cards > 0 or not min_powers.is_empty()):
			var target := int(target_value)
			var deck_one := _build_exact(str(pair["god_one"]), target, max_tier, rng,
				min_god_cards, min_powers)
			if deck_one.is_empty():
				continue
			var deck_two := _build_exact(str(pair["god_two"]), target, max_tier, rng,
				min_god_cards, min_powers)
			if deck_two.is_empty():
				continue
			return {
				"ok": true,
				"reason": "",
				"god_one": str(pair["god_one"]),
				"god_two": str(pair["god_two"]),
				"deck_one": deck_one,
				"deck_two": deck_two,
				"total_quarters": target,
				"total_points": float(target) / float(MonsterCostRules.COST_SCALE),
				"seed": generation_seed,
			}
	return _fail("Aucun couple de decks légaux n'atteint un total commun.")


## Deck déterministe pour un dieu imposé, sans changer de dieu. Utilisé par la
## campagne quand un niveau fixe le dieu adverse mais génère son deck.
func generate_for_god(generation_seed: int, god_id: String, max_tier: int,
		min_powers: Dictionary = {}) -> Dictionary:
	if not _valid_gods([god_id], max_tier).has(god_id):
		return _fail("Ce dieu ne permet pas un deck complet avec cette limite.")
	var power_problem := power_constraint_problem(min_powers)
	if power_problem != "":
		return _fail(power_problem)
	var rng := _rng(generation_seed)
	var totals := reachable_totals(god_id, max_tier)
	for target_value in _targets_for_constraint(totals, rng, not min_powers.is_empty()):
		var target := int(target_value)
		var deck := _build_exact(god_id, target, max_tier, rng, 0, min_powers)
		if deck.is_empty():
			continue
		return {
			"ok": true,
			"reason": "",
			"god_id": god_id,
			"deck": deck,
			"total_quarters": target,
			"total_points": float(target) / float(MonsterCostRules.COST_SCALE),
			"seed": generation_seed,
		}
	return _fail("Aucun deck légal pour ce dieu.")


## Un seul loadout légal, dupliqué en profondeur par l'appelant. Le premier
## joueur n'est jamais déduit de ce loadout : il reste un tirage séparé.
func generate_mirror(generation_seed: int, god_ids: Array, max_tier: int,
		min_god_cards: int = 0, min_powers: Dictionary = {}) -> Dictionary:
	if min_god_cards < 0 or min_god_cards > deck_size:
		return _fail("Le minimum de cartes du dieu est hors bornes.")
	var power_problem := power_constraint_problem(min_powers)
	if power_problem != "":
		return _fail(power_problem)
	var valid := _valid_gods(god_ids, max_tier)
	if valid.is_empty():
		return _fail("Aucun dieu ne permet un deck complet avec cette limite.")
	var rng := _rng(generation_seed)
	var god_id := str(valid[rng.randi_range(0, valid.size() - 1)])
	var totals := reachable_totals(god_id, max_tier)
	if totals.is_empty():
		return _fail("Aucun total réalisable pour le dieu tiré.")
	for target_value in _targets_for_constraint(totals, rng,
			min_god_cards > 0 or not min_powers.is_empty()):
		var target := int(target_value)
		var deck := _build_exact(god_id, target, max_tier, rng, min_god_cards,
			min_powers)
		if deck.is_empty():
			continue
		return {
			"ok": true,
			"reason": "",
			"god_id": god_id,
			"deck": deck,
			"total_quarters": target,
			"total_points": float(target) / float(MonsterCostRules.COST_SCALE),
			"seed": generation_seed,
		}
	return _fail("Aucun deck légal pour le dieu tiré.")


func _randomized_rich_targets(totals: Array, rng: RandomNumberGenerator) -> Array:
	if totals.is_empty():
		return []
	var first := floori(float(totals.size()) / float(TARGET_POOL_DIVISOR))
	var result: Array = totals.slice(first, totals.size())
	Shuffle.apply(result, rng)
	return result


## Sans contrainte, conserve le tirage historique dans la moitié haute. Avec
## une affinité minimale, essaie ensuite les autres totaux afin qu'une solution
## légale moins chère ne soit jamais ignorée.
func _targets_for_constraint(totals: Array, rng: RandomNumberGenerator,
		include_fallback: bool) -> Array:
	var rich := _randomized_rich_targets(totals, rng)
	if not include_fallback or rich.size() == totals.size():
		return rich
	var rich_lookup := {}
	for value in rich:
		rich_lookup[int(value)] = true
	var fallback: Array = []
	for value in totals:
		if not rich_lookup.has(int(value)):
			fallback.append(value)
	Shuffle.apply(fallback, rng)
	rich.append_array(fallback)
	return rich


static func duplicate_loadout(loadout: Dictionary) -> Dictionary:
	return (loadout as Dictionary).duplicate(true)


## ─── Solveur de deck exact ──────────────────────────────────────────────────

func _build_exact(god_id: String, target: int, max_tier: int,
		rng: RandomNumberGenerator, min_god_cards: int = 0,
		min_powers: Dictionary = {}) -> Array:
	var options := lineages_for_god(god_id, max_tier)
	if options.size() < deck_size:
		return []
	var order: Array = options.keys()
	order.sort()
	Shuffle.apply(order, rng)
	var candidates := {}
	for lineage in order:
		var values: Array = (options[lineage] as Array).duplicate()
		Shuffle.apply(values, rng)
		candidates[lineage] = values
	var power_tags: Array = min_powers.keys()
	power_tags.sort()
	var normalized_powers := {}
	var power_counts := {}
	for tag in power_tags:
		normalized_powers[str(tag)] = int(min_powers[tag])
		power_counts[str(tag)] = 0
	var found: Variant = _search_exact(order, candidates, 0, 0, target, 0,
		god_id, min_god_cards, normalized_powers, power_counts, {})
	return (found as Array).duplicate() if found is Array else []


static func _power_minimums_met(min_powers: Dictionary,
		power_counts: Dictionary) -> bool:
	for tag in min_powers:
		if int(power_counts.get(tag, 0)) < int(min_powers[tag]):
			return false
	return true


func _search_exact(order: Array, candidates: Dictionary, index: int, count: int,
		remaining: int, god_count: int, god_id: String, min_god_cards: int,
		min_powers: Dictionary, power_counts: Dictionary,
		memo: Dictionary) -> Variant:
	if count == deck_size:
		if remaining == 0 and god_count >= min_god_cards \
				and _power_minimums_met(min_powers, power_counts):
			return []
		return null
	if index >= order.size() or order.size() - index < deck_size - count:
		return null
	if god_count + deck_size - count < min_god_cards:
		return null
	for tag in min_powers:
		if int(power_counts.get(tag, 0)) + (deck_size - count) < int(min_powers[tag]):
			return null
	var key := "%d|%d|%d|%d" % [index, count, remaining, god_count]
	for tag in power_counts:
		key += "|%s:%d" % [tag, int(power_counts[tag])]
	if memo.has(key):
		var cached: Variant = memo[key]
		if cached is Array:
			return (cached as Array).duplicate()
		return null
	var lineage := str(order[index])
	for card_value in candidates[lineage]:
		var card_data: Dictionary = card_value
		var cost := int(card_data["cost_q"])
		if cost > remaining:
			continue
		var next_god_count := god_count + (1 if str(card_data["god_id"]) == god_id else 0)
		var next_power_counts := power_counts.duplicate()
		for tag in (card_data.get("power_tags", []) as Array):
			if next_power_counts.has(tag):
				next_power_counts[tag] = int(next_power_counts[tag]) + 1
		var tail: Variant = _search_exact(order, candidates, index + 1, count + 1,
			remaining - cost, next_god_count, god_id, min_god_cards,
			min_powers, next_power_counts, memo)
		if tail is Array:
			var result: Array = (tail as Array).duplicate()
			result.push_front(str(card_data["id"]))
			memo[key] = result
			return result
	# Une lignée peut être ignorée. Le calcul des totaux atteignables autorise
	# déjà ce choix ; l'ancien solveur forçait par erreur les huit premières
	# lignées de l'ordre mélangé, rendant certains seeds pourtant valides
	# impossibles à construire.
	var skipped: Variant = _search_exact(order, candidates, index + 1, count,
		remaining, god_count, god_id, min_god_cards, min_powers, power_counts,
		memo)
	if skipped is Array:
		memo[key] = (skipped as Array).duplicate()
		return (skipped as Array).duplicate()
	memo[key] = false
	return null


func deck_cost_sum(deck: Array) -> int:
	var total := 0
	for monster_id in deck:
		total += cost_quarters(str(monster_id))
	return total


func _valid_gods(god_ids: Array, max_tier: int) -> Array:
	var result: Array = []
	for god_id_value in god_ids:
		var god_id := str(god_id_value)
		if result.has(god_id):
			continue
		if reachable_totals(god_id, max_tier).size() > 0:
			result.append(god_id)
	result.sort()
	return result


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
