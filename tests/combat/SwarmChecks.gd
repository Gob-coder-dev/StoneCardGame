extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_swarm()

func _test_swarm() -> void:
	var state := _state_with_hands(["fx_swarm_a", "fx_swarm_b", "fx_swarm_c"], [])
	CombatResolverModel.apply_move(state, 0, 0, "fx_swarm_a", GameState.PLAYER_HUMAN)
	var second := CombatResolverModel.apply_move(state, 0, 1, "fx_swarm_b", GameState.PLAYER_HUMAN)
	var third := CombatResolverModel.apply_move(state, 0, 2, "fx_swarm_c", GameState.PLAYER_HUMAN)
	var a: BattleStoneModel = state.get_cell(0, 0)["stone"]
	var b: BattleStoneModel = state.get_cell(0, 1)["stone"]
	var c: BattleStoneModel = state.get_cell(0, 2)["stone"]
	# Trois membres : deux autres membres × 2 lames, soit le plafond de 4.
	_check(_sum(a.swarm_blades) == 4 and _sum(b.swarm_blades) == 4 and _sum(c.swarm_blades) == 4,
		"tout le groupe Swarm reçoit l'aura plafonnée")
	var second_event: Dictionary = second["placement"]["swarm_events"][0]
	var third_event: Dictionary = third["placement"]["swarm_events"][0]
	_check(second_event["members"].size() == 2 and second_event["links_after"].size() == 1,
		"la pose décrit les deux membres et leur nouvelle liaison Essaim")
	_check(third_event["members"].size() == 3 and third_event["links_after"].size() == 2,
		"l'impulsion de renfort reçoit toute la composante connectée")
	_check(CombatResolverModel.swarm_links(state).size() == 2,
		"le moteur expose les deux lianes persistantes du groupe sans règle visuelle dupliquée")
	state.get_cell(0, 1)["owner"] = GameState.PLAYER_AI
	CombatResolverModel.recalculate_swarm(state)
	_check(_sum(a.swarm_blades) == 0 and _sum(c.swarm_blades) == 0, "capturer un maillon casse immédiatement l'aura")

	var captured := _state_with_hands(
		["fx_swarm_a", "fx_swarm_b", "fx_swarm_c"], ["fx_strong_wall"])
	CombatResolverModel.apply_move(captured, 1, 0, "fx_swarm_a", GameState.PLAYER_HUMAN)
	CombatResolverModel.apply_move(captured, 1, 1, "fx_swarm_b", GameState.PLAYER_HUMAN)
	CombatResolverModel.apply_move(captured, 1, 2, "fx_swarm_c", GameState.PLAYER_HUMAN)
	var capture_result := CombatResolverModel.apply_move(
		captured, 0, 1, "fx_strong_wall", GameState.PLAYER_AI)
	var break_event: Dictionary = capture_result["swarm_events"][0]
	_check(capture_result["captures"].size() == 1
		and break_event["links_before"].size() == 2
		and break_event["links_after"].is_empty(),
		"la capture d'un maillon décrit les deux filaments rompus")
	var every_bonus_retracted := true
	for member in break_event["members"]:
		every_bonus_retracted = every_bonus_retracted \
			and _sum(member["before"]) == 4 and _sum(member["after"]) == 0
	_check(every_bonus_retracted,
		"la rupture fournit chaque lame à rétracter sans recalcul visuel")

	# Cinq membres en croix : le plafond de +4 ne grandit plus avec le groupe.
	var cross := _state_with_hands([], [])
	for cell in [[1, 1], [0, 1], [2, 1], [1, 0], [1, 2]]:
		_force_instance(cross, cell[0], cell[1], "fx_swarm_a", GameState.PLAYER_HUMAN)
	_force_instance(cross, 3, 3, "fx_swarm_a", GameState.PLAYER_HUMAN)
	CombatResolverModel.recalculate_swarm(cross)
	_check(_sum(cross.get_cell(1, 1)["stone"].swarm_blades) == 4
		and _sum(cross.get_cell(0, 1)["stone"].swarm_blades) == 4
		and _sum(cross.get_cell(3, 3)["stone"].swarm_blades) == 0,
		"un groupe de cinq atteint +4 pour chaque membre ; une pierre isolée ne gagne rien")

	_test_god_rule()


## Règle des dieux : seules les pierres Essaim d'un camp Ōkuninushi se relient.
func _test_god_rule() -> void:
	var state := _state_with_hands([], [])
	state.human_god_id = "okuninushi"
	state.ai_god_id = "hachiman"
	_force_instance(state, 0, 0, "fx_swarm_okuni_a", GameState.PLAYER_HUMAN)
	_force_instance(state, 0, 1, "fx_swarm_okuni_b", GameState.PLAYER_HUMAN)
	CombatResolverModel.recalculate_swarm(state)
	var first: BattleStoneModel = state.get_cell(0, 0)["stone"]
	var second: BattleStoneModel = state.get_cell(0, 1)["stone"]
	_check(_sum(first.swarm_blades) == 2 and _sum(second.swarm_blades) == 2,
		"deux pierres Essaim reliées dans le camp d'Ōkuninushi gagnent 2 lames chacune")
	state.get_cell(0, 0)["owner"] = GameState.PLAYER_AI
	state.get_cell(0, 1)["owner"] = GameState.PLAYER_AI
	CombatResolverModel.recalculate_swarm(state)
	_check(_sum(first.swarm_blades) == 0 and _sum(second.swarm_blades) == 0
		and CombatResolverModel.swarm_links(state).is_empty(),
		"capturées par un autre dieu, les pierres Essaim ne se relient plus")
	state.ai_god_id = "okuninushi"
	CombatResolverModel.recalculate_swarm(state)
	_check(_sum(first.swarm_blades) == 2 and CombatResolverModel.swarm_links(state).size() == 1,
		"capturées par un joueur d'Ōkuninushi, elles se relient dans son camp")
