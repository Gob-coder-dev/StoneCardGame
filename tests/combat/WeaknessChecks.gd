extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_weakening()

func _test_weakening() -> void:
	var local := _state_with_hands(["fx_weaken_local"], [])
	_force_instance(local, 1, 2, "fx_plain", GameState.PLAYER_AI)
	_force_instance(local, 1, 0, "fx_plain", GameState.PLAYER_HUMAN)
	var local_result := CombatResolverModel.apply_move(local, 1, 1, "fx_weaken_local", GameState.PLAYER_HUMAN)
	var neighbor: BattleStoneModel = local.get_cell(1, 2)["stone"]
	var ally: BattleStoneModel = local.get_cell(1, 0)["stone"]
	_check(neighbor.permanent_weakness == 1 and neighbor.attack("left") == 0, "l'affaiblissement local est permanent et touche chaque face")
	_check(ally.permanent_weakness == 1, "l'affaiblissement local touche aussi les alliés")
	_check(local_result["effects"].size() == 2
		and local_result["effects"][0].get("source_row", -1) == 1
		and local_result["effects"][0].get("weakness_before", -1) == 0
		and local_result["effects"][0].get("weakness_after", -1) == 1,
		"le Miasme décrit sa source et les valeurs visuelles avant/après")

	var equal_duel := _state_with_hands(["fx_weaken_attack1", "fx_plain"], [])
	_force_instance(equal_duel, 1, 2, "fx_plain", GameState.PLAYER_AI)
	var equal_result := CombatResolverModel.apply_move(equal_duel, 1, 1, "fx_weaken_attack1", GameState.PLAYER_HUMAN)
	var equal_target: BattleStoneModel = equal_duel.get_cell(1, 2)["stone"]
	_check(equal_result["captures"].is_empty() and equal_duel.get_cell(1, 2)["owner"] == GameState.PLAYER_AI,
		"Miasme ne transforme pas une égalité en capture pendant le coup qui l'active")
	_check(equal_target.permanent_weakness == 1 and equal_target.defense("left") == 0,
		"la voisine est affaiblie après avoir résisté à la tentative de capture")
	var later_result := CombatResolverModel.apply_move(equal_duel, 0, 2, "fx_plain", GameState.PLAYER_HUMAN)
	_check(later_result["captures"].size() == 1, "un coup ultérieur profite du Miasme déjà appliqué")

	var winning_duel := _state_with_hands(["fx_weaken_attack2"], [])
	_force_instance(winning_duel, 1, 2, "fx_plain", GameState.PLAYER_AI)
	var winning_result := CombatResolverModel.apply_move(winning_duel, 1, 1, "fx_weaken_attack2", GameState.PLAYER_HUMAN)
	var captured_neighbor: BattleStoneModel = winning_duel.get_cell(1, 2)["stone"]
	_check(winning_result["captures"].size() == 1 and winning_duel.get_cell(1, 2)["owner"] == GameState.PLAYER_HUMAN
		and captured_neighbor.permanent_weakness == 1, "Miasme affaiblit aussi une voisine après sa capture")

	var timed := _state_with_hands(["fx_weaken_miss", "fx_plain"], ["fx_plain"])
	_force_instance(timed, 0, 1, "fx_plain", GameState.PLAYER_AI)
	var timed_result := CombatResolverModel.apply_move(timed, 2, 2, "fx_weaken_miss", GameState.PLAYER_HUMAN)
	var victim: BattleStoneModel = timed.get_cell(0, 1)["stone"]
	_check(victim.temporary_weakness == 1, "un échec affaiblit le camp adverse")
	_check(timed_result["effects"][0].get("scope", "") == "global"
		and timed_result["effects"][0].get("source_row", -1) == 2,
		"l'échec corrosif décrit la vague globale et sa source")
	CombatResolverModel.apply_move(timed, 2, 0, "fx_plain", GameState.PLAYER_AI)
	_check(victim.temporary_weakness == 1, "l'affaiblissement survit au tour adverse")
	var attack_result := CombatResolverModel.apply_move(timed, 0, 0, "fx_plain", GameState.PLAYER_HUMAN)
	_check(attack_result["captures"].size() == 1 and timed.get_cell(0, 1)["owner"] == GameState.PLAYER_HUMAN,
		"le prochain coup du lanceur profite de l'affaiblissement")
	_check(victim.temporary_weakness == 0, "l'affaiblissement expire après la résolution de ce coup")
	var expiry_found := false
	for event in attack_result["effects"]:
		expiry_found = expiry_found or event.get("type", "") == "weakness_expired"
	_check(expiry_found, "l'expiration fournit un événement de réparation visuelle")
