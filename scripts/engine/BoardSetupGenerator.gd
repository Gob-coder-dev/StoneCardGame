## Tirages qui précèdent le match : terrain et premier joueur.
## L'écran d'avant-combat anime le résultat ; il ne tire rien lui-même.
class_name BoardSetupGenerator
extends RefCounted
const CHANCE_NO_BLOCK := 45

static func generate() -> Array:
	if randi() % 100 < CHANCE_NO_BLOCK:
		return []  ## plateau ouvert
	## Une case bloquée, à une position aléatoire du terrain.
	var size := GameState.BOARD_SIZE
	var row := randi() % size
	var col := randi() % size
	return [[row, col]]


## Pile ou face du premier joueur : une chance sur deux pour chaque camp.
static func draw_first_player() -> int:
	return GameState.PLAYER_HUMAN if randi() % 2 == 0 else GameState.PLAYER_AI
