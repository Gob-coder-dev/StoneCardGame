## Barrière de fin pour plusieurs animations jouées simultanément.
extends RefCounted
signal finished
var _pending: int = 0
var _sealed: bool = false
var completed: bool = false

func track(animation: Signal) -> void:
	_pending += 1
	animation.connect(_on_finished, CONNECT_ONE_SHOT)

func seal() -> void:
	_sealed = true
	_try_finish()

func _on_finished() -> void:
	if completed:
		return
	_pending -= 1
	_try_finish()

func _try_finish() -> void:
	if _sealed and _pending == 0 and not completed:
		completed = true
		finished.emit()

func cancel() -> void:
	_pending = 0
	_sealed = true
	_try_finish()
