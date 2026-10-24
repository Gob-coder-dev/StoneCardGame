## Ce que l'IA peut savoir de la main humaine sans la voir : les cartes que le
## dieu du joueur autorise (sa famille et les neutres), moins celles qu'il a déjà
## posées. Le dieu et l'auteur de chaque pose sont des informations publiques.
extends RefCounted

const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const CoinFlip := preload("res://scripts/engine/effects/CoinFlipEffect.gd")


## Cartes que le joueur humain peut encore avoir en main. Avec un dieu inconnu,
## toutes les cartes du catalogue restent possibles.
static func possible_cards(state: GameState) -> Array[String]:
	var definitions := StoneLoader.get_stones_for_god(state.human_god_id)
	if definitions.is_empty():
		definitions = StoneLoader.get_all_stones()
	var placed := {}
	for cell in state.board:
		if cell["placed_by"] == GameState.PLAYER_HUMAN:
			placed[StoneLoader.stone_lineage(str(cell["stone_id"]))] = true
	var result: Array[String] = []
	for definition in definitions:
		var stone_id := str(definition["id"])
		if not placed.has(StoneLoader.stone_lineage(stone_id)):
			result.append(stone_id)
	return result


## La main cachée est vue comme hand_size cartes tirées parmi card_count cartes
## possibles. Si l'on classe ces cartes de la plus utile au joueur à la moins
## utile, la k-ième (k = 0 pour la première) est la meilleure carte de sa main
## avec la probabilité C(card_count − 1 − k, hand_size − 1) / C(card_count, hand_size).
## Ces poids, de somme 1, donnent l'espérance de sa meilleure riposte.
static func rank_weights(card_count: int, hand_size: int) -> PackedFloat64Array:
	var weights := PackedFloat64Array()
	var held := mini(hand_size, card_count)
	if held <= 0:
		return weights
	weights.resize(card_count)
	var weight := float(held) / card_count
	for rank in range(card_count):
		weights[rank] = weight
		var remaining := card_count - 1 - rank
		weight = 0.0 if remaining <= 0 else weight * maxi(0, remaining - held + 1) / remaining
	return weights


## Espérance de la meilleure valeur d'une main, les valeurs étant déjà classées
## de la plus utile au joueur à la moins utile.
static func expected_best(ranked_values: Array[float], weights: PackedFloat64Array) -> float:
	var total := 0.0
	for rank in range(mini(ranked_values.size(), weights.size())):
		total += ranked_values[rank] * weights[rank]
	return total


## Hypothèse explicite : lignées équiprobables sans remise, puis un niveau
## équiprobable par lignée. Une main ne contient jamais deux formes du même être.
## La distribution du meilleur résultat est calculée exactement, sans énumérer
## les mains : coefficient de degré h du produit ∏(1 + F_lignée * t).
static func expected_from_variants(card_ids: Array, values: Array[float], hand_size: int, prefer_high: bool = true) -> float:
	if card_ids.is_empty() or hand_size <= 0:
		return 0.0
	var groups := {}
	var group_ids: Array[String] = []
	for card in card_ids:
		var group := StoneLoader.stone_lineage(str(card))
		group_ids.append(group)
		groups[group] = int(groups.get(group, 0)) + 1
	var held := mini(hand_size, groups.size())
	var order: Array[int] = []
	for index in range(card_ids.size()):
		order.append(index)
	order.sort_custom(func(a: int, b: int): return values[a] < values[b] if prefer_high else values[a] > values[b])
	# Le cas historique garde son calcul et son coût, sans polynôme supplémentaire.
	if groups.size() == card_ids.size():
		var ranked: Array[float] = []
		for index in order:
			ranked.push_front(values[index])
		return expected_best(ranked, rank_weights(ranked.size(), held))
	var denominator := 1.0
	for index in range(1, held + 1):
		denominator *= float(groups.size() - held + index) / index
	var coefficients := PackedFloat64Array()
	coefficients.resize(held + 1)
	coefficients[0] = 1.0
	var fractions := {}
	var previous_probability := 0.0
	var expected := 0.0
	for index in order:
		var group := group_ids[index]
		var previous_fraction := float(fractions.get(group, 0.0))
		var next_fraction := previous_fraction + 1.0 / int(groups[group])
		# Retirer l'ancien facteur puis ajouter le nouveau, en O(taille de main).
		var quotient_previous := 1.0
		for degree in range(1, held + 1):
			var quotient := coefficients[degree] - previous_fraction * quotient_previous
			coefficients[degree] = quotient + next_fraction * quotient_previous
			quotient_previous = quotient
		fractions[group] = next_fraction
		var probability := clampf(coefficients[held] / denominator, previous_probability, 1.0)
		expected += values[index] * (probability - previous_probability)
		previous_probability = probability
	return expected


## Pierres prêtes à attaquer, une liste d'orientations par carte. Un pile ou
## face donne ses deux issues, également probables. Les lames roses, tirées à
## la pose, ne sont pas ajoutées : la menace de ces cartes est sous-estimée.
static func attack_variants(card_ids: Array[String]) -> Array:
	var result: Array = []
	for stone_id in card_ids:
		var definition := StoneLoader.get_stone(stone_id)
		var stone: BattleStoneModel = BattleStoneModel.new()
		stone.configure(stone_id, definition)
		var variants: Array = [stone]
		var axis := str(definition.get("coin_flip", ""))
		if axis != "":
			var flipped: BattleStoneModel = stone.clone()
			CoinFlip.apply_outcome(flipped, axis, true)
			variants.append(flipped)
		result.append(variants)
	return result
