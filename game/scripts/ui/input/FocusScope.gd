## Cycle de navigation d’une modale et retour au contrôle qui l’a ouverte.
extends RefCounted

var _opener: WeakRef


func capture(scope: Control, fallback: Control = null) -> void:
	var current := scope.get_viewport().gui_get_focus_owner()
	if current == scope or (current != null and scope.is_ancestor_of(current)):
		return
	var opener := fallback if can_focus(fallback) else current
	_opener = weakref(opener) if opener != null else null


func restore() -> void:
	var opener := _opener.get_ref() as Control if _opener != null else null
	_opener = null
	if can_focus(opener):
		opener.grab_focus()


func handle(event: InputEvent, controls: Array[Control], viewport: Viewport) -> void:
	var direction := navigation_step(event)
	if direction == 0:
		return
	var available := controls.filter(can_focus)
	if not available.is_empty():
		var current := available.find(viewport.gui_get_focus_owner())
		var next := posmod(current + direction, available.size()) if current >= 0 \
			else (0 if direction > 0 else available.size() - 1)
		available[next].grab_focus()
	viewport.set_input_as_handled()


static func can_focus(control: Control) -> bool:
	return is_instance_valid(control) and not control.is_queued_for_deletion() and control.is_visible_in_tree() \
		and control.focus_mode == Control.FOCUS_ALL \
		and not (control is BaseButton and control.disabled)


static func navigation_step(event: InputEvent) -> int:
	if event.is_action_pressed("ui_focus_prev", true, true) \
			or event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_up", true):
		return -1
	if event.is_action_pressed("ui_focus_next", true, true) \
			or event.is_action_pressed("ui_right", true) or event.is_action_pressed("ui_down", true):
		return 1
	return 0
