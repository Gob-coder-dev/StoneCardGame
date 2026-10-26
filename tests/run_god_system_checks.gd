## Point d'entrée des suites : règles, IA, interface et fins de présentation.
## Échouent aussi : une suite qui ne compile pas, une erreur ou un avertissement
## Godot non annoncé, et un dépassement du temps limite.
extends Node

const TestLog := preload("res://tests/support/TestLog.gd")
## Secondes de jeu : avec --fixed-fps 60, la limite ne dépend pas de la machine.
## Les suites en utilisent environ 70 aujourd'hui.
const TIME_LIMIT := 300.0
## Chargées à l'exécution : une suite cassée est signalée sans bloquer les autres.
const SUITES: Array[String] = [
	"res://tests/combat/PlayerDataChecks.gd",
	"res://tests/combat/MonsterMigrationChecks.gd",
	"res://tests/combat/EvolutionChecks.gd",
	"res://tests/test_rules_engine.gd",
	"res://tests/test_deck_rules.gd",
	"res://tests/combat/CatalogChecks.gd",
	"res://tests/combat/FortuneChecks.gd",
	"res://tests/combat/AttackChecks.gd",
	"res://tests/combat/WeaknessChecks.gd",
	"res://tests/combat/SwarmChecks.gd",
	"res://tests/combat/PillageChecks.gd",
	"res://tests/ai/AIChecks.gd",
	"res://tests/ui/MenuChecks.gd",
	"res://tests/ui/EvolutionMenuChecks.gd",
	"res://tests/ui/CardArtworkChecks.gd",
	"res://tests/ui/PreparationAnimationChecks.gd",
	"res://tests/ui/EffectAnimationChecks.gd",
	"res://tests/ui/SwarmAnimationChecks.gd",
	"res://tests/ui/AttackAnimationChecks.gd",
	"res://tests/combat/TurnSequenceChecks.gd",
	"res://tests/combat/AnimatedMatchChecks.gd",
]

var _log: TestLog = TestLog.new()
var _passed := 0
var _failed := 0
var _current_suite := ""
var _finished := false


func _ready() -> void:
	TestLog.current = _log
	OS.add_logger(_log)
	get_tree().create_timer(TIME_LIMIT).timeout.connect(_on_time_limit)
	for path in SUITES:
		_current_suite = path.get_file()
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			_failed += 1
			printerr("FAIL: suite non compilée : ", path)
			continue
		var suite = script.new()
		add_child(suite)
		suite._register_test_stones()
		await suite.run()
		_passed += suite._passed
		_failed += suite._failed
		suite.queue_free()
		await get_tree().process_frame
	_finish()


func _on_time_limit() -> void:
	if _finished:
		return
	_failed += 1
	printerr("FAIL: temps limite de %d s dépassé pendant %s" % [TIME_LIMIT, _current_suite])
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	OS.remove_logger(_log)
	TestLog.current = null
	var problems: Array[String] = _log.problems()
	for problem in problems:
		printerr("ERREUR GODOT : ", problem)
	print("GOD_SYSTEM_CHECKS: %d passed, %d failed, %d Godot errors" % [_passed, _failed, problems.size()])
	get_tree().quit(0 if _failed == 0 and problems.is_empty() else 1)
