## Statistiques de manches terminées, vues depuis le camp local.
## Les totaux historiques restent acquis ; les ventilations débutent à la mise à jour.
extends RefCounted

const Integer := preload("res://scripts/domain/IntegerValue.gd")
const COUNTERS := ["games_played", "wins", "losses", "draws", "current_streak",
	"best_streak", "total_captures"]
const RECORDS := ["best_move_captures", "best_round_captures", "perfect_rounds"]
const MODES := ["classic", "random", "mirror", "draft"]
const SCOPES := ["campaign", "pvp"]
const RECENT_LIMIT := 128


static func defaults() -> Dictionary:
	var result := {"by_scope": {}, "by_god": {}, "by_mode": {}, "recent_results": []}
	for key in COUNTERS + RECORDS:
		result[key] = 0
	return result


static func normalize(raw: Variant) -> Dictionary:
	var result := defaults()
	if not raw is Dictionary:
		return result
	for key in COUNTERS + RECORDS:
		result[key] = Integer.read(raw.get(key))
	for group in ["by_scope", "by_god", "by_mode"]:
		var entries: Variant = raw.get(group, {})
		if not entries is Dictionary:
			continue
		for key in entries:
			if key is String and entries[key] is Dictionary:
				var record := {}
				for counter in COUNTERS + RECORDS:
					record[counter] = Integer.read(entries[key].get(counter))
				result[group][key] = record
	var recent: Variant = raw.get("recent_results", [])
	if recent is Array:
		for key in recent.slice(-RECENT_LIMIT):
			if key is String and key != "" and not result["recent_results"].has(key):
				result["recent_results"].append(key)
	return result


static func record_match(stats: Dictionary, result: Dictionary, key: String = "") -> Dictionary:
	var next := normalize(stats)
	if key != "" and next["recent_results"].has(key):
		return next
	_update(next, result)
	var scope := str(result.get("scope", "campaign"))
	if not SCOPES.has(scope):
		scope = "campaign"
	var god := str(result.get("player_god_id", ""))
	if god == "":
		god = "godless"
	var mode := str(result.get("mode", "classic"))
	if not MODES.has(mode):
		mode = "classic"
	for pair in [["by_scope", scope], ["by_god", god], ["by_mode", mode]]:
		var record: Dictionary = next[pair[0]].get(pair[1], {})
		_update(record, result)
		next[pair[0]][pair[1]] = record
	for pair in [["by_god", god], ["by_mode", mode]]:
		var scoped_key := "%s:%s" % [scope, pair[1]]
		var record: Dictionary = next[pair[0]].get(scoped_key, {})
		_update(record, result)
		next[pair[0]][scoped_key] = record
	if key != "":
		next["recent_results"].append(key)
		if next["recent_results"].size() > RECENT_LIMIT:
			next["recent_results"].pop_front()
	return next


static func _update(stats: Dictionary, result: Dictionary) -> void:
	for counter in COUNTERS + RECORDS:
		if not stats.has(counter):
			stats[counter] = 0
	stats["games_played"] += 1
	var captures := maxi(0, int(result.get("captures", 0)))
	stats["total_captures"] += captures
	stats["best_round_captures"] = maxi(stats["best_round_captures"], captures)
	stats["best_move_captures"] = maxi(stats["best_move_captures"],
		clampi(int(result.get("best_move_captures", 0)), 0, captures))
	match int(result.get("winner", 0)):
		1:
			stats["wins"] += 1
			stats["current_streak"] += 1
			stats["best_streak"] = maxi(stats["best_streak"], stats["current_streak"])
			if int(result.get("board_size", 4)) == 4 and int(result.get("score_local", 0)) > 0 and int(result.get("score_opponent", -1)) == 0:
				stats["perfect_rounds"] += 1
		2:
			stats["losses"] += 1
			stats["current_streak"] = 0
		_:
			stats["draws"] += 1
			stats["current_streak"] = 0


static func win_rate(stats: Dictionary) -> int:
	var games := int(stats.get("games_played", 0))
	return int(round(100.0 * int(stats.get("wins", 0)) / games)) if games > 0 else 0
