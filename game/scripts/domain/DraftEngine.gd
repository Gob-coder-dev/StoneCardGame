## DraftEngine.gd
## Moteur pur du mode Sélection. Il ne dépend d'aucune scène, d'aucun socket et
## d'aucune horloge murale : l'orchestrateur appelle `advance(delta)` et reste
## seul autoritaire sur la deadline.
##
## Chaque camp possède son propre curseur. Un choix valide avance immédiatement
## ce camp et publie sa paire suivante ; l'autre camp n'est jamais attendu entre
## deux cartes. Le plan complet est construit et vérifié au démarrage : seize
## lignées distinctes par camp, deux par étape, un coût commun aux quatre cartes
## d'une même position et un total final identique quelle que soit la branche.
class_name DraftEngine
extends RefCounted

const GeneratorModel := preload("res://scripts/domain/LoadoutGenerator.gd")

const DEFAULT_DURATION_SECONDS: float = 60.0
const MAX_PLAN_ATTEMPTS: int = 96

var generator: LoadoutGenerator = null
var god_one: String = ""
var god_two: String = ""
var max_tier: int = GameModeRules.DEFAULT_POWER_TIER
var seed: int = 0

var _deck_size: int = DeckRules.DECK_SIZE
var _duration: float = DEFAULT_DURATION_SECONDS
var _elapsed: float = 0.0
var _started := false
var _costs: Array = []
var _plan_one: Array = []
var _plan_two: Array = []
var _step_one := 0
var _step_two := 0
var _deck_one: Array = []
var _deck_two: Array = []
var _complete_one := false
var _complete_two := false
var _offers_one: Array = []
var _offers_two: Array = []
var _total_quarters := 0


## `pool` vide lit le catalogue réel ; les tests injectent un petit catalogue.
func _init(pool: Array = [], deck_size: int = DeckRules.DECK_SIZE,
		budget_points: float = float(DeckRules.DECK_BUDGET)) -> void:
	_deck_size = deck_size
	generator = GeneratorModel.new(pool, deck_size, budget_points)


## Démarre un draft complet. Le plan est précalculé et vérifié avant de publier
## la moindre offre : un catalogue insuffisant échoue proprement.
func start(p_seed: int, p_god_one: String, p_god_two: String, p_max_tier: int,
		duration: float = DEFAULT_DURATION_SECONDS) -> Dictionary:
	_reset()
	seed = p_seed
	god_one = p_god_one
	god_two = p_god_two
	max_tier = p_max_tier
	_duration = maxf(0.1, duration)
	if generator == null:
		return {"ok": false, "reason": "Catalogue absent."}
	if god_one == "" or god_two == "":
		return {"ok": false, "reason": "Dieu manquant pour le draft."}
	var costs_one := _costs_by_lineage(god_one, max_tier)
	var costs_two := _costs_by_lineage(god_two, max_tier)
	var common_costs: Array = []
	for cost in costs_one:
		if costs_two.has(cost):
			common_costs.append(int(cost))
	common_costs.sort()
	if common_costs.is_empty():
		return {"ok": false, "reason": "Aucun coût commun entre les deux dieux."}
	for attempt in range(MAX_PLAN_ATTEMPTS):
		var rng := _rng(seed + attempt * 104729)
		var plan := _build_plan(costs_one, costs_two, common_costs, rng)
		if not bool(plan.get("ok", false)):
			continue
		_install_plan(plan)
		_started = true
		_offers_one = _current_pair(_plan_one, _step_one)
		_offers_two = _current_pair(_plan_two, _step_two)
		return _started_result()
	_reset()
	return {"ok": false, "reason": "Aucun plan de draft légal et sûr n'existe pour ces dieux."}


func _started_result() -> Dictionary:
	return {
		"ok": true,
		"reason": "",
		"god_one": god_one,
		"god_two": god_two,
		"step_one": _step_one,
		"step_two": _step_two,
		"complete_one": _complete_one,
		"complete_two": _complete_two,
		"cost_quarters": _offer_cost(GameState.PLAYER_ONE),
		"total_quarters": _total_quarters,
		"offers_one": _offers_one.duplicate(),
		"offers_two": _offers_two.duplicate(),
	}


func _reset() -> void:
	_started = false
	_elapsed = 0.0
	_costs = []
	_plan_one = []
	_plan_two = []
	_step_one = 0
	_step_two = 0
	_deck_one = []
	_deck_two = []
	_complete_one = false
	_complete_two = false
	_offers_one = []
	_offers_two = []
	_total_quarters = 0


