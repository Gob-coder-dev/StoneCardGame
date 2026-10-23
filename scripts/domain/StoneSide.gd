## Convention commune : les lignes/colonnes du modèle et les axes de l'écran.
class_name StoneSide
extends RefCounted

const ALL: Array[String] = ["top", "bottom", "left", "right"]
const GRID := {"top": Vector2i(-1, 0), "bottom": Vector2i(1, 0),
	"left": Vector2i(0, -1), "right": Vector2i(0, 1)}
const SCREEN := {"top": Vector2.UP, "bottom": Vector2.DOWN,
	"left": Vector2.LEFT, "right": Vector2.RIGHT}
const OPPOSITE := {"top": "bottom", "bottom": "top", "left": "right", "right": "left"}

static func opposite(side: String) -> String:
	assert(OPPOSITE.has(side), "Face inconnue : " + side)
	return OPPOSITE.get(side, "")
