## Valeurs et calculs des statistiques du profil, sans stockage ni singleton.
## Les données relues sont normalisées avant de pouvoir entrer dans un calcul.
extends RefCounted

const Integer := preload("res://scripts/domain/IntegerValue.gd")
const COUNTERS := ["games_played", "wins", "losses", "draws", "current_streak",
	"best_streak", "total_captures"]


static func defaults() -> Dictionary:
	var result := {"per_npc": {}}
	for key in COUNTERS:
		result[key] = 0
	return result


static func normalize(raw: Variant) -> Dictionary:
	var result := defaults()
	if not raw is Dictionary:
		return result
	for key in COUNTERS:
		result[key] = Integer.read(raw.get(key))
	var records: Variant = raw.get("per_npc", {})
	if records is Dictionary:
		for npc_id in records:
			if npc_id is String and records[npc_id] is Dictionary:
				var record: Dictionary = records[npc_id]
				result["per_npc"][npc_id] = {
					"wins": Integer.read(record.get("wins")),
					"games": Integer.read(record.get("games")),
					"best_diff": Integer.read(record.get("best_diff"), -99, -99),
				}
	return result


static func record_game(stats: Dictionary, npc_id: String, winner: int,
		score_local: int, score_opponent: int, captures: int) -> Dictionary:
	var next := normalize(stats)
	next["games_played"] += 1
	next["total_captures"] += maxi(0, captures)
	match winner:
		1:
			next["wins"] += 1
			next["current_streak"] += 1
			next["best_streak"] = maxi(next["best_streak"], next["current_streak"])
		2:
			next["losses"] += 1
			next["current_streak"] = 0
		_:
			next["draws"] += 1
			next["current_streak"] = 0
	var record: Dictionary = next["per_npc"].get(npc_id,
		{"wins": 0, "games": 0, "best_diff": -99})
	record["games"] += 1
	record["wins"] += 1 if winner == 1 else 0
	record["best_diff"] = maxi(int(record["best_diff"]), score_local - score_opponent)
	next["per_npc"][npc_id] = record
	return next


static func record_forfeit(stats: Dictionary, npc_id: String) -> Dictionary:
	var next := normalize(stats)
	next["games_played"] += 1
	next["losses"] += 1
	next["current_streak"] = 0
	var record: Dictionary = next["per_npc"].get(npc_id,
		{"wins": 0, "games": 0, "best_diff": -99})
	record["games"] += 1
	next["per_npc"][npc_id] = record
	return next
