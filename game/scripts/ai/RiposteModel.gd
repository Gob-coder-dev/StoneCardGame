## Estime la riposte immédiate depuis les seules informations visibles par l'IA.
## Prépare une fois les tirs et réutilise ceux dont la ligne n'a pas changé.
## Ce modèle reste une estimation : sans lames roses ni aura reçue à la pose.
extends RefCounted

const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const Resolver := preload("res://scripts/engine/CombatResolver.gd")
const Opponent := preload("res://scripts/ai/OpponentModel.gd")

var _state: GameState
var _possible_cards: Array[String] = []
## Un tir représente une direction et ses lames normales / longues.
var _shots: Array[BattleStoneModel] = []
## Par carte : les indices des tirs de chacune de ses orientations possibles.
var _threat_cards: Array = []
var _hand_size := 0
var _shot_sides := PackedInt32Array()
## Par case et direction : les cases traversées jusqu'au bord.
var _lines: Array = []
## Type, propriétaire et défenses de chaque case avant les simulations.
var _base_signatures: Array = []
## Captures de chaque tir depuis chaque case libre de l'état initial.
var _base_hits := {}
var _shot_indices := {}

enum PreparationPhase { CARDS, LINES, SIGNATURES, HITS, DONE }
var _preparation_phase := PreparationPhase.CARDS
var _preparation_index := 0
var _free_cells: Array = []


func _init(state: GameState) -> void:
	_state = state
	_possible_cards = Opponent.possible_cards(state)
	_hand_size = state.human_hand.size()


## Prépare le modèle par unités bornées : une carte, une case ou un ensemble de
## tirs de case. MoveSearch peut ainsi rendre la main entre deux unités.
func prepare_step(budget_usec: int = 0) -> bool:
	if is_prepared():
		return true
	var started := Time.get_ticks_usec()
	var did_work := false
	while not is_prepared():
		if did_work and budget_usec > 0 \
				and Time.get_ticks_usec() - started >= budget_usec:
			return false
		_prepare_next_unit()
		did_work = true
	return true


func is_prepared() -> bool:
	return _preparation_phase == PreparationPhase.DONE


func _prepare_next_unit() -> void:
	match _preparation_phase:
		PreparationPhase.CARDS:
			if _preparation_index < _possible_cards.size():
				_prepare_card(_possible_cards[_preparation_index])
				_preparation_index += 1
				return
			_advance_preparation(PreparationPhase.LINES)
		PreparationPhase.LINES:
			if _preparation_index < _state.cell_count():
				_prepare_line(_preparation_index)
				_preparation_index += 1
				return
			_advance_preparation(PreparationPhase.SIGNATURES)
		PreparationPhase.SIGNATURES:
			if _preparation_index < _state.board.size():
				_base_signatures.append(_cell_signature(_state.board[_preparation_index]))
				_preparation_index += 1
				return
			_free_cells = RulesEngine.get_free_cells(_state)
			_advance_preparation(PreparationPhase.HITS)
		PreparationPhase.HITS:
			if _preparation_index < _free_cells.size():
				var cell: Dictionary = _free_cells[_preparation_index]
				_base_hits[_state.index_of(cell["row"], cell["col"])] = \
					_shot_hits(_state, cell["row"], cell["col"])
				_preparation_index += 1
				return
			_advance_preparation(PreparationPhase.DONE)


func _advance_preparation(next_phase: PreparationPhase) -> void:
	_preparation_phase = next_phase
	_preparation_index = 0


func _prepare_card(stone_id: String) -> void:
	var orientations: Array = []
	for stone in Opponent.attack_variants_for(stone_id):
		var shots := PackedInt32Array()
		for side in StoneSide.ALL:
			var normal_count: int = stone.normal_blades(side)
			var long_count: int = int(stone.long_blades.get(side, 0))
			if normal_count + long_count == 0:
				continue
			var key := "%s:%d:%d" % [side, normal_count, long_count]
			if not _shot_indices.has(key):
				_shot_indices[key] = _shots.size()
				_shots.append(make_shot(side, normal_count, long_count))
				_shot_sides.append(StoneSide.ALL.find(side))
			shots.append(_shot_indices[key])
		orientations.append(shots)
	_threat_cards.append(orientations)


## Prépare la ligne d'une case indépendamment des cartes envisagées.
func _prepare_line(index: int) -> void:
	var row := floori(float(index) / _state.board_size)
	var col := index % _state.board_size
	var per_side: Array = []
	for side in StoneSide.ALL:
		var delta: Vector2i = StoneSide.GRID[side]
		var line := PackedInt32Array()
		var r := row + delta.x
		var c := col + delta.y
		while r >= 0 and r < _state.board_size \
				and c >= 0 and c < _state.board_size:
			line.append(_state.index_of(r, c))
			r += delta.x
			c += delta.y
		per_side.append(line)
	_lines.append(per_side)


## Toutes les données d'une case qui peuvent changer le résultat d'un tir.
static func _cell_signature(cell: Dictionary) -> Array:
	var signature: Array = [cell["cell_type"], cell["owner"]]
	var stone = cell["stone"]
	for side in StoneSide.ALL:
		signature.append(stone.defense(side) if stone is BattleStoneModel else 0)
	return signature

func _shot_hits(state: GameState, row: int, col: int) -> PackedInt32Array:
	var hits := PackedInt32Array()
	hits.resize(_shots.size())
	for index in range(_shots.size()):
		hits[index] = Resolver.find_captures(state, row, col, GameState.PLAYER_HUMAN, _shots[index]).size()
	return hits

## Pierre qui n'attaque que dans une direction ; les tests comparent ces tirs
## à l'attaque d'une carte entière avec le même résolveur.
static func make_shot(side: String, normal_count: int, long_count: int) -> BattleStoneModel:
	var shot: BattleStoneModel = BattleStoneModel.new()
	shot.configure("", {"blades": {side: normal_count}, "long_blades": {side: long_count}})
	return shot

## Espérance de la meilleure riposte d'une main cachée. Conserve exactement
## les mêmes poids et orientations que le calcul sans réutilisation des tirs.
func threat(simulation: GameState) -> float:
	if not is_prepared():
		prepare_step()
	if _threat_cards.is_empty() or _hand_size <= 0:
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
		var cell_index := simulation.index_of(cell["row"], cell["col"])
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
	return Opponent.expected_from_variants(_possible_cards, values, _hand_size)
