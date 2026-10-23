extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_theft()
	_test_single_capture_avoids_attacking_face()
	_test_full_other_faces()

func _test_theft() -> void:
	var state := _state_with_hands(["fx_thief"], [])
	_force_instance(state, 0, 1, "fx_wall", GameState.PLAYER_AI)
	_force_instance(state, 1, 0, "fx_wall", GameState.PLAYER_AI)
	_force_instance(state, 1, 2, "fx_wall", GameState.PLAYER_AI)
	var result := CombatResolverModel.apply_move(state, 1, 1, "fx_thief", GameState.PLAYER_HUMAN)
	var thief: BattleStoneModel = state.get_cell(1, 1)["stone"]
	_check(result["captures"].size() == 3, "la pierre de pillage capture plusieurs cibles")
	var event: Dictionary = result["effects"][0]
	var capped := true
	for side in BattleStoneModel.SIDES:
		capped = capped and thief.marker_count(side) <= 4
	# Six symboles volés pour quatre places libres : chaque place peut venir
	# d'une capture faite par une autre face, toutes sont donc remplies.
	_check(capped and _sum(thief.shields) == 4 and event["amount"] == 4,
		"le pillage remplit les emplacements libres sans dépasser quatre symboles par face")
	var reconstructed: Dictionary = event["shields_before"].duplicate()
	for side in event["placements"]:
		reconstructed[side] = int(reconstructed.get(side, 0)) + 1
	_check(reconstructed == thief.shields and event["placements"].size() == event["transfers"].size(),
		"l'animation reçoit les vrais boucliers gagnés et leurs faces, sans nouveau tirage")
	var transfers_match := true
	var never_on_attacking_face := true
	for index in range(event["transfers"].size()):
		var transfer: Dictionary = event["transfers"][index]
		transfers_match = transfers_match and transfer["destination_side"] == event["placements"][index]
		never_on_attacking_face = never_on_attacking_face \
			and transfer["destination_side"] != transfer["direction"] \
			and not transfer["candidate_sides"].has(transfer["direction"]) \
			and transfer["candidate_sides"].has(transfer["destination_side"])
	_check(never_on_attacking_face,
		"avec plusieurs captures, aucun symbole volé n'arrive sur la face qui l'a capturé")
	_check(event["origins"].size() == 3 and transfers_match
		and state.get_cell(0, 1)["stone"].shields["bottom"] == 1,
		"l'aura relie chaque symbole volé à sa vraie destination sans le retirer du modèle")


func _test_single_capture_avoids_attacking_face() -> void:
	# Capture par la droite : les deux symboles volés vont en haut, en bas ou à gauche.
	var state := _state_with_hands(["fx_thief"], [])
	_force_instance(state, 1, 2, "fx_wall", GameState.PLAYER_AI)
	var result := CombatResolverModel.apply_move(state, 1, 1, "fx_thief", GameState.PLAYER_HUMAN)
	var thief: BattleStoneModel = state.get_cell(1, 1)["stone"]
	var event: Dictionary = result["effects"][0]
	var candidates_ok := true
	for transfer in event["transfers"]:
		candidates_ok = candidates_ok and transfer["candidate_sides"].size() >= 2 \
			and not transfer["candidate_sides"].has("right")
	_check(event["amount"] == 2 and thief.shields["right"] == 0 and candidates_ok,
		"les boucliers volés sont répartis sur les trois autres faces")


func _test_full_other_faces() -> void:
	# Seule la face qui attaque a de la place : aucun bouclier ne peut être placé.
	var state := _state_with_hands(["fx_thief_right_open"], [])
	_force_instance(state, 1, 2, "fx_plain", GameState.PLAYER_AI)
	var result := CombatResolverModel.apply_move(state, 1, 1, "fx_thief_right_open", GameState.PLAYER_HUMAN)
	var thief: BattleStoneModel = state.get_cell(1, 1)["stone"]
	_check(result["captures"].size() == 1 and _sum(thief.shields) == 0 and result["effects"].is_empty(),
		"si les trois autres faces sont pleines, le pillage ne place aucun bouclier")
