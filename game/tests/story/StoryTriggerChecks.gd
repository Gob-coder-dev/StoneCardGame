## Règles pures des déclencheurs : priorité, état « déjà vu » et filtres.
extends "res://tests/support/CombatTestSuite.gd"

const TriggerRulesModel := preload("res://scripts/domain/story/StoryTriggerRules.gd")


func run() -> void:
	var trigger := {
		"id": "intro",
		"node_id": "tuto_01",
		"event": "level_start",
		"sequence": "tuto_01_intro",
	}
	_check(TriggerRulesModel.matches(trigger, "tuto_01", "level_start"),
		"déclencheurs : un niveau et un événement identiques correspondent")
	_check(not TriggerRulesModel.matches(trigger, "tuto_02", "level_start"),
		"déclencheurs : un autre niveau ne correspond pas")
	_check(not TriggerRulesModel.matches(trigger, "tuto_01", "level_won"),
		"déclencheurs : un autre événement ne correspond pas")
	var global_trigger := {"event": "level_won", "outcome": "win"}
	_check(TriggerRulesModel.matches(global_trigger, "veskar_01", "level_won",
		{"outcome": "win"}), "déclencheurs : un déclencheur global accepte un résultat gagnant")
	_check(not TriggerRulesModel.matches(global_trigger, "veskar_01", "level_won",
		{"outcome": "loss"}), "déclencheurs : le résultat filtre une défaite")
	var bounded := {"event": "turn_start", "min_turn": 2, "max_turn": 4}
	_check(not TriggerRulesModel.matches(bounded, "n", "turn_start", {"turn": 1}),
		"déclencheurs : un tour trop tôt est refusé")
	_check(TriggerRulesModel.matches(bounded, "n", "turn_start", {"turn": 3}),
		"déclencheurs : un tour dans la fenêtre est accepté")
	_check(not TriggerRulesModel.matches(bounded, "n", "turn_start", {"turn": 5}),
		"déclencheurs : un tour trop tard est refusé")
	var ordered := [
		{"id": "first", "node_id": "tuto_01", "event": "level_start"},
		{"id": "second", "node_id": "tuto_01", "event": "level_start"},
	]
	_check(str(TriggerRulesModel.first_matching(ordered, "tuto_01", "level_start", {})
		.get("id", "")) == "first",
		"déclencheurs : le premier déclencheur correspondant gagne")
	var once_seen := {TriggerRulesModel.state_key("first"): true}
	_check(str(TriggerRulesModel.first_matching(ordered, "tuto_01", "level_start", once_seen)
		.get("id", "")) == "second",
		"déclencheurs : un déclencheur déjà consommé laisse sa place au suivant")
	var repeatable := {"id": "repeat", "node_id": "tuto_01", "event": "level_start", "once": false}
	var seen := {TriggerRulesModel.state_key("repeat"): true}
	_check(not TriggerRulesModel.first_matching([repeatable], "tuto_01", "level_start", seen)
		.is_empty(), "déclencheurs : once=false reste rejouable malgré l'état vu")
	_check(TriggerRulesModel.state_key("intro") == "seq:intro:seen",
		"déclencheurs : la clé d'état est stable")
	_check(TriggerRulesModel.first_matching([], "tuto_01", "level_start", {}).is_empty(),
		"déclencheurs : une liste vide ne déclenche rien")
