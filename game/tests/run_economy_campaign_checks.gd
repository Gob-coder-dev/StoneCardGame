## Passe ciblée rapide pour le profil économique, la campagne et leurs écrans.
## La suite globale reste l'autorité finale ; celle-ci accélère les itérations.
extends Node

const TestLog := preload("res://tests/support/TestLog.gd")
const SUITES: Array[String] = [
	"res://tests/combat/PlayerDataChecks.gd",
	"res://tests/ui/MenuChecks.gd",
	"res://tests/domain/EconomyChecks.gd",
	"res://tests/domain/CampaignValidatorChecks.gd",
	"res://tests/domain/CampaignProgressChecks.gd",
	"res://tests/domain/CampaignEncounterChecks.gd",
	"res://tests/domain/CampaignFlowChecks.gd",
]

var _log := TestLog.new()


func _ready() -> void:
	TestLog.current = _log
	OS.add_logger(_log)
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
	OS.remove_logger(_log)
	TestLog.current = null
	var errors := _log.problems()
	print("ECONOMY_CAMPAIGN_CHECKS: %d passed, %d failed, %d Godot errors" % [
		passed, failed, errors.size()])
	Audio.quit_game(0 if failed == 0 and errors.is_empty() else 1)
