## Point d'entrée autonome de la régression visuelle des flammes de Rituel.
extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var script := load("res://tests/ui/RitualFlameBackdropChecks.gd") as Script
	var suite = script.new()
	add_child(suite)
	await suite.run()
	var passed: int = suite._passed
	var failed: int = suite._failed
	suite.queue_free()
	await get_tree().process_frame
	script = null
	print("RITUAL_FLAME_CHECKS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
