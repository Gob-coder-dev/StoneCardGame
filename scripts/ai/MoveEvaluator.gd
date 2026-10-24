## Valeur d'un coup de l'IA, en nombre de captures. Le coup est joué par le
## résolveur de la partie sur une copie de l'état reçu par l'IA :
## - gain : captures du coup ;
## - avec anticipation : moins la riposte attendue de l'adversaire, c'est-à-dire
##   la meilleure riposte de sa main, en moyenne sur les mains possibles ;
## - avec anticipation, à ENDGAME_CELLS cases libres ou moins : calcul exact
##   jusqu'à la fin de la partie, chaque riposte étant pondérée de la même façon.
## Chaque tirage fixe le hasard de la copie : un coup qui utilise le hasard est
## évalué en moyenne sur plusieurs tirages, sans jamais lire le hasard réel.
extends RefCounted

const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const Resolver := preload("res://scripts/engine/CombatResolver.gd")
const Opponent := preload("res://scripts/ai/OpponentModel.gd")

## Tirages d'un coup aléatoire (Fortune, Pillage…), hors fin de partie. Sur le
## plateau 4×4, ces coups représentaient l'essentiel des réflexions les plus
## longues : 4 tirages suffisent pour classer les coups.
const RANDOM_SAMPLES := 4
## En fin de partie, chaque tirage explore tout l'arbre restant.
const ENDGAME_RANDOM_SAMPLES := 2
## Le calcul exact pose réellement chaque carte possible de l'adversaire : son
## coût grandit avec la collection. À deux cases, il reste court ; à trois, il
## coûtait déjà 0,2 s sur PC avec 20 cartes possibles, sans gain mesuré.
const ENDGAME_CELLS := 2
## Poids de la riposte : une capture subie compte autant qu'une capture gagnée.
const RISK_WEIGHT := 1.0
## Valeur, en captures, d'une lame d'aura d'Essaim gagnée par l'IA : l'aura
## reste tant que le groupe tient et servira aux coups suivants. Sans ce bonus,
## l'IA ne la comptait que pour la capture ou la défense immédiates.
const AURA_WEIGHT := 0.3

var _state: GameState
var _anticipation := false
var _endgame := false
## Cartes que l'adversaire peut avoir, et nombre de cartes de sa main.
var _possible_cards: Array[String] = []
var _hand_size := 0
## Riposte immédiate, préparée une seule fois. Une attaque est un plan pur où
## chaque direction est un tir indépendant (AttackResolver). Chaque carte
## possible est donc découpée en tirs (face, lames, lames bleues) : un même tir
## sert à toutes les cartes qui le partagent. Le calcul dépend du nombre de tirs
## différents, qui plafonne (14 par face), plutôt que du nombre de cartes.
var _shots: Array[BattleStoneModel] = []
## Par carte possible : ses orientations (deux pour un pile ou face), chacune
## donnée par les indices de ses tirs dans _shots.
var _threat_cards: Array = []
var _threat_weights := PackedFloat64Array()
## Aura d'Essaim de l'IA avant le coup évalué.
var _aura_before := 0
## Réutilisation entre les coups : un coup ne change que quelques cases (la
## pose, ses captures, les auras et défenses touchées). Un tir ne regarde que
## sa propre ligne, dans sa propre direction : si aucune case de cette ligne
## n'a changé, ses captures sont celles déjà comptées sur l'état reçu.
var _shot_sides := PackedInt32Array()
## Par case : pour chaque face (ordre de StoneSide.ALL), les cases de sa ligne.
var _lines: Array = []
## Signature de chaque case de l'état reçu (voir _cell_signature).
var _base_signatures: Array = []
## Par case libre de l'état reçu : les captures de chaque tir.
var _base_hits := {}


func _init(state: GameState, anticipation: bool) -> void:
	_state = state
	_anticipation = anticipation
	if not anticipation:
		return
	_possible_cards = Opponent.possible_cards(state)
	_hand_size = state.human_hand.size()
	_endgame = state.empty_playable_cells <= ENDGAME_CELLS
	if not _endgame:
		_aura_before = aura_blades(state)
		_prepare_threats()
		_threat_weights = Opponent.rank_weights(_possible_cards.size(), _hand_size)


