## Authoritative teacher scores from public snapshots, independent of RL features.
extends RefCounted

const Evaluator := preload("res://scripts/ai/MoveEvaluator.gd")
const Monster := preload("res://scripts/engine/BattleMonster.gd")


static func scores(request: Dictionary) -> Dictionary:
	var snapshot: Dictionary = request["snapshot"]
	var observer := int(snapshot["observer"])
	var state := GameState.new()
	state.ai_god_id = str(snapshot["human_god"] if observer == 1 else snapshot["ai_god"])
	state.human_god_id = str(snapshot["ai_god"] if observer == 1 else snapshot["human_god"])
	for card in snapshot["hand"]:
		state.ai_hand.append(str(card["monster_id"]))
	state.human_hand.resize(int(snapshot["opponent_hand_size"]))
	state.human_hand.fill("")
	state.current_player = GameState.PLAYER_AI
	state.empty_playable_cells = int(snapshot["empty_playable_cells"])
	for index in range(state.board.size()):
		var raw: Dictionary = snapshot["board"][index]
		var cell: Dictionary = state.board[index]
		cell["cell_type"] = int(raw["cell_type"])
		for key in ["owner", "placed_by"]:
			var player := int(raw[key])
			cell[key] = 0 if player == 0 else (2 if player == observer else 1)
		var data = raw.get("monster")
		if data == null:
			continue
		var monster := Monster.new()
		monster.configure(str(data["monster_id"]), {}, int(data["instance_id"]))
		for field in ["base_blades", "swarm_blades"]:
			monster.set(field, data[field].duplicate())
		monster.random_blades = data["random_blade_sides"].duplicate()
		monster.long_blades = data["long_blade_sides"].duplicate()
		monster.shields = data["shield_sides"].duplicate()
		monster.miasma_weakness = int(data["miasma_weakness"])
		monster.temporary_weakness = int(data["temporary_weakness"])
		var owner := int(data["temporary_weakness_owner"])
		monster.temporary_weakness_owner = 0 if owner == 0 else (2 if owner == observer else 1)
		monster.coin_flipped = bool(data["coin_flipped"])
		cell["monster_id"] = monster.monster_id
		cell["monster"] = monster
		state.next_instance_id = maxi(state.next_instance_id, monster.instance_id + 1)
	# Use the same public seed and hidden-hand masking as ProfileAI.
	state = state.clone_for_ai()
	var evaluator := Evaluator.new(state, bool(request["anticipation"]))
	var result := {}
	for move in RulesEngine.get_valid_moves(state, GameState.PLAYER_AI):
		var first: Dictionary = evaluator.evaluate(move, 0)
		var count := evaluator.random_samples() if bool(first["random"]) else 1
		var value := float(first["value"])
		for sample in range(1, count):
			value += float(evaluator.evaluate(move, sample)["value"])
		var action := state.ai_hand.find(str(move["monster_id"])) * 16 + int(move["row"]) * 4 + int(move["col"])
		result[str(action)] = value / count
	return result
