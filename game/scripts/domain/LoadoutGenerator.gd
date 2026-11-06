## LoadoutGenerator.gd
## Fabrique pure de loadouts : dieux aléatoires, decks au même total exact,
## miroir et plan uniforme du draft. Partagée par campagne et PVP.
##
## Toutes les comparaisons de coût utilisent des quarts de point entiers. Un
## même `seed` produit exactement les mêmes dieux, cartes et totaux.
class_name LoadoutGenerator
extends RefCounted

const PowerTierRules := preload("res://scripts/domain/CardPowerTierRules.gd")

var deck_size: int = DeckRules.DECK_SIZE
var budget_quarters: int = DeckRules.DECK_BUDGET * StoneCostRules.COST_SCALE

var _cards: Array = []
var _cards_by_id: Dictionary = {}
var _available_cache: Dictionary = {}
var _lineage_cache: Dictionary = {}
var _reachable_cache: Dictionary = {}
var _uniform_cache: Dictionary = {}

const MAX_ATTEMPTS: int = 12
const MAX_COST_SEARCH: int = 250000
## Le total reste variable, mais les decks sont tirés dans la moitié supérieure
## des totaux réellement atteignables afin de conserver des parties consistantes.
const TARGET_POOL_DIVISOR: int = 2


## `pool` permet aux tests et à la future campagne d'injecter un catalogue
## réduit. Vide, le générateur lit le catalogue réel sans dépendre d'une scène.
func _init(pool: Array = [], size: int = DeckRules.DECK_SIZE,
		budget_points: float = float(DeckRules.DECK_BUDGET)) -> void:
	deck_size = size
	budget_quarters = int(roundf(budget_points * float(StoneCostRules.COST_SCALE)))
	var source: Array = pool
	if source.is_empty():
		source = StoneLoader.get_all_stones()
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
		var card := {
			"id": id,
			"lineage": str(definition.get("lineage_id", id)),
			"god_id": str(definition.get("god_id", "neutral")),
			"rarity": str(definition.get("rarity", "")),
			"level": int(definition.get("level", 1)),
			"tier": tier,
			"cost_q": _cost_quarters(definition),
		}
		if int(card["cost_q"]) < 0:
			continue
		_cards.append(card)
		_cards_by_id[id] = card


func _cost_quarters(definition: Dictionary) -> int:
	if definition.has("cost_q"):
		return int(definition["cost_q"])
	if definition.has("cost_points"):
		return int(roundf(float(definition["cost_points"]) * float(StoneCostRules.COST_SCALE)))
	return StoneCostRules.cost_quarters(definition)


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
	for card in _cards:
		if int(card["tier"]) > max_tier:
			continue
		var affinity := str(card["god_id"])
		if affinity != "neutral" and affinity != god_id:
			continue
		result.append((card as Dictionary).duplicate())
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["id"]) < str(b["id"]))
	_available_cache[key] = result
	return result.duplicate()


func lineages_for_god(god_id: String, max_tier: int) -> Dictionary:
	var key := "%s|%d" % [god_id, max_tier]
	if _lineage_cache.has(key):
		return (_lineage_cache[key] as Dictionary).duplicate(true)
	var options := {}
	for card in cards_for_god(god_id, max_tier):
		var lineage := str(card["lineage"])
		if not options.has(lineage):
			options[lineage] = []
		(options[lineage] as Array).append(card)
	for lineage in options:
		(options[lineage] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var cost_a := int(a["cost_q"])
			var cost_b := int(b["cost_q"])
			return cost_a < cost_b if cost_a != cost_b else str(a["id"]) < str(b["id"]))
	_lineage_cache[key] = options
	return options.duplicate(true)


func card(stone_id: String) -> Dictionary:
	return (_cards_by_id.get(stone_id, {}) as Dictionary).duplicate(true)


func cost_quarters(stone_id: String) -> int:
	return int((_cards_by_id.get(stone_id, {}) as Dictionary).get("cost_q", -1))


func lineage_of(stone_id: String) -> String:
	return str((_cards_by_id.get(stone_id, {}) as Dictionary).get("lineage", ""))


func tier_of(stone_id: String) -> int:
	return int((_cards_by_id.get(stone_id, {}) as Dictionary).get("tier", -1))


func deck_cost_list(deck: Array) -> Array:
	var costs: Array = []
	for stone_id in deck:
		costs.append(cost_quarters(str(stone_id)))
	return costs


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
func generate_random(seed: int, god_ids: Array, max_tier: int) -> Dictionary:
	var valid := _valid_gods(god_ids, max_tier)
	if valid.is_empty():
		return _fail("Aucun dieu ne permet un deck complet avec cette limite.")
	var rng := _rng(seed)
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
	_shuffle(pairs, rng)
	for pair_value in pairs:
		var pair: Dictionary = pair_value
		for target_value in _randomized_rich_targets(pair["totals"], rng):
			var target := int(target_value)
			var deck_one := _build_exact(str(pair["god_one"]), target, max_tier, rng)
			if deck_one.is_empty():
				continue
			var deck_two := _build_exact(str(pair["god_two"]), target, max_tier, rng)
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
				"total_points": float(target) / float(StoneCostRules.COST_SCALE),
				"seed": seed,
			}
	return _fail("Aucun couple de decks légaux n'atteint un total commun.")


