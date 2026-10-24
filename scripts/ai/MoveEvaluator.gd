## Orchestre la valeur d'un coup, en captures, sur une copie de la partie.
## RiposteModel estime la menace ; EndgameSearch explore les derniers placements.
## Les graines de simulation ne révèlent ni ne consomment le hasard réel.
extends RefCounted

const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const Resolver := preload("res://scripts/engine/CombatResolver.gd")
const Opponent := preload("res://scripts/ai/OpponentModel.gd")
const Riposte := preload("res://scripts/ai/RiposteModel.gd")
const Endgame := preload("res://scripts/ai/EndgameSearch.gd")

const RANDOM_SAMPLES := 4
const ENDGAME_RANDOM_SAMPLES := 2
const ENDGAME_CELLS := 2
const RISK_WEIGHT := 1.0
## Valeur d'une lame d'aura conservée pour les coups suivants, en captures.
const AURA_WEIGHT := 0.3

var _state: GameState
var _anticipation := false
var _endgame := false
var _riposte: Riposte
var _possible_cards: Array[String] = []
var _hand_size := 0
var _aura_before := 0


func _init(state: GameState, anticipation: bool) -> void:
	_state = state
	_anticipation = anticipation
	if not anticipation:
		return
	_endgame = state.empty_playable_cells <= ENDGAME_CELLS
	if _endgame:
		_possible_cards = Opponent.possible_cards(state)
		_hand_size = state.human_hand.size()
	else:
		_aura_before = aura_blades(state)
		_riposte = Riposte.new(state)


func is_endgame() -> bool:
	return _endgame

## Nombre de tirages d'un coup dont la simulation consomme du hasard.
func random_samples() -> int:
	return ENDGAME_RANDOM_SAMPLES if _endgame else RANDOM_SAMPLES

## Le placement utilise toujours le moteur commun, puis le modèle adapté à
## l'avancement du match. La détection du hasard et les graines restent inchangées.
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
		value = Endgame.evaluate(simulation, _hand_size)
	else:
		value = float(result.get("captures", []).size())
		if _anticipation:
			value -= RISK_WEIGHT * _riposte.threat(simulation)
			value += AURA_WEIGHT * (aura_blades(simulation) - _aura_before)
	return {"value": value, "random": used_random}

## Lames d'aura portées par l'IA, avant ou après son placement.
static func aura_blades(state: GameState) -> int:
	var total := 0
	for cell in state.board:
		var stone = cell["stone"]
		if cell["owner"] == GameState.PLAYER_AI and stone is BattleStoneModel:
			for side in StoneSide.ALL:
				total += int(stone.swarm_blades[side])
	return total
