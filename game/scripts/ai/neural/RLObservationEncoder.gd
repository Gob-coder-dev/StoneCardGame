## Encodage v1 (929 valeurs) et features tactiques v2 (128 x 79).
## Ordre et normalisations identiques a envs/observation.py et tactics/features.py.
extends RefCounted

const Serializer := preload("res://scripts/ai/neural/StateSerializer.gd")
const SIDES := ["top", "bottom", "left", "right"]
const EFFECTS := ["weaken_adjacent", "weaken_on_failed_attack", "swarm", "shield_theft"]
const GODS := ["veskar", "nerava", "kharun", "ilyr", "sylkha", "enigma"]
const AFFINITIES := ["neutral", "veskar", "nerava", "kharun", "ilyr", "sylkha", "enigma"]


static func encode(state: GameState, observer: int) -> PackedFloat32Array:
	assert(state.board_size == 4)
	var raw := Serializer.serialize_for_player(state, observer)
	var opponent := 3 - observer
	var result: Array[float] = []
	for cell in raw["board"]:
		var owner := int(cell["owner"])
		var placed := int(cell["placed_by"])
		result.append_array([float(int(cell["cell_type"]) == -1),
			float(cell["monster"] == null and int(cell["cell_type"]) == 0),
			float(owner == observer), float(owner == opponent),
			float(placed == observer), float(placed == opponent)])
		var monster: Variant = cell["monster"]
		if monster == null:
			for _index in range(36):
				result.append(0.0)
			continue
		for key in ["base_blades", "random_blade_sides", "long_blade_sides", "shield_sides", "swarm_blades"]:
			_append_sides(result, monster.get(key, {}))
		result.append_array([float(monster["miasma_weakness"]) / 4.0,
			float(monster["temporary_weakness"]) / 4.0,
			float(int(monster["temporary_weakness_owner"]) == observer),
			float(int(monster["temporary_weakness_owner"]) == opponent)])
		_append_matches(result, EFFECTS, monster["effects"])
		_append_matches(result, AFFINITIES, [monster["affinity"]])
		result.append(float(monster["coin_flipped"]))
	for slot in range(8):
		if slot < raw["hand"].size():
			result.append_array(_card(raw["hand"][slot]))
		else:
			for _index in range(29):
				result.append(0.0)
	var winner := int(raw["winner"])
	var own_score := int(raw["score_human"] if observer == 1 else raw["score_ai"])
	var other_score := int(raw["score_ai"] if observer == 1 else raw["score_human"])
	result.append_array([float(int(raw["current_player"]) == observer),
		float(int(raw["current_player"]) == opponent), own_score / 16.0, other_score / 16.0,
		raw["hand"].size() / 8.0, int(raw["opponent_hand_size"]) / 8.0,
		int(raw["empty_playable_cells"]) / 16.0, float(raw["is_game_over"]),
		float(winner == observer), float(winner == opponent),
		float(bool(raw["is_game_over"]) and winner == 0)])
	_append_matches(result, GODS, [state.god_of(observer)])
	_append_matches(result, GODS, [state.god_of(opponent)])
	result.append_array([float(observer == 1), float(observer == 2)])
	assert(result.size() == 929)
	return PackedFloat32Array(result)


static func action_features(observation: PackedFloat32Array, action: int, scores: Array) -> PackedFloat32Array:
	var slot := floori(action / 16.0)
	var cell := action % 16
	var result := observation.slice(672 + slot * 29, 672 + (slot + 1) * 29)
	result.append_array(observation.slice(cell * 42, (cell + 1) * 42))
	result.append_array(PackedFloat32Array([slot / 7.0, floori(cell / 4.0) / 3.0, (cell % 4) / 3.0]))
	result.append_array(PackedFloat32Array([clampf(float(scores[0]) / 4.0, -1.0, 1.0),
		clampf(float(scores[1]) / 4.0, -1.0, 1.0), clampf(float(scores[2]) / 4.0, -1.0, 1.0),
		float(scores[3]), clampf(float(scores[4]) / 16.0, -1.0, 1.0)]))
	return result


static func _card(card: Dictionary) -> Array[float]:
	var result: Array[float] = [1.0, float(card["level"]) / 4.0]
	for key in ["blades", "long_blades", "shields"]:
		_append_sides(result, card[key])
	result.append(minf(float(card["random_blades"]) / 8.0, 1.0))
	_append_matches(result, EFFECTS, card["effects"])
	_append_matches(result, AFFINITIES, [card["affinity"]])
	_append_matches(result, ["", "horizontal", "vertical"], [card["coin_flip"]])
	return result


static func _append_sides(result: Array[float], values: Dictionary) -> void:
	for side in SIDES:
		result.append(float(values.get(side, 0)) / 4.0)


static func _append_matches(result: Array[float], expected: Array, actual: Array) -> void:
	for value in expected:
		result.append(float(value in actual))
