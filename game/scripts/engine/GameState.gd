## GameState.gd
## Représente l'état complet d'une partie de SamStone.
## Classe de pure donnée — aucune règle de jeu ici.
##
## Une case garde l'id de catalogue et, une fois occupée, une BattleStone mutable.
## Cette instance contient uniquement l'état de combat (hasard, statuts, aura et
## boucliers volés). La définition de contenu reste dans StoneLoader.
class_name GameState
extends RefCounted

const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")

## Taille historique et valeur par défaut. La taille effective appartient à
## chaque partie afin que les tutoriels 3×3 n'altèrent jamais le PVP 4×4.
const DEFAULT_BOARD_SIZE: int = 4
const BOARD_SIZE: int = DEFAULT_BOARD_SIZE
const MIN_BOARD_SIZE: int = 3
const MAX_BOARD_SIZE: int = 4

## Identifiants génériques des deux camps. La campagne et le PVP local utilisent
## exactement les mêmes valeurs : PLAYER_ONE est l'hôte en réseau, PLAYER_TWO le
## client. Les anciens noms restent des alias pour ne pas casser la campagne.
const PLAYER_ONE: int = 1
const PLAYER_TWO: int = 2
const PLAYER_HUMAN: int = PLAYER_ONE
const PLAYER_AI: int = PLAYER_TWO
const PLAYER_NONE: int = 0  ## case vide ou bloquée

## Types de cases
const CELL_EMPTY: int = 0
const CELL_BLOCKED: int = -1

## Nombre total de cases (dérivé de BOARD_SIZE)
static func total_cells() -> int:
	return BOARD_SIZE * BOARD_SIZE

## Structure d'une case :
## {
##   "cell_type": CELL_EMPTY | CELL_BLOCKED,
##   "stone_id": String,   # "" si vide
##   "stone": BattleStone, # null si vide
##   "owner": PLAYER_NONE | PLAYER_HUMAN | PLAYER_AI
##   "placed_by": joueur qui a posé la pierre, inchangé par les captures.
##                Information publique : l'IA en déduit les cartes déjà jouées.
## }

## ─── État de la partie ────────────────────────────────────────────────────────

## Le plateau : tableau 1D (index = row * board_size + col).
var board: Array = []
var board_size: int = DEFAULT_BOARD_SIZE

## Mains des joueurs : listes de stone_id (String) uniquement.
var human_hand: Array = []
var ai_hand: Array = []

var current_player: int = PLAYER_HUMAN
var empty_playable_cells: int = 0
var score_human: int = 0
var score_ai: int = 0
var is_game_over: bool = false
var winner: int = PLAYER_NONE
var npc_id: String = ""
var human_god_id: String = ""
var ai_god_id: String = ""

## Générateur déterministe propre à la partie. Son état est cloné avec le
## plateau afin que les simulations n'altèrent jamais le hasard réel.
var random_seed: int = 1
var random_state: int = 1
var next_instance_id: int = 1
## Outil de tirage réutilisé ; random_state reste la valeur clonée et sérialisable.
var _random_generator: RandomNumberGenerator = null


## Le clonage recopie directement les cases ; il n'alloue pas de plateau jetable.
func _init(size: int = DEFAULT_BOARD_SIZE, initialize_board: bool = true) -> void:
	board_size = clampi(size, MIN_BOARD_SIZE, MAX_BOARD_SIZE)
	if initialize_board:
		_reset_board()


## Remet le plateau à zéro (cases vides).
func _reset_board() -> void:
	board.clear()
	for i in range(cell_count()):
		board.append({
			"cell_type": CELL_EMPTY,
			"stone_id": "",
			"stone": null,
			"owner": PLAYER_NONE,
			"placed_by": PLAYER_NONE
		})
	empty_playable_cells = cell_count()
	score_human = 0
	score_ai = 0
	is_game_over = false
	winner = PLAYER_NONE


## Applique une liste de cases bloquées (Array de Vector2i ou [row, col]).
func apply_blocked_cells(blocked: Array) -> void:
	for pos in blocked:
		## Les cases reçues du réseau ont traversé JSON : 1 devient 1.0.
		var row: int = int(pos[0]) if pos is Array else int(pos.x)
		var col: int = int(pos[1]) if pos is Array else int(pos.y)
		if not in_bounds(row, col):
			continue
		var idx: int = index_of(row, col)
		if board[idx]["cell_type"] != CELL_BLOCKED:
			board[idx]["cell_type"] = CELL_BLOCKED
			empty_playable_cells -= 1


## Pose une pierre déjà construite avant le premier tour. Le tutoriel s'en sert
## pour placer une cible de capture ; aucun autre mode n'appelle cette méthode.
func place_initial_stone(row: int, col: int, stone: BattleStone, owner: int) -> bool:
	if stone == null or not in_bounds(row, col):
		return false
	if owner != PLAYER_HUMAN and owner != PLAYER_AI:
		return false
	var cell: Dictionary = board[index_of(row, col)]
	if cell["cell_type"] == CELL_BLOCKED or cell["owner"] != PLAYER_NONE:
		return false
	cell["stone_id"] = stone.stone_id
	cell["stone"] = stone
	cell["owner"] = owner
	cell["placed_by"] = owner
	empty_playable_cells = maxi(0, empty_playable_cells - 1)
	return true


