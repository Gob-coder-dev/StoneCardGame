## Passe ciblée de la courbe de campagne : contenu, progression, boss et decks.
extends Node

const TestLog := preload("res://tests/support/TestLog.gd")
const SUITES: Array[String] = [
	"res://tests/domain/ProgressionAccessChecks.gd",
	"res://tests/domain/CampaignGraphChecks.gd",
	"res://tests/domain/CampaignValidatorChecks.gd",
	"res://tests/domain/CampaignAuditChecks.gd",
	"res://tests/domain/CampaignEncounterChecks.gd",
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var log := TestLog.new()
	TestLog.current = log
	OS.add_logger(log)
	StoryService.auto_start_tutorials = false
	var passed := 0
	var failed := 0
	for path in SUITES:
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			failed += 1
			continue
		var suite = script.new()
		add_child(suite)
		suite._register_test_stones()
		await suite.run()
		passed += suite._passed
		failed += suite._failed
		suite.queue_free()
		await get_tree().process_frame
	OS.remove_logger(log)
	TestLog.current = null
	var errors := log.problems()
	print("CAMPAIGN_BALANCE_CHECKS: %d passed, %d failed, %d Godot errors" % [
		passed, failed, errors.size()])
	get_tree().quit(0 if failed == 0 and errors.is_empty() else 1)
