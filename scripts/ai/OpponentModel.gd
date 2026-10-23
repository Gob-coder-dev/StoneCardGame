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
			placed[cell["stone_id"]] = true
	var result: Array[String] = []
	for definition in definitions:
		var stone_id := str(definition["id"])
		if not placed.has(stone_id):
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