## Installe les mains (listes de stone_id).
func setup_hands(human_stone_ids: Array, ai_stone_ids: Array) -> void:
	human_hand = human_stone_ids.duplicate()
	ai_hand = ai_stone_ids.duplicate()


func set_random_seed(value: int) -> void:
	random_seed = value if value != 0 else 1
	var generator := _rng()
	generator.seed = random_seed
	random_state = generator.state


func draw_random_index(count: int) -> int:
	if count <= 1:
		return 0
	var generator := _rng()
	generator.state = random_state
	var result := generator.randi_range(0, count - 1)
	random_state = generator.state
	return result


func _rng() -> RandomNumberGenerator:
	if _random_generator == null:
		_random_generator = RandomNumberGenerator.new()
	return _random_generator


func take_instance_id() -> int:
	var result := next_instance_id
	next_instance_id += 1
	return result


## ─── Accès au plateau ─────────────────────────────────────────────────────────

func get_cell(row: int, col: int) -> Dictionary:
	return board[index_of(row, col)]


func cell_count() -> int:
	return board_size * board_size


func index_of(row: int, col: int) -> int:
	return row * board_size + col


func in_bounds(row: int, col: int) -> bool:
	return row >= 0 and row < board_size and col >= 0 and col < board_size


func adjacent_positions(row: int, col: int) -> Array:
	var result: Array = []
	if row > 0:
		result.append({"row": row - 1, "col": col, "direction": "top"})
	if row < board_size - 1:
		result.append({"row": row + 1, "col": col, "direction": "bottom"})
	if col > 0:
		result.append({"row": row, "col": col - 1, "direction": "left"})
	if col < board_size - 1:
		result.append({"row": row, "col": col + 1, "direction": "right"})
	return result


## ─── Main du joueur courant (lecture pour l'IA / l'UI) ───────────────────────

func hand_of(player: int) -> Array:
	return human_hand if player == PLAYER_HUMAN else ai_hand


## Dieu équipé par un camp ("" pour une case neutre ou un dieu inconnu).
func god_of(player: int) -> String:
	if player == PLAYER_HUMAN:
		return human_god_id
	if player == PLAYER_AI:
		return ai_god_id
	return ""


## ─── Copie pour l'IA ──────────────────────────────────────────────────────────
## IMPORTANT (choix de game design) : l'IA ne doit PAS connaître le contenu de
## la main du joueur humain. clone_for_ai() masque la main humaine : elle n'en
## garde que la TAILLE (sous forme de placeholders ""), pas les vraies pierres.
## L'IA raisonne donc sur le plateau et sa propre main, en aveugle sur la tienne.
func clone_for_ai() -> GameState:
	var copy := _clone_common()
	## Masquer la main humaine : on garde le nombre de cartes, pas leur identité.
	copy.human_hand = []
	for i in range(human_hand.size()):
		copy.human_hand.append("")
	# Le futur tirage réel n'est pas exposé à l'IA. Elle reçoit un flux
	# reproductible dérivé uniquement de l'état public du plateau.
	copy.set_random_seed(hash(_public_position_key()))
	return copy


## Copie complète et fidèle (debug, tests, ou usage interne).
func clone() -> GameState:
	var copy := _clone_common()
	copy.human_hand = human_hand.duplicate()
	return copy


func _clone_common() -> GameState:
	var copy := GameState.new(board_size, false)
	for cell in board:
		# Une case ne contient que des valeurs simples et sa pierre, copiée à part.
		var cloned_cell: Dictionary = cell.duplicate()
		var stone = cell.get("stone")
		cloned_cell["stone"] = stone.clone() if stone is BattleStoneModel else null
		copy.board.append(cloned_cell)
	copy.ai_hand = ai_hand.duplicate()
	copy.current_player = current_player
	copy.empty_playable_cells = empty_playable_cells
	copy.score_human = score_human
	copy.score_ai = score_ai
	copy.is_game_over = is_game_over
	copy.winner = winner
	copy.npc_id = npc_id
	copy.human_god_id = human_god_id
	copy.ai_god_id = ai_god_id
	copy.random_seed = random_seed
	copy.random_state = random_state
	copy.next_instance_id = next_instance_id
	return copy


func _public_position_key() -> String:
	var parts: Array[String] = [str(board_size), str(current_player), str(empty_playable_cells)]
	for cell in board:
		parts.append("%s:%s" % [cell.get("stone_id", ""), cell.get("owner", PLAYER_NONE)])
	for stone_id in ai_hand:
		parts.append(str(stone_id))
	return "|".join(parts)