func _prepare_threats() -> void:
	var shot_indices := {}
	for variants in Opponent.attack_variants(_possible_cards):
		var orientations: Array = []
		for stone in variants:
			var shots := PackedInt32Array()
			for side in StoneSide.ALL:
				var normal_count: int = stone.normal_blades(side)
				var long_count: int = int(stone.long_blades.get(side, 0))
				if normal_count + long_count == 0:
					continue
				var key := "%s:%d:%d" % [side, normal_count, long_count]
				if not shot_indices.has(key):
					shot_indices[key] = _shots.size()
					_shots.append(make_shot(side, normal_count, long_count))
					_shot_sides.append(StoneSide.ALL.find(side))
				shots.append(shot_indices[key])
			orientations.append(shots)
		_threat_cards.append(orientations)
	_prepare_lines()
	for index in range(_state.board.size()):
		_base_signatures.append(_cell_signature(_state.board[index]))
	for cell in RulesEngine.get_free_cells(_state):
		_base_hits[GameState.cell_index(cell["row"], cell["col"])] = _shot_hits(_state, cell["row"], cell["col"])


## Cases rencontrées depuis chaque case vers chaque face, jusqu'au bord.
func _prepare_lines() -> void:
	for index in range(GameState.total_cells()):
		var row := index / GameState.BOARD_SIZE
		var col := index % GameState.BOARD_SIZE
		var per_side: Array = []
		for side in StoneSide.ALL:
			var delta: Vector2i = StoneSide.GRID[side]
			var line := PackedInt32Array()
			var r := row + delta.x
			var c := col + delta.y
			while r >= 0 and r < GameState.BOARD_SIZE and c >= 0 and c < GameState.BOARD_SIZE:
				line.append(GameState.cell_index(r, c))
				r += delta.x
				c += delta.y
			per_side.append(line)
		_lines.append(per_side)


## Ce qu'un tir peut lire d'une case : son type, son camp et la défense de
## chaque face de sa pierre.
static func _cell_signature(cell: Dictionary) -> Array:
	var signature: Array = [cell["cell_type"], cell["owner"]]
	var stone = cell["stone"]
	for side in StoneSide.ALL:
		signature.append(stone.defense(side) if stone is BattleStoneModel else 0)
	return signature


## Captures de chaque tir depuis une case, demandées au résolveur.
func _shot_hits(state: GameState, row: int, col: int) -> PackedInt32Array:
	var hits := PackedInt32Array()
	hits.resize(_shots.size())
	for index in range(_shots.size()):
		hits[index] = Resolver.find_captures(state, row, col, GameState.PLAYER_HUMAN, _shots[index]).size()
	return hits


## Pierre qui n'attaque que dans une direction, avec ces lames et lames bleues.
static func make_shot(side: String, normal_count: int, long_count: int) -> BattleStoneModel:
	var shot: BattleStoneModel = BattleStoneModel.new()
	shot.configure("", {"blades": {side: normal_count}, "long_blades": {side: long_count}})
	return shot


func is_endgame() -> bool:
	return _endgame


## Nombre total de tirages d'un coup dont la simulation a utilisé le hasard.
func random_samples() -> int:
	return ENDGAME_RANDOM_SAMPLES if _endgame else RANDOM_SAMPLES


## Évalue un tirage d'un coup : { "value": float, "random": bool }.
## "random" signale que le coup a consommé du hasard et mérite d'autres tirages.
func evaluate(move: Dictionary, sample: int) -> Dictionary:
	var stone_id: String = move["stone_id"]
	var row: int = move["row"]
	var col: int = move["col"]
	var simulation := _state.clone()
	simulation.set_random_seed(hash("preview:%s:%d:%d:%d" % [stone_id, row, col, sample]))
	var seeded_state := simulation.random_state
	var result := Resolver.apply_move(simulation, row, col, stone_id, GameState.PLAYER_AI)
	var used_random := simulation.random_state != seeded_state
	var value: float
	if _endgame:
		# Les coups adverses sont choisis parmi toutes ses cartes possibles.
		simulation.human_hand = _possible_cards.duplicate()
		value = _human_turn_value(simulation, _hand_size)
	else:
		value = float(result.get("captures", []).size())
		if _anticipation:
			value -= RISK_WEIGHT * threat(simulation)
			value += AURA_WEIGHT * (aura_blades(simulation) - _aura_before)
	return {"value": value, "random": used_random}


