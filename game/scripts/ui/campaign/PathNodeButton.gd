## Comportements visuels communs des boutons de parcours : pulsation et cadenas.
## Les états de progression et les styles appartiennent aux vues spécialisées.
extends "res://scripts/ui/input/TouchButton.gd"

var _pulse := 0.0
var _pulse_tween: Tween = null


func _process(_delta: float) -> void:
	queue_redraw()


func _set_pulse(enabled: bool) -> void:
	set_process(enabled)
	if enabled:
		if _pulse_tween == null:
			_pulse_tween = create_tween().set_loops()
			for value in [1.0, 0.0]:
				_pulse_tween.tween_property(self, "_pulse", value, 1.3) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		return
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	_pulse = 0.0
	queue_redraw()


func _draw_lock(center: Vector2, radius: float) -> void:
	var ink := UITheme.COL_NODE_LOCKED_TEXT
	var body := Rect2(center + Vector2(-radius * 0.26, radius * 0.02),
		Vector2(radius * 0.52, radius * 0.38))
	draw_rect(body, UITheme.COL_NODE_LOCKED_BG, true)
	draw_rect(body, ink, false, 3.0)
	var shackle_center := center + Vector2(0.0, -radius * 0.18)
	draw_arc(shackle_center, radius * 0.18, PI, TAU, 24, ink, 3.0, true)
	draw_circle(center + Vector2(0.0, radius * 0.17), radius * 0.045, ink)
