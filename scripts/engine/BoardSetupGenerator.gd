## Création du terrain avant le début du match.
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