## Lames d'aura d'Essaim portées par les pierres de l'IA.
static func aura_blades(state: GameState) -> int:
	var total := 0
	for cell in state.board:
		var stone = cell["stone"]
		if cell["owner"] == GameState.PLAYER_AI and stone is BattleStoneModel:
			for side in StoneSide.ALL:
				total += int(stone.swarm_blades[side])
	return total


## Riposte attendue : pour chaque carte possible, le plus grand nombre de
## pierres de l'IA qu'elle capturerait aussitôt depuis une case libre (les deux
## orientations d'un pile ou face comptent chacune pour moitié), puis la
## meilleure de ces valeurs dans la main adverse, en moyenne sur ses mains possibles.
func threat(simulation: GameState) -> float:
	if _threat_cards.is_empty() or _threat_weights.is_empty():
		return 0.0
	var best := PackedFloat64Array()
	best.resize(_threat_cards.size())
	var hits := PackedInt32Array()
	hits.resize(_shots.size())
	var changed := PackedByteArray()
	changed.resize(simulation.board.size())
	for index in range(simulation.board.size()):
		changed[index] = 1 if _cell_signature(simulation.board[index]) != _base_signatures[index] else 0
	var dirty_sides := PackedByteArray()
	dirty_sides.resize(StoneSide.ALL.size())
	for cell in RulesEngine.get_free_cells(simulation):
		var cell_index := GameState.cell_index(cell["row"], cell["col"])
		var lines: Array = _lines[cell_index]
		for side in range(lines.size()):
			dirty_sides[side] = 0
			for crossed in lines[side]:
				if changed[crossed] == 1:
					dirty_sides[side] = 1
					break
		var base: PackedInt32Array = _base_hits[cell_index]
		var any_hit := false
		for index in range(_shots.size()):
			if dirty_sides[_shot_sides[index]] == 1:
				hits[index] = Resolver.find_captures(simulation, cell["row"], cell["col"],
					GameState.PLAYER_HUMAN, _shots[index]).size()
			else:
				hits[index] = base[index]
			any_hit = any_hit or hits[index] > 0
		if not any_hit:
			continue
		for card in range(_threat_cards.size()):
			var orientations: Array = _threat_cards[card]
			var total := 0
			for shots in orientations:
				for index in shots:
					total += hits[index]
			best[card] = maxf(best[card], float(total) / orientations.size())
	var values: Array[float] = []
	for value in best:
		values.append(value)
	values.sort()
	values.reverse()
	return Opponent.expected_best(values, _threat_weights)


## Fin de partie, au tour de l'IA : son meilleur coup (élagage alpha-bêta).
func _ai_turn_value(simulation: GameState, hand_size: int, alpha: float, beta: float) -> float:
	var moves := RulesEngine.get_valid_moves(simulation, GameState.PLAYER_AI)
	if moves.is_empty():
		return _final_value(simulation)
	var best := -INF
	for move in moves:
		var child := simulation.clone()
		Resolver.apply_move(child, move["row"], move["col"], move["stone_id"], GameState.PLAYER_AI)
		best = maxf(best, _human_turn_value(child, hand_size))
		alpha = maxf(alpha, best)
		if alpha >= beta:
			break
	return best


## Fin de partie, au tour de l'adversaire : chaque carte possible donne sa
## meilleure riposte, puis la meilleure de sa main est prise en moyenne sur les
## mains possibles, comme pour threat().
func _human_turn_value(simulation: GameState, hand_size: int) -> float:
	var cards: Array = simulation.human_hand.duplicate()
	var free_cells := RulesEngine.get_free_cells(simulation)
	if cards.is_empty() or hand_size <= 0 or free_cells.is_empty():
		return _final_value(simulation)
	var values: Array[float] = []
	for card in cards:
		var best := INF
		for cell in free_cells:
			var child := simulation.clone()
			Resolver.apply_move(child, cell["row"], cell["col"], card, GameState.PLAYER_HUMAN)
			# Seule une riposte plus forte que la meilleure trouvée pour cette carte compte.
			best = minf(best, _ai_turn_value(child, hand_size - 1, -INF, best))
		values.append(best)
	values.sort()
	return Opponent.expected_best(values, Opponent.rank_weights(cards.size(), hand_size))


## Écart final des scores, divisé par deux pour rester en captures (une capture
## change l'écart de deux points).
func _final_value(simulation: GameState) -> float:
	var score := RulesEngine.calculate_score(simulation)
	return (score["ai"] - score["human"]) / 2.0