## Un seul loadout légal, dupliqué en profondeur par l'appelant. Le premier
## joueur n'est jamais déduit de ce loadout : il reste un tirage séparé.
func generate_mirror(seed: int, god_ids: Array, max_tier: int) -> Dictionary:
	var valid := _valid_gods(god_ids, max_tier)
	if valid.is_empty():
		return _fail("Aucun dieu ne permet un deck complet avec cette limite.")
	var rng := _rng(seed)
	var god_id := str(valid[rng.randi_range(0, valid.size() - 1)])
	var totals := reachable_totals(god_id, max_tier)
	if totals.is_empty():
		return _fail("Aucun total réalisable pour le dieu tiré.")
	for target_value in _randomized_rich_targets(totals, rng):
		var target := int(target_value)
		var deck := _build_exact(god_id, target, max_tier, rng)
		if deck.is_empty():
			continue
		return {
			"ok": true,
			"reason": "",
			"god_id": god_id,
			"deck": deck,
			"total_quarters": target,
			"total_points": float(target) / float(StoneCostRules.COST_SCALE),
			"seed": seed,
		}
	return _fail("Aucun deck légal pour le dieu tiré.")


func _randomized_rich_targets(totals: Array, rng: RandomNumberGenerator) -> Array:
	if totals.is_empty():
		return []
	var first := floori(float(totals.size()) / float(TARGET_POOL_DIVISOR))
	var result: Array = totals.slice(first, totals.size())
	_shuffle(result, rng)
	return result


static func duplicate_loadout(loadout: Dictionary) -> Dictionary:
	return (loadout as Dictionary).duplicate(true)


## ─── Draft : plan uniforme vérifiable ───────────────────────────────────────

## Sélectionne un coût commun aux deux dieux avec au moins `deck_size + 1`
## lignées disponibles pour chacun. Le plan de huit cartes et sa réserve de
## même coût rendent chaque branche d'offre immédiatement complétable.
func generate_uniform_pair(seed: int, god_one: String, god_two: String,
		max_tier: int) -> Dictionary:
	var rng := _rng(seed)
	var by_cost_one := _uniform_by_cost(god_one, max_tier)
	var by_cost_two := _uniform_by_cost(god_two, max_tier)
	var common_costs: Array = []
	for cost in by_cost_one:
		if not by_cost_two.has(cost):
			continue
		if int(cost) * deck_size > budget_quarters:
			continue
		if (by_cost_one[cost] as Array).size() < deck_size + 1:
			continue
		if (by_cost_two[cost] as Array).size() < deck_size + 1:
			continue
		common_costs.append(int(cost))
	common_costs.sort()
	if common_costs.is_empty():
		return _fail("Aucun coût commun ne permet deux drafts complets et sûrs.")
	var cost := int(common_costs[common_costs.size() - 1])
	var one: Array = (by_cost_one[cost] as Array).duplicate()
	var two: Array = (by_cost_two[cost] as Array).duplicate()
	_shuffle(one, rng)
	_shuffle(two, rng)
	var plan_one: Array = []
	var plan_two: Array = []
	for index in range(deck_size):
		plan_one.append(str((one[index] as Dictionary)["id"]))
		plan_two.append(str((two[index] as Dictionary)["id"]))
	return {
		"ok": true,
		"reason": "",
		"god_one": god_one,
		"god_two": god_two,
		"deck_one": plan_one,
		"deck_two": plan_two,
		"reserve_one": str((one[deck_size] as Dictionary)["id"]),
		"reserve_two": str((two[deck_size] as Dictionary)["id"]),
		"cost_quarters": cost,
		"total_quarters": cost * deck_size,
		"total_points": float(cost * deck_size) / float(StoneCostRules.COST_SCALE),
		"seed": seed,
	}


## Une carte au plus par lignée pour un coût donné. Le tri par identifiant
## garde un choix déterministe quand plusieurs formes d'une lignée coûtent
## exactement le même prix.
func _uniform_by_cost(god_id: String, max_tier: int) -> Dictionary:
	var key := "%s|%d" % [god_id, max_tier]
	if _uniform_cache.has(key):
		return (_uniform_cache[key] as Dictionary).duplicate(true)
	var result := {}
	for card_value in cards_for_god(god_id, max_tier):
		var card_data: Dictionary = card_value
		var cost := int(card_data["cost_q"])
		if not result.has(cost):
			result[cost] = {}
		var lineage := str(card_data["lineage"])
		if not (result[cost] as Dictionary).has(lineage):
			result[cost][lineage] = card_data
	var compact := {}
	for cost in result:
		var cards: Array = (result[cost] as Dictionary).values()
		cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["id"]) < str(b["id"]))
		compact[cost] = cards
	_uniform_cache[key] = compact
	return compact.duplicate(true)


