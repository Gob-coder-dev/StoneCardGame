## Cycle de vie commun des révélations d'une carte. Aucun calcul de règles.
extends Control
signal reveal_finished
const Symbols := preload("res://scripts/ui/StoneSymbols.gd")
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		_update_preview()
		queue_redraw()
var _card: StoneCard
var _card_transform := Transform2D.IDENTITY
var _center := Vector2.ZERO
var _square: float = 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 20

func _prepare(card: StoneCard) -> void:
	_card = card
	_card_transform = get_global_transform().affine_inverse() * card.get_global_transform()
	_center = _card_transform * (card.size * 0.5)
	_square = minf(card.size.x, card.size.y)

func _start(duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "progress", 1.0, duration)
	tween.tween_callback(_finish)

func _update_preview() -> void:
	pass

func _restore_preview() -> void:
	if is_instance_valid(_card):
		_card.set_combat_preview(null)

func _finish() -> void:
	_restore_preview()
	reveal_finished.emit()
	queue_free()

func _exit_tree() -> void:
	_restore_preview()

func _draw_caption(value: String, color: Color) -> void:
	var rect := Rect2(_center + Vector2(-_square * 0.38, _square * 0.23), Vector2(_square * 0.76, _square * 0.16))
	draw_rect(rect, Color("#20152def"))
	Symbols.draw_text(self, rect.get_center(), _square * 0.065, value, color)
