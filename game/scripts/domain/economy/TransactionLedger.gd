## Registre idempotent compact des flux ordonnés de campagne.
## Un curseur par niveau remplace les milliers d'identifiants de replays/manches.
## Les récompenses uniques conservent leurs clés ; aucun historique n'est expiré.
extends RefCounted

const Integer := preload("res://scripts/domain/IntegerValue.gd")


static func restore(raw_keys: Variant, raw_cursors: Variant) -> Dictionary:
	var result := {"keys": {}, "cursors": {}}
	if raw_cursors is Dictionary:
		for stream in raw_cursors:
			var values: Variant = raw_cursors[stream]
			if stream is String and values is Array and values.size() in [1, 2]:
				var cursor: Array = []
				for value in values:
					cursor.append(Integer.read(value))
				result["cursors"][stream] = cursor
	if raw_keys is Dictionary:
		for key in raw_keys:
			if key is String and raw_keys[key] == true:
				mark(result["keys"], result["cursors"], key)
	return result


static func contains(keys: Dictionary, cursors: Dictionary, id: String) -> bool:
	if keys.has(id):
		return true
	var entry := _ordered_entry(id)
	return not entry.is_empty() and cursors.has(entry["stream"]) \
		and _at_least(cursors[entry["stream"]], entry["position"])


static func mark(keys: Dictionary, cursors: Dictionary, id: String) -> void:
	if id == "":
		return
	var entry := _ordered_entry(id)
	if entry.is_empty():
		keys[id] = true
	elif not contains(keys, cursors, id):
		cursors[entry["stream"]] = entry["position"]


static func _ordered_entry(id: String) -> Dictionary:
	var parts := id.split(":")
	if parts.size() == 5 and parts[0] == "campaign" and parts[3] == "replay" \
			and parts[4].is_valid_int():
		return {"stream": ":".join(parts.slice(0, 4)), "position": [maxi(0, int(parts[4]))]}
	if parts.size() in [5, 6] and parts[0] == "quest" and parts[1] == "campaign" \
			and parts[4].is_valid_int() and (parts.size() == 5 or parts[5].is_valid_int()):
		return {"stream": ":".join(parts.slice(0, 4)), "position": [maxi(0, int(parts[4])),
			maxi(0, int(parts[5])) if parts.size() == 6 else 0]}
	return {}


static func _at_least(current: Array, requested: Array) -> bool:
	for index in range(requested.size()):
		var previous := int(current[index]) if index < current.size() else 0
		if previous != int(requested[index]):
			return previous > int(requested[index])
	return true
