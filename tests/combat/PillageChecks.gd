extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_theft()

func _test_theft() -> void:
	var state := _state_with_hands(["fx_thief"], [])
	_force_instance(state, 0, 1, "fx_wall", GameState.PLAYER_AI)
	_force_instance(state, 1, 0, "fx_wall", GameState.PLAYER_AI)
	_force_instance(state, 1, 2, "fx_wall", GameState.PLAYER_AI)
	var result := CombatResolverModel.apply_move(state, 1, 1, "fx_thief", GameState.PLAYER_HUMAN)
	var thief: BattleStoneModel = state.get_cell(1, 1)["stone"]
	_check(result["captures"].size() == 3, "la pierre de pillage capture plusieurs cibles")
	_check(_sum(thief.shields) == 4, "le pillage remplit seulement les quatre emplacements encore libres")
	var capped := true
	for side in BattleStoneModel.SIDES:
		capped = capped and thief.marker_count(side) <= 4
	_check(capped, "le pillage ne dépasse jamais quatre symboles sur une face")
	var event: Dictionary = result["effects"][0]
	var reconstructed: Dictionary = event["shields_before"].duplicate()
	for side in event["placements"]:
		reconstructed[side] = int(reconstructed.get(side, 0)) + 1
	_check(reconstructed == thief.shields and event["placements"].size() == 4,
		"l'animation reçoit les vrais boucliers gagnés et leurs faces, sans nouveau tirage")
	var transfers_match: bool = event["transfers"].size() == event["placements"].size()
	for index in range(event["transfers"].size()):
		transfers_match = transfers_match and event["transfers"][index]["destination_side"] == event["placements"][index]
	_check(event["origins"].size() == 3 and transfers_match
		and state.get_cell(0, 1)["stone"].shields["bottom"] == 1,
		"l'aura relie chaque symbole volé à sa vraie destination sans le retirer du modèle")