func _install_plan(plan: Dictionary) -> void:
	_costs = (plan["costs"] as Array).duplicate()
	_plan_one = _duplicate_pairs(plan["pairs_one"])
	_plan_two = _duplicate_pairs(plan["pairs_two"])
	_total_quarters = int(plan["total_quarters"])


static func _duplicate_pairs(pairs: Array) -> Array:
	var result: Array = []
	for pair in pairs:
		result.append((pair as Array).duplicate())
	return result


## Coût de chaque lignée disponible pour un dieu. Une lignée ne peut être
## utilisée qu'une seule fois dans le plan, même si elle possède plusieurs
## formes de coûts différents.
func _costs_by_lineage(god_id: String, tier: int) -> Dictionary:
	var result := {}
	for card_value in generator.cards_for_god(god_id, tier):
		var card_data: Dictionary = card_value
		var cost := int(card_data.get("cost_q", -1))
		var lineage := str(card_data.get("lineage", ""))
		if cost <= 0 or lineage == "":
			continue
		if not result.has(cost):
			result[cost] = {}
		(result[cost] as Dictionary)[lineage] = true
	return result


## Recherche d'un plan par tentatives déterministes. Les coûts sont pris parmi
## les moins chers pour rester sous le budget, avec un peu de diversité pour ne
## pas consommer une lignée nécessaire à une étape ultérieure.
func _build_plan(costs_one: Dictionary, costs_two: Dictionary,
		common_costs: Array, rng: RandomNumberGenerator) -> Dictionary:
	var used_one := {}
	var used_two := {}
	var pairs_one: Array = []
	var pairs_two: Array = []
	var chosen_costs: Array = []
	var total := 0
	for step in range(_deck_size):
		var candidates: Array = []
		for cost_value in common_costs:
			var cost := int(cost_value)
			if total + cost > generator.budget_quarters:
				continue
			if _unused_lineages(costs_one, cost, used_one).size() < 2:
				continue
			if _unused_lineages(costs_two, cost, used_two).size() < 2:
				continue
			candidates.append(cost)
		if candidates.is_empty():
			return {"ok": false}
		var pick_limit := mini(4, candidates.size())
		var cost := int(candidates[rng.randi_range(0, pick_limit - 1)])
		var one := _unused_lineages(costs_one, cost, used_one)
		var two := _unused_lineages(costs_two, cost, used_two)
		_shuffle(one, rng)
		_shuffle(two, rng)
		var pair_one := _pair_ids_for_god(god_one, cost, one, 2)
		var pair_two := _pair_ids_for_god(god_two, cost, two, 2)
		if pair_one.size() != 2 or pair_two.size() != 2:
			return {"ok": false}
		for stone_id in pair_one:
			used_one[generator.lineage_of(str(stone_id))] = true
		for stone_id in pair_two:
			used_two[generator.lineage_of(str(stone_id))] = true
		pairs_one.append(pair_one)
		pairs_two.append(pair_two)
		chosen_costs.append(cost)
		total += cost
	if total > generator.budget_quarters:
		return {"ok": false}
	if not _verify_plan(pairs_one, pairs_two, chosen_costs):
		return {"ok": false}
	return {
		"ok": true,
		"costs": chosen_costs,
		"pairs_one": pairs_one,
		"pairs_two": pairs_two,
		"total_quarters": total,
	}


func _unused_lineages(costs: Dictionary, cost: int, used: Dictionary) -> Array:
	var result: Array = []
	if not costs.has(cost):
		return result
	for lineage in (costs[cost] as Dictionary):
		if not used.has(lineage):
			result.append(str(lineage))
	result.sort()
	return result


## Choisit un identifiant de carte concret pour chaque lignée, au coût demandé.
func _pair_ids_for_god(god_id: String, cost: int, lineages: Array, count: int) -> Array:
	var wanted := {}
	for lineage in lineages:
		wanted[str(lineage)] = true
	var by_lineage := {}
	for card_value in generator.cards_for_god(god_id, max_tier):
		var card_data: Dictionary = card_value
		if int(card_data.get("cost_q", -1)) != cost:
			continue
		var lineage := str(card_data.get("lineage", ""))
		if not wanted.has(lineage) or by_lineage.has(lineage):
			continue
		by_lineage[lineage] = str(card_data.get("id", ""))
	var result: Array = []
	for lineage in lineages:
		var card_id := str(by_lineage.get(str(lineage), ""))
		if card_id == "":
			return []
		result.append(card_id)
		if result.size() == count:
			break
	return result


