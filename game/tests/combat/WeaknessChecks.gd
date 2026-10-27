extends "res://tests/support/CombatTestSuite.gd"

const WeaknessSystemModel := preload("res://scripts/engine/effects/WeaknessSystem.gd")

func run() -> void:
	await _test_weakening()

func _test_weakening() -> void:
	var local := _state_with_hands(["fx_weaken_local"], [])
	_force_instance(local, 1, 2, "fx_plain", GameState.PLAYER_AI)
	_force_instance(local, 1, 0, "fx_plain", GameState.PLAYER_HUMAN)
	var local_result := CombatResolverModel.apply_move(local, 1, 1, "fx_weaken_local", GameState.PLAYER_HUMAN)
	var neighbor: BattleStoneModel = local.get_cell(1, 2)["stone"]
	var ally: BattleStoneModel = local.get_cell(1, 0)["stone"]
	_check(neighbor.miasma_weakness == 1 and neighbor.attack("left") == 0, "l'aura du Miasme touche chaque face de la voisine")
	_check(ally.miasma_weakness == 0, "le Miasme épargne les pierres du lanceur")
	_check(local_result["effects"].size() == 1
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
	_check(equal_target.miasma_weakness == 1 and equal_target.defense("left") == 0,
		"la voisine est affaiblie après avoir résisté à la tentative de capture")
	var later_result := CombatResolverModel.apply_move(equal_duel, 0, 2, "fx_plain", GameState.PLAYER_HUMAN)
	_check(later_result["captures"].size() == 1, "un coup ultérieur profite du Miasme déjà appliqué")

	var winning_duel := _state_with_hands(["fx_weaken_attack2"], [])
	_force_instance(winning_duel, 1, 2, "fx_plain", GameState.PLAYER_AI)
	var winning_result := CombatResolverModel.apply_move(winning_duel, 1, 1, "fx_weaken_attack2", GameState.PLAYER_HUMAN)
	var captured_neighbor: BattleStoneModel = winning_duel.get_cell(1, 2)["stone"]
	_check(winning_result["captures"].size() == 1 and winning_duel.get_cell(1, 2)["owner"] == GameState.PLAYER_HUMAN
		and captured_neighbor.miasma_weakness == 0, "le Miasme épargne une voisine que le coup vient de capturer")

	_test_miasma_aura()
	await _test_failed_attack()


## Le Miasme est une aura : il touche aussi les cartes posées plus tard, se
## cumule et disparaît quand sa pierre passe chez un autre dieu.
func _test_miasma_aura() -> void:
	var later := _state_with_hands(["fx_plain"], ["fx_attack2"])
	later.human_god_id = "izanami"
	later.ai_god_id = "hachiman"
	_force_instance(later, 1, 1, "fx_miasma_guard", GameState.PLAYER_HUMAN)
	# fx_attack2 (2 lames à droite) contre une défense de 1 : la capture n'a lieu
	# que si la carte posée frappe avant de subir l'aura (sinon 1 contre 1).
	var arrival := CombatResolverModel.apply_move(later, 1, 0, "fx_attack2", GameState.PLAYER_AI)
	var newcomer: BattleStoneModel = later.get_cell(1, 0)["stone"]
	_check(arrival["captures"].size() == 1 and later.get_cell(1, 1)["owner"] == GameState.PLAYER_AI,
		"une carte posée à côté du Miasme attaque d'abord avec toute sa force")
	_check(newcomer.miasma_weakness == 0,
		"un Miasme capturé par un autre dieu n'affaiblit pas son nouveau voisin")

	var placed_next := _state_with_hands(["fx_plain"], ["fx_plain"])
	placed_next.human_god_id = "izanami"
	placed_next.ai_god_id = "hachiman"
	_force_instance(placed_next, 1, 1, "fx_miasma_izanami", GameState.PLAYER_HUMAN)
	_force_instance(placed_next, 1, 3, "fx_miasma_izanami", GameState.PLAYER_HUMAN)
	var between := CombatResolverModel.apply_move(placed_next, 1, 2, "fx_plain", GameState.PLAYER_AI)
	var squeezed: BattleStoneModel = placed_next.get_cell(1, 2)["stone"]
	_check(between["captures"].size() == 2 and squeezed.miasma_weakness == 0,
		"une carte qui capture les pierres Miasme voisines ne subit pas leur aura")

	var cumulative := _state_with_hands(["fx_plain"], ["fx_wall"])
	cumulative.human_god_id = "izanami"
	cumulative.ai_god_id = "hachiman"
	# Les deux gardes résistent au mur posé entre elles, qui reste donc adverse.
	_force_instance(cumulative, 1, 1, "fx_miasma_guard", GameState.PLAYER_HUMAN)
	_force_instance(cumulative, 1, 3, "fx_miasma_guard", GameState.PLAYER_HUMAN)
	_force_instance(cumulative, 0, 1, "fx_strong_wall", GameState.PLAYER_HUMAN)
	var walled := CombatResolverModel.apply_move(cumulative, 1, 2, "fx_wall", GameState.PLAYER_AI)
	var wall: BattleStoneModel = cumulative.get_cell(1, 2)["stone"]
	var weaken_events := 0
	for event in walled["effects"]:
		if event.get("type", "") == CombatEvents.WEAKEN:
			weaken_events += 1
	_check(wall.miasma_weakness == 2 and wall.attack("left") == 0 and wall.defense("left") == 1,
		"deux pierres Miasme voisines retirent 2 de force, sans toucher les boucliers")
	_check(weaken_events == 1 and walled["effects"][0].get("weakness_after", -1) == 2,
		"la carte posée reçoit un seul événement avec son malus total")

	# Capturer la pierre Miasme (1,1) pour le camp IA éteint son aura.
	cumulative.get_cell(1, 1)["owner"] = GameState.PLAYER_AI
	var relief := WeaknessSystemModel.update_miasma(cumulative, 1, 1)
	_check(wall.miasma_weakness == 1 and relief.size() == 1
		and relief[0].get("type", "") == CombatEvents.WEAKNESS_EXPIRED,
		"une pierre Miasme capturée par un autre dieu perd son aura et soulage sa voisine")
	cumulative.ai_god_id = "izanami"
	WeaknessSystemModel.update_miasma(cumulative, 1, 1)
	_check(cumulative.get_cell(0, 1)["stone"].miasma_weakness == 1,
		"chez un adversaire du même dieu, le Miasme capturé agit pour son nouveau camp")


func _test_failed_attack() -> void:
	# fx_corrode (1 lame à droite) échoue contre la défense 1 de sa voisine de droite.
	var timed := _state_with_hands(["fx_corrode", "fx_plain"], ["fx_plain"])
	_force_instance(timed, 1, 2, "fx_plain", GameState.PLAYER_AI)
	_force_instance(timed, 0, 1, "fx_plain", GameState.PLAYER_AI)
	_force_instance(timed, 2, 2, "fx_plain", GameState.PLAYER_AI)
	var timed_result := CombatResolverModel.apply_move(timed, 1, 1, "fx_corrode", GameState.PLAYER_HUMAN)
	var victim: BattleStoneModel = timed.get_cell(1, 2)["stone"]
	var untouched_above: BattleStoneModel = timed.get_cell(0, 1)["stone"]
	var far_away: BattleStoneModel = timed.get_cell(2, 2)["stone"]
	_check(timed_result["captures"].is_empty() and victim.temporary_weakness == 2,
		"la pierre qui résiste à l'attaque perd 2 de force")
	_check(untouched_above.temporary_weakness == 0 and far_away.temporary_weakness == 0,
		"une voisine non attaquée et une pierre éloignée ne sont pas affaiblies")
	_check(timed_result["effects"].size() == 1
		and timed_result["effects"][0].get("scope", "") == "failed_attack"
		and timed_result["effects"][0].get("row", -1) == 1 and timed_result["effects"][0].get("col", -1) == 2
		and timed_result["effects"][0].get("source_row", -1) == 1,
		"l'échec corrosif décrit sa cible et sa source")
	CombatResolverModel.apply_move(timed, 2, 0, "fx_plain", GameState.PLAYER_AI)
	_check(victim.temporary_weakness == 2, "l'affaiblissement survit au tour adverse")
	var attack_result := CombatResolverModel.apply_move(timed, 0, 2, "fx_plain", GameState.PLAYER_HUMAN)
	_check(attack_result["captures"].size() == 1 and timed.get_cell(1, 2)["owner"] == GameState.PLAYER_HUMAN,
		"le prochain coup du lanceur profite de l'affaiblissement")
	_check(victim.temporary_weakness == 0, "l'affaiblissement expire après la résolution de ce coup")
	var expiry_found := false
	for event in attack_result["effects"]:
		expiry_found = expiry_found or event.get("type", "") == CombatEvents.WEAKNESS_EXPIRED
	_check(expiry_found, "l'expiration fournit un événement de réparation visuelle")

	# En haut, 1 lame contre 1 : échec. À droite, 2 lames contre 1 : capture.
	var mixed := _state_with_hands(["fx_corrode_mixed"], [])
	_force_instance(mixed, 0, 1, "fx_plain", GameState.PLAYER_AI)
	_force_instance(mixed, 1, 2, "fx_plain", GameState.PLAYER_AI)
	var mixed_result := CombatResolverModel.apply_move(mixed, 1, 1, "fx_corrode_mixed", GameState.PLAYER_HUMAN)
	_check(mixed_result["captures"].size() == 1
		and mixed.get_cell(0, 1)["stone"].temporary_weakness == 2
		and mixed.get_cell(1, 2)["stone"].temporary_weakness == 0,
		"seule la pierre qui a résisté est affaiblie, pas celle qui vient d'être capturée")

	var ranged := _state_with_hands(["fx_corrode_ranged"], [])
	_force_instance(ranged, 1, 2, "fx_wall", GameState.PLAYER_AI)
	CombatResolverModel.apply_move(ranged, 1, 0, "fx_corrode_ranged", GameState.PLAYER_HUMAN)
	_check(ranged.get_cell(1, 2)["stone"].temporary_weakness == 2,
		"une pierre lointaine qui résiste à une lame bleue est aussi affaiblie")

	var no_target := _state_with_hands(["fx_corrode"], [])
	_force_instance(no_target, 0, 0, "fx_plain", GameState.PLAYER_AI)
	var quiet := CombatResolverModel.apply_move(no_target, 2, 2, "fx_corrode", GameState.PLAYER_HUMAN)
	_check(quiet["effects"].is_empty() and no_target.get_cell(0, 0)["stone"].temporary_weakness == 0,
		"sans attaque, l'échec corrosif ne se déclenche pas")