## ─── Solveur de deck exact ──────────────────────────────────────────────────

func _build_exact(god_id: String, target: int, max_tier: int,
		rng: RandomNumberGenerator) -> Array:
	var options := lineages_for_god(god_id, max_tier)
	if options.size() < deck_size:
		return []
	var order: Array = options.keys()
	order.sort()
	_shuffle(order, rng)
	var candidates := {}
	for lineage in order:
		var values: Array = (options[lineage] as Array).duplicate()
		_shuffle(values, rng)
		candidates[lineage] = values
	var found: Variant = _search_exact(order, candidates, 0, 0, target, {})
	return (found as Array).duplicate() if found is Array else []


func _search_exact(order: Array, candidates: Dictionary, index: int, count: int,
		remaining: int, memo: Dictionary) -> Variant:
	if count == deck_size:
		return [] if remaining == 0 else null
	if index >= order.size() or order.size() - index < deck_size - count:
		return null
	var key := "%d|%d|%d" % [index, count, remaining]
	if memo.has(key):
		var cached: Variant = memo[key]
		return (cached as Array).duplicate() if cached is Array else null
	var lineage := str(order[index])
	for card_value in candidates[lineage]:
		var card_data: Dictionary = card_value
		var cost := int(card_data["cost_q"])
		if cost > remaining:
			continue
		var tail: Variant = _search_exact(order, candidates, index + 1, count + 1,
			remaining - cost, memo)
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
		remaining, memo)
	if skipped is Array:
		memo[key] = (skipped as Array).duplicate()
		return (skipped as Array).duplicate()
	memo[key] = false
	return null


## Construit un deck dont la suite des coûts est imposée. Utilisé par le
## repli du draft lorsque le plan uniforme n'est pas disponible.
func generate_with_costs(seed: int, god_id: String, costs: Array,
		max_tier: int) -> Dictionary:
	var rng := _rng(seed)
	var deck := _build_exact_costs(god_id, costs, max_tier, rng)
	if deck.is_empty():
		return _fail("Aucun deck ne respecte exactement cette suite de coûts.")
	return {
		"ok": true,
		"reason": "",
		"god_id": god_id,
		"deck": deck,
		"total_quarters": int(deck_cost_sum(deck)),
		"seed": seed,
	}


func _build_exact_costs(god_id: String, costs: Array, max_tier: int,
		rng: RandomNumberGenerator) -> Array:
	var by_cost := {}
	for card_value in cards_for_god(god_id, max_tier):
		var card_data: Dictionary = card_value
		var cost := int(card_data["cost_q"])
		if not by_cost.has(cost):
			by_cost[cost] = []
		(by_cost[cost] as Array).append(card_data)
	for cost in by_cost:
		_shuffle(by_cost[cost], rng)
	var used := {}
	var chosen: Array = []
	var search_budget := [MAX_COST_SEARCH]
	if _search_costs(costs, 0, by_cost, used, chosen, search_budget):
		return chosen.duplicate()
	return []


func _search_costs(costs: Array, index: int, by_cost: Dictionary, used: Dictionary,
		chosen: Array, search_budget: Array) -> bool:
	if index >= costs.size():
		return true
	search_budget[0] -= 1
	if search_budget[0] <= 0:
		return false
	var candidates: Array = by_cost.get(int(costs[index]), [])
	for card_value in candidates:
		var card_data: Dictionary = card_value
		var lineage := str(card_data["lineage"])
		if used.has(lineage):
			continue
		used[lineage] = true
		chosen.append(str(card_data["id"]))
		if _search_costs(costs, index + 1, by_cost, used, chosen, search_budget):
			return true
		chosen.pop_back()
		used.erase(lineage)
	return false


## Repli déterministe : deux decks dont la suite exacte des coûts est commune.
func generate_pair_with_shared_costs(seed: int, god_one: String, god_two: String,
		max_tier: int) -> Dictionary:
	var rng := _rng(seed)
	var common := _common_totals(reachable_totals(god_one, max_tier),
		reachable_totals(god_two, max_tier))
	for index in range(common.size() - 1, -1, -1):
		var target := int(common[index])
		for attempt in range(MAX_ATTEMPTS):
			var deck_one := _build_exact(god_one, target, max_tier, rng)
			if deck_one.is_empty():
				continue
			var costs := deck_cost_list(deck_one)
			var deck_two := _build_exact_costs(god_two, costs, max_tier, rng)
			if deck_two.is_empty():
				continue
			return {
				"ok": true,
				"reason": "",
				"god_one": god_one,
				"god_two": god_two,
				"deck_one": deck_one,
				"deck_two": deck_two,
				"costs": costs,
				"total_quarters": target,
				"seed": seed,
			}
	return _fail("Aucune suite de coûts commune ne réalise deux decks légaux.")


func deck_cost_sum(deck: Array) -> int:
	var total := 0
	for stone_id in deck:
		total += cost_quarters(str(stone_id))
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


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[swap]
		values[swap] = value
