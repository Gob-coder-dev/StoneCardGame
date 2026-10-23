## Point d'entrée des suites : règles, IA, interface et fins de présentation.
extends Node
const Suites := [
	preload("res://tests/combat/PlayerDataChecks.gd"),
	preload("res://tests/test_rules_engine.gd"),
	preload("res://tests/test_deck_rules.gd"),
	preload("res://tests/combat/CatalogChecks.gd"),
	preload("res://tests/combat/FortuneChecks.gd"),
	preload("res://tests/combat/AttackChecks.gd"),
	preload("res://tests/combat/WeaknessChecks.gd"),
	preload("res://tests/combat/SwarmChecks.gd"),
	preload("res://tests/combat/PillageChecks.gd"),
	preload("res://tests/ai/AIChecks.gd"),
	preload("res://tests/ui/MenuChecks.gd"),
	preload("res://tests/ui/PreparationAnimationChecks.gd"),
	preload("res://tests/ui/EffectAnimationChecks.gd"),
	preload("res://tests/ui/SwarmAnimationChecks.gd"),
	preload("res://tests/ui/AttackAnimationChecks.gd"),
	preload("res://tests/combat/TurnSequenceChecks.gd"),
	preload("res://tests/combat/AnimatedMatchChecks.gd"),
]

func _ready() -> void:
	var passed := 0
	var failed := 0
	for script in Suites:
		var suite = script.new()
		add_child(suite)
		suite._register_test_stones()
		await suite.run()
		passed += suite._passed
		failed += suite._failed
		suite.queue_free()
		await get_tree().process_frame
	print("GOD_SYSTEM_CHECKS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
