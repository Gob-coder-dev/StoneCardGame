## SeriesState.gd
## État générique d'une série, partagé par la campagne et le PVP. Il n'écrit
## jamais dans PlayerData et ne dépend d'aucun transport.
class_name SeriesState
extends RefCounted

var series_id: String = ""
var mode: String = GameModeRules.MODE_CLASSIC
var series_format: String = SeriesRules.SERIES_FT1
var rules: Dictionary = {}
var rules_revision: int = 0
var power_tier: int = GameModeRules.DEFAULT_POWER_TIER
var wins_needed: int = 1
var max_rounds: int = 1
var wins_one: int = 0
var wins_two: int = 0
var round_index: int = 1
var ties: int = 0
var finished: bool = false
var winner: int = GameState.PLAYER_NONE
## Une série concédée garde son score réel et s'affiche comme abandonnée.
var abandoned: bool = false
var seed: int = 0
## Loadouts conservés pour les modes Classique et Miroir.
var loadout_one: GameLoadout = null
var loadout_two: GameLoadout = null
## Historique des manches, sans deck (les loadouts conservés vivent à part).
var round_results: Array = []


static func create(p_series_id: String, p_rules: Dictionary, p_seed: int) -> SeriesState:
	var mode_config := GameModeRules.normalized(p_rules)
	var rules_value := {
		"mode": mode_config["mode"],
		"series": SeriesRules.normalized(str(p_rules.get("series", SeriesRules.SERIES_FT1))),
		"power_tier": mode_config["power_tier"],
		"revision": maxi(0, int(p_rules.get("revision", 0))),
	}
	var state := SeriesState.new()
	state.series_id = p_series_id
	state.rules = rules_value.duplicate(true)
	state.rules_revision = int(rules_value["revision"])
	state.mode = str(rules_value["mode"])
	state.series_format = str(rules_value["series"])
	state.power_tier = int(rules_value["power_tier"])
	state.wins_needed = SeriesRules.wins_needed(state.series_format)
	state.max_rounds = SeriesRules.max_rounds(state.series_format)
	state.seed = p_seed
	return state


func keeps_loadouts() -> bool:
	return SeriesRules.mode_keeps_loadout(mode)


func is_draw_round(round_winner: int) -> bool:
	return round_winner == GameState.PLAYER_NONE


func total_scored_rounds() -> int:
	return wins_one + wins_two


func copy() -> SeriesState:
	var state := SeriesState.create(series_id, rules, seed)
	state.mode = mode
	state.series_format = series_format
	state.rules_revision = rules_revision
	state.power_tier = power_tier
	state.wins_needed = wins_needed
	state.max_rounds = max_rounds
	state.wins_one = wins_one
	state.wins_two = wins_two
	state.round_index = round_index
	state.ties = ties
	state.finished = finished
	state.winner = winner
	state.abandoned = abandoned
	state.loadout_one = loadout_one.copy() if loadout_one != null else null
	state.loadout_two = loadout_two.copy() if loadout_two != null else null
	state.round_results = round_results.duplicate(true)
	return state


func to_dict() -> Dictionary:
	return {
		"series_id": series_id,
		"mode": mode,
		"series": series_format,
		"rules_revision": rules_revision,
		"power_tier": power_tier,
		"wins_needed": wins_needed,
		"max_rounds": max_rounds,
		"wins_one": wins_one,
		"wins_two": wins_two,
		"round_index": round_index,
		"ties": ties,
		"finished": finished,
		"winner": winner,
		"seed": seed,
		"loadout_one": loadout_one.to_dict() if loadout_one != null else {},
		"loadout_two": loadout_two.to_dict() if loadout_two != null else {},
		"round_results": round_results.duplicate(true),
	}


static func from_dict(data: Dictionary) -> SeriesState:
	var rules := {
		"mode": str(data.get("mode", GameModeRules.MODE_CLASSIC)),
		"series": str(data.get("series", SeriesRules.SERIES_FT1)),
		"power_tier": int(data.get("power_tier", GameModeRules.DEFAULT_POWER_TIER)),
		"revision": int(data.get("rules_revision", 0)),
	}
	var state := SeriesState.create(str(data.get("series_id", "")), rules,
		int(data.get("seed", 0)))
	state.wins_needed = int(data.get("wins_needed", state.wins_needed))
	state.max_rounds = int(data.get("max_rounds", state.max_rounds))
	state.wins_one = int(data.get("wins_one", 0))
	state.wins_two = int(data.get("wins_two", 0))
	state.round_index = int(data.get("round_index", 1))
	state.ties = int(data.get("ties", 0))
	state.finished = bool(data.get("finished", false))
	state.winner = int(data.get("winner", GameState.PLAYER_NONE))
	var one: Variant = data.get("loadout_one", {})
	var two: Variant = data.get("loadout_two", {})
	if one is Dictionary and not (one as Dictionary).is_empty():
		state.loadout_one = GameLoadout.from_dict(one)
	if two is Dictionary and not (two as Dictionary).is_empty():
		state.loadout_two = GameLoadout.from_dict(two)
	state.round_results = (data.get("round_results", []) as Array).duplicate(true)
	return state
