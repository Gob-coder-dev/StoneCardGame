## Inférence float32 portable. Les projections d'état sont calculées une fois
## et peuvent être réparties sur plusieurs images par advance_state().
extends RefCounted

const Identity := preload("res://scripts/ai/neural/RLIdentity.gd")
const MAGIC := "SSPOLICY2\n"
const MAX_BYTES := 67108864
var metadata: Dictionary = {}
var _tensors: Dictionary = {}


func load_file(path: String, require_validated: bool = true) -> Error:
	metadata = {}
	_tensors.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	if file.get_length() > MAX_BYTES or file.get_buffer(MAGIC.length()).get_string_from_utf8() != MAGIC:
		return ERR_FILE_CORRUPT
	var header_size := file.get_32()
	var expected_digest := file.get_buffer(32)
	if header_size <= 0 or header_size > 1048576 or header_size > file.get_length() - file.get_position():
		return ERR_FILE_CORRUPT
	var header := file.get_buffer(header_size)
	var parsed: Variant = JSON.parse_string(header.get_string_from_utf8())
	if not parsed is Dictionary or int(parsed.get("schema", 0)) != 2:
		return ERR_FILE_CORRUPT
	if parsed.get("dtype", "") != "float32-le":
		return ERR_INVALID_DATA
	var spec: Dictionary = parsed.get("policy_spec", {})
	if int(spec.get("observation_size", 0)) != 929 or int(spec.get("action_count", 0)) != 128:
		return ERR_INVALID_DATA
	var architecture := str(spec.get("architecture", ""))
	if architecture not in ["actor_critic", "tactical_actor_critic"]:
		return ERR_INVALID_DATA
	if architecture == "tactical_actor_critic" and (int(spec.get("feature_schema", 0)) != 2 or int(spec.get("feature_size", 0)) != 79):
		return ERR_INVALID_DATA
	if require_validated and not bool(parsed.get("validated", false)):
		return ERR_UNAUTHORIZED
	var provenance: Dictionary = parsed.get("provenance", {})
	if provenance.get("content", "") != Identity.content_checksum() or provenance.get("game_rules", "") != Identity.rules_checksum():
		return ERR_INVALID_DATA
	var weights := file.get_buffer(file.get_length() - file.get_position())
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(header)
	digest.update(weights)
	if digest.finish() != expected_digest:
		return ERR_FILE_CORRUPT
	digest.start(HashingContext.HASH_SHA256)
	digest.update(weights)
	if digest.finish().hex_encode() != str(parsed.get("sha256", "")):
		return ERR_FILE_CORRUPT
	for name in parsed.get("tensors", {}):
		var tensor: Dictionary = parsed["tensors"][name]
		var offset := int(tensor.get("offset", -1))
		var length := int(tensor.get("bytes", -1))
		if offset < 0 or length <= 0 or offset + length > weights.size() or length % 4 != 0:
			return ERR_FILE_CORRUPT
		var values := weights.slice(offset, offset + length).to_float32_array()
		for value in values:
			if not is_finite(value):
				return ERR_INVALID_DATA
		_tensors[str(name)] = values
	var hidden := int(spec.get("hidden_dim", 0))
	var action_hidden := int(spec.get("action_hidden_dim", 0))
	if hidden <= 0 or hidden > 2048 or action_hidden < 0 or action_hidden > 2048:
		return ERR_INVALID_DATA
	var shapes := {"backbone.0": [929, hidden], "backbone.2": [hidden, hidden], "critic": [hidden, 1]}
	if architecture == "tactical_actor_critic":
		shapes.merge({"legacy_actor": [hidden, 128], "action_encoder.0": [79, action_hidden],
			"action_scorer.0": [hidden + action_hidden, maxi(64, floori(hidden / 2.0))],
			"action_scorer.2": [maxi(64, floori(hidden / 2.0)), 1]})
	else:
		shapes["actor"] = [hidden, 128]
	for layer in shapes:
		if not _tensors.has(layer + ".weight") or not _tensors.has(layer + ".bias"):
			return ERR_INVALID_DATA
		if _tensors[layer + ".weight"].size() != int(shapes[layer][0]) * int(shapes[layer][1]) or _tensors[layer + ".bias"].size() != int(shapes[layer][1]):
			return ERR_INVALID_DATA
	metadata = parsed
	return OK


func start_state(observation: PackedFloat32Array) -> Dictionary:
	return {"observation": observation, "stage": 0, "row": 0, "buffer": []}


func advance_state(context: Dictionary, budget_usec: int = 0) -> bool:
	var started := Time.get_ticks_usec()
	var tactical := str(metadata["policy_spec"]["architecture"]) == "tactical_actor_critic"
	var stages := ["backbone.0", "backbone.2", "legacy_actor" if tactical else "actor", "critic"]
	if tactical:
		stages.append("action_scorer.0")
	while int(context["stage"]) < stages.size():
		var stage := int(context["stage"])
		var layer: String = stages[stage]
		var input: PackedFloat32Array = context["observation"] if stage == 0 else context["first"] if stage == 1 else context["state"]
		var stride := input.size()
		if stage == 4:
			stride += int(metadata["policy_spec"]["action_hidden_dim"])
		var bias: PackedFloat32Array = _tensors[layer + ".bias"]
		var weights: PackedFloat32Array = _tensors[layer + ".weight"]
		var buffer: Array = context["buffer"]
		while int(context["row"]) < bias.size():
			var row := int(context["row"])
			var value := _dot(input, weights, row * stride) + bias[row]
			buffer.append(tanh(value) if stage < 2 else value)
			context["row"] = row + 1
			context["buffer"] = buffer
			if budget_usec > 0 and Time.get_ticks_usec() - started >= budget_usec:
				return false
		context[["first", "state", "legacy", "value", "shared"][stage]] = PackedFloat32Array(buffer)
		context["buffer"] = []
		context["row"] = 0
		context["stage"] = stage + 1
	return true


func score_action(context: Dictionary, action: int, features: PackedFloat32Array) -> float:
	var value := float(context["legacy"][action])
	if str(metadata["policy_spec"]["architecture"]) != "tactical_actor_critic":
		return value
	var encoded := _dense(features, "action_encoder.0", true)
	var shared: PackedFloat32Array = context["shared"]
	var weights: PackedFloat32Array = _tensors["action_scorer.0.weight"]
	var hidden := int(metadata["policy_spec"]["hidden_dim"])
	var stride := hidden + encoded.size()
	var activation := PackedFloat32Array()
	for row in range(shared.size()):
		activation.append(tanh(shared[row] + _dot(encoded, weights, row * stride + hidden)))
	return value + _dense(activation, "action_scorer.2", false)[0]


func _dense(input: PackedFloat32Array, layer: String, nonlinear: bool) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var bias: PackedFloat32Array = _tensors[layer + ".bias"]
	var weights: PackedFloat32Array = _tensors[layer + ".weight"]
	for row in range(bias.size()):
		var value := bias[row] + _dot(input, weights, row * input.size())
		result.append(tanh(value) if nonlinear else value)
	return result


static func _dot(input: PackedFloat32Array, weights: PackedFloat32Array, offset: int) -> float:
	var total := 0.0
	for index in range(input.size()):
		total += input[index] * weights[offset + index]
	return total
