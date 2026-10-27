## Tirages qui précèdent le match : terrain et premier joueur.
## L'écran d'avant-combat anime le résultat ; il ne tire rien lui-même.
class_name BoardSetupGenerator
extends RefCounted
## Chances, en pourcentage, d'un plateau sans case bloquée puis avec une seule ;
## le reste du temps, deux cases différentes sont bloquées.
const CHANCE_NO_BLOCK := 40
const CHANCE_ONE_BLOCK := 35

static func generate() -> Array:
	var roll := randi() % 100
	var count := 0 if roll < CHANCE_NO_BLOCK else (1 if roll < CHANCE_NO_BLOCK + CHANCE_ONE_BLOCK else 2)
	var cells: Array = []
	for index in range(GameState.total_cells()):
		cells.append([index / GameState.BOARD_SIZE, index % GameState.BOARD_SIZE])
	var blocked: Array = []
	for i in range(count):
		blocked.append(cells.pop_at(randi() % cells.size()))
	return blocked


## Pile ou face du premier joueur : une chance sur deux pour chaque camp.
static func draw_first_player() -> int:
	return GameState.PLAYER_HUMAN if randi() % 2 == 0 else GameState.PLAYER_AI