func _verify_plan(pairs_one: Array, pairs_two: Array, costs: Array) -> bool:
	if pairs_one.size() != _deck_size or pairs_two.size() != _deck_size:
		return false
	if costs.size() != _deck_size:
		return false
	var lineages_one := {}
	var lineages_two := {}
	var total := 0
	for step in range(_deck_size):
		var cost := int(costs[step])
		total += cost
		if cost <= 0 or cost > generator.budget_quarters:
			return false
		var pair_one: Array = pairs_one[step]
		var pair_two: Array = pairs_two[step]
		if pair_one.size() != 2 or pair_two.size() != 2:
			return false
		if str(pair_one[0]) == str(pair_one[1]) or str(pair_two[0]) == str(pair_two[1]):
			return false
		for stone_id in pair_one + pair_two:
			if generator.cost_quarters(str(stone_id)) != cost:
				return false
		for stone_id in pair_one:
			var lineage_one := generator.lineage_of(str(stone_id))
			if lineage_one == "" or lineages_one.has(lineage_one):
				return false
			lineages_one[lineage_one] = true
		for stone_id in pair_two:
			var lineage_two := generator.lineage_of(str(stone_id))
			if lineage_two == "" or lineages_two.has(lineage_two):
				return false
			lineages_two[lineage_two] = true
	if total > generator.budget_quarters:
		return false
	for mask in range(1 << _deck_size):
		var deck_one: Array = []
		var deck_two: Array = []
		for step in range(_deck_size):
			var index := 1 if (mask & (1 << step)) != 0 else 0
			deck_one.append(str((pairs_one[step] as Array)[index]))
			deck_two.append(str((pairs_two[step] as Array)[index]))
		if DeckRules.deck_quarters(deck_one) != total or DeckRules.deck_quarters(deck_two) != total:
			return false
		if not DeckRules.is_deck_valid(deck_one, god_one):
			return false
		if not DeckRules.is_deck_valid(deck_two, god_two):
			return false
		if not _lineages_unique(deck_one) or not _lineages_unique(deck_two):
			return false
	return true


func _lineages_unique(deck: Array) -> bool:
	var seen := {}
	for stone_id in deck:
		var lineage := generator.lineage_of(str(stone_id))
		if lineage == "" or seen.has(lineage):
			return false
		seen[lineage] = true
	return true


## ─── Choix et progression ───────────────────────────────────────────────────

func choose(side: int, stone_id: String) -> Dictionary:
	if not _started or complete_for(side):
		return {"ok": false, "reason": "Le draft n'est pas ouvert pour ce joueur."}
	if side != GameState.PLAYER_ONE and side != GameState.PLAYER_TWO:
		return {"ok": false, "reason": "Joueur inconnu."}
	if not offers_for(side).has(stone_id):
		return {"ok": false, "reason": "Carte hors proposition."}
	if side == GameState.PLAYER_ONE:
		_deck_one.append(stone_id)
		_step_one += 1
		_complete_one = _step_one >= _deck_size
		_offers_one = [] if _complete_one else _current_pair(_plan_one, _step_one)
	else:
		_deck_two.append(stone_id)
		_step_two += 1
		_complete_two = _step_two >= _deck_size
		_offers_two = [] if _complete_two else _current_pair(_plan_two, _step_two)
	return {
		"ok": true,
		"reason": "",
		"complete": is_complete(),
		"own_complete": complete_for(side),
		"step": step_for(side),
	}


func offers_for(side: int) -> Array:
	if side == GameState.PLAYER_ONE:
		return _offers_one.duplicate()
	if side == GameState.PLAYER_TWO:
		return _offers_two.duplicate()
	return []


## Paire prévue pour un camp à une étape donnée. C'est la projection utilisée
## pour montrer à un joueur les propositions adverses de **sa** position, même
## si l'adversaire a déjà avancé plus loin ou terminé son deck.
func offers_for_step(side: int, step: int) -> Array:
	if step < 0 or step >= _deck_size:
		return []
	if side == GameState.PLAYER_ONE:
		return _current_pair(_plan_one, step)
	if side == GameState.PLAYER_TWO:
		return _current_pair(_plan_two, step)
	return []


## Les quatre propositions de l'étape courante sont publiques. Elles peuvent
## être vides pour un camp qui a terminé : les autres restent intactes.
func all_offers() -> Dictionary:
	return {
		"offers_one": _offers_one.duplicate(),
		"offers_two": _offers_two.duplicate(),
		"step_one": _step_one,
		"step_two": _step_two,
		"complete_one": _complete_one,
		"complete_two": _complete_two,
	}


func step_for(side: int) -> int:
	if side == GameState.PLAYER_ONE:
		return _step_one
	if side == GameState.PLAYER_TWO:
		return _step_two
	return 0


func complete_for(side: int) -> bool:
	if side == GameState.PLAYER_ONE:
		return _complete_one
	if side == GameState.PLAYER_TWO:
		return _complete_two
	return false


