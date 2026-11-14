## Traduit les actions acceptées en compteurs, sans stockage ni dépendance UI.
extends RefCounted

const PERFECT_SCORE := 16
const PERFECT_BOARD_SIZE := 4


static func increments(kind: String, payload: Dictionary) -> Dictionary:
	var result := {}
	match kind:
		"campaign_result":
			_add(result, "captures", int(payload.get("captures", 0)))
			if int(payload.get("winner", 0)) != GameState.PLAYER_HUMAN:
				return result
			_add(result, "campaign_wins", 1)
			if str(payload.get("opponent_god_id", "")) != "":
				_add(result, "god_wins", 1)
			if bool(payload.get("boss", false)):
				_add(result, "boss_wins", 1)
			if int(payload.get("score_local", 0)) \
					- int(payload.get("score_opponent", 0)) >= 6:
				_add(result, "high_diff_wins", 1)
			if bool(payload.get("series_complete", false)):
				var series := str(payload.get("series", ""))
				if series == SeriesRules.SERIES_FT2:
					_add(result, "series_ft2_wins", 1)
				elif series == SeriesRules.SERIES_FT3:
					_add(result, "series_ft3_wins", 1)
			_add(result, _mode_wins_metric(str(payload.get("mode", ""))), 1)
			if _is_perfect(payload):
				_add(result, "perfect_rounds", 1)
		"pvp_result":
			_add(result, "pvp_matches", 1)
			if _is_perfect(payload):
				_add(result, "perfect_rounds", 1)
		"shop_purchase":
			_add(result, "shop_offers", 1)
			_add(result, "copies_gained", int(payload.get("copies", 0)))
			_add(result, "souls_spent", int(payload.get("souls", 0)))
		"ritual_purchase":
			_add(result, "rituals", 1)
		"upgrade_purchase":
			_add(result, "upgrades", 1)
			_add(result, "souls_spent", int(payload.get("souls", 0)))
	return result


static func _mode_wins_metric(mode: String) -> String:
	if mode == GameModeRules.MODE_CLASSIC:
		return "mode_wins_classic"
	if mode == GameModeRules.MODE_RANDOM:
		return "mode_wins_random"
	if mode == GameModeRules.MODE_MIRROR:
		return "mode_wins_mirror"
	if mode == GameModeRules.MODE_DRAFT:
		return "mode_wins_draft"
	return ""


static func _is_perfect(payload: Dictionary) -> bool:
	if int(payload.get("board_size", PERFECT_BOARD_SIZE)) != PERFECT_BOARD_SIZE:
		return false
	return int(payload.get("score_local", 0)) == PERFECT_SCORE \
		and int(payload.get("score_opponent", 0)) == 0


static func _add(target: Dictionary, metric: String, amount: int) -> void:
	if metric == "" or amount <= 0:
		return
	target[metric] = int(target.get(metric, 0)) + amount
