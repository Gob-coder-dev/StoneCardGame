## ParchmentBackground.gd
## Fond décoratif réutilisable : parchemin sombre + soleil rouge + pétales.
## À placer comme premier enfant (Control) d'un écran, ancré en plein écran.
## Dessine tout par code, aucun asset requis.
@tool
class_name ParchmentBackground
extends Control

const COL_TOP := Color("#2a1a0e")
const COL_BOTTOM := Color("#120a05")
const COL_SUN := Color("#7a1512")
const COL_SUN_RING := Color("#b8923e")
const COL_PETAL := Color("#e89ab0")

## Petites positions de pétales (ratio de la taille)
var _petals := [
	Vector2(0.14, 0.14), Vector2(0.85, 0.21), Vector2(0.27, 0.38),
	Vector2(0.75, 0.42), Vector2(0.09, 0.60), Vector2(0.91, 0.64),
	Vector2(0.40, 0.80), Vector2(0.62, 0.88)
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y

	# Fond vertical dégradé (approximé par bandes)
	var bands := 32
	for i in range(bands):
		var t := float(i) / float(bands - 1)
		var col := COL_TOP.lerp(COL_BOTTOM, t)
		## La hauteur suit le même pas que la position afin que deux bandes
		## consécutives se chevauchent légèrement sans laisser de ligne vide.
		draw_rect(Rect2(0, h * t, w, h / float(bands - 1) + 1.0), col, true)

	# Soleil rouge
	var sun_center := Vector2(w * 0.5, h * 0.24)
	var sun_r: float = min(w, h) * 0.22
	draw_circle(sun_center, sun_r, Color(COL_SUN.r, COL_SUN.g, COL_SUN.b, 0.35))
	draw_arc(sun_center, sun_r, 0, TAU, 64, Color(COL_SUN_RING.r, COL_SUN_RING.g, COL_SUN_RING.b, 0.5), 4.0)

	# Pétales (taille proportionnelle à la largeur du canevas)
	var petal_r: float = w * 0.012
	for p in _petals:
		var pos := Vector2(p.x * w, p.y * h)
		draw_circle(pos, petal_r, Color(COL_PETAL.r, COL_PETAL.g, COL_PETAL.b, 0.55))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