func is_complete() -> bool:
	return _complete_one and _complete_two


func step() -> int:
	return maxi(_step_one, _step_two)


func total_steps() -> int:
	return _deck_size


func is_started() -> bool:
	return _started


func current_cost_quarters() -> int:
	return _offer_cost(GameState.PLAYER_ONE)


func _offer_cost(side: int) -> int:
	var offers := offers_for(side)
	if offers.is_empty():
		return 0
	return generator.cost_quarters(str(offers[0]))


func spent_quarters(side: int) -> int:
	return generator.deck_cost_sum(deck(side))


func total_quarters() -> int:
	return _total_quarters


func deck(side: int) -> Array:
	if side == GameState.PLAYER_ONE:
		return _deck_one.duplicate()
	if side == GameState.PLAYER_TWO:
		return _deck_two.duplicate()
	return []


func result() -> Dictionary:
	if not is_complete():
		return {"ok": false, "reason": "Draft incomplet."}
	var valid := generator.deck_cost_sum(_deck_one) == generator.deck_cost_sum(_deck_two) \
		and _deck_one.size() == _deck_size and _deck_two.size() == _deck_size \
		and _lineages_unique(_deck_one) and _lineages_unique(_deck_two) \
		and DeckRules.is_deck_valid(_deck_one, god_one) \
		and DeckRules.is_deck_valid(_deck_two, god_two)
	return {
		"ok": valid,
		"reason": "" if valid else "Les deux decks ne sont pas légaux et égaux.",
		"deck_one": _deck_one.duplicate(),
		"deck_two": _deck_two.duplicate(),
		"total_quarters": generator.deck_cost_sum(_deck_one),
		"total_points": float(generator.deck_cost_sum(_deck_one)) / float(StoneCostRules.COST_SCALE),
		"god_one": god_one,
		"god_two": god_two,
	}


## ─── Deadline et complétion automatique ─────────────────────────────────────

func advance(delta: float) -> bool:
	if not _started or is_complete():
		return false
	_elapsed += maxf(0.0, delta)
	if _elapsed < _duration:
		return false
	auto_complete()
	return true


func remaining_seconds() -> float:
	return maxf(0.0, _duration - _elapsed)


func elapsed_seconds() -> float:
	return _elapsed


func duration_seconds() -> float:
	return _duration


## Complète chaque deck incomplet sans toucher à la progression déjà faite.
func auto_complete() -> void:
	for side in [GameState.PLAYER_ONE, GameState.PLAYER_TWO]:
		var guard := 0
		while _started and not complete_for(side) and guard <= _deck_size:
			guard += 1
			var offers := offers_for(side)
			if offers.is_empty():
				break
			var choice := choose(side, str(offers[0]))
			if not bool(choice.get("ok", false)):
				break


## ─── Vue publique filtrée ───────────────────────────────────────────────────

## Ne contient jamais le choix, le deck ou la progression de deck adverse.
## `own_deck` est la seule projection privée ; elle est calculée pour le camp
## demandeur, y compris côté client après accusé de l'hôte.
func public_state(viewer_side: int) -> Dictionary:
	var own_side := GameState.PLAYER_ONE if viewer_side == GameState.PLAYER_ONE else GameState.PLAYER_TWO
	var other_side := GameState.PLAYER_TWO if own_side == GameState.PLAYER_ONE else GameState.PLAYER_ONE
	var view_step := step_for(own_side)
	# Les deux paires sont indexées sur l'étape du lecteur. L'adversaire peut
	# être en avance ou avoir terminé : sa paire affichée reste celle de cette
	# même position logique, jamais ses offres courantes.
	return {
		"started": _started,
		"complete": is_complete(),
		"own_complete": complete_for(own_side),
		"opponent_complete": complete_for(other_side),
		"step": view_step,
		"own_step": view_step,
		"opponent_step": step_for(other_side),
		"offers_step": view_step,
		"total_steps": _deck_size,
		"cost_quarters": _offer_cost(own_side),
		"total_quarters": _total_quarters,
		"offers_one": offers_for_step(GameState.PLAYER_ONE, view_step),
		"offers_two": offers_for_step(GameState.PLAYER_TWO, view_step),
		"own_side": own_side,
		"own_offers": offers_for_step(own_side, view_step),
		"own_deck": deck(own_side),
		"own_chosen": "",
		"opponent_locked": false,
		"remaining_seconds": remaining_seconds(),
	}


func _current_pair(plan: Array, step: int) -> Array:
	if step < 0 or step >= plan.size():
		return []
	return (plan[step] as Array).duplicate()


## ─── Utilitaires déterministes ──────────────────────────────────────────────

static func _rng(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[swap]
		values[swap] = value
