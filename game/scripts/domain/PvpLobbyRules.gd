## Règles propres au salon PVP : révision, verrouillage, états PRÊT et phases.
## Les modes et les séries sont délégués aux règles génériques.
class_name PvpLobbyRules
extends RefCounted

const PHASE_LOBBY_EDITING := "lobby_editing"
const PHASE_RULES_READY := "rules_ready"
const PHASE_PREPARING := "preparing"
const PHASE_LOADOUT_REVEAL := "loadout_reveal"
const PHASE_LOADOUT_READY := "loadout_ready"
const PHASE_IN_MATCH := "in_match"
const PHASE_ROUND_RESULT := "round_result"
const PHASE_SERIES_COMPLETE := "series_complete"
const PHASES: Array[String] = [
	PHASE_LOBBY_EDITING, PHASE_RULES_READY, PHASE_PREPARING,
	PHASE_LOADOUT_REVEAL, PHASE_LOADOUT_READY, PHASE_IN_MATCH,
	PHASE_ROUND_RESULT, PHASE_SERIES_COMPLETE,
]
const TRANSITIONS := {
	PHASE_LOBBY_EDITING: [PHASE_RULES_READY],
	PHASE_RULES_READY: [PHASE_LOBBY_EDITING, PHASE_PREPARING, PHASE_IN_MATCH],
	PHASE_PREPARING: [PHASE_LOADOUT_REVEAL, PHASE_LOBBY_EDITING],
	PHASE_LOADOUT_REVEAL: [PHASE_LOADOUT_READY, PHASE_LOBBY_EDITING],
	PHASE_LOADOUT_READY: [PHASE_IN_MATCH, PHASE_LOBBY_EDITING],
	PHASE_IN_MATCH: [PHASE_ROUND_RESULT, PHASE_LOBBY_EDITING],
	PHASE_ROUND_RESULT: [PHASE_PREPARING, PHASE_SERIES_COMPLETE, PHASE_LOBBY_EDITING],
	PHASE_SERIES_COMPLETE: [PHASE_LOBBY_EDITING],
}


static func default_config() -> Dictionary:
	return {
		"mode": GameModeRules.MODE_CLASSIC,
		"series": SeriesRules.SERIES_FT1,
		"power_tier": GameModeRules.DEFAULT_POWER_TIER,
		"revision": 0,
		"locked": false,
		"ready_one": false,
		"ready_two": false,
	}


static func normalized(config: Dictionary) -> Dictionary:
	var mode_config := GameModeRules.normalized(config)
	return {
		"mode": mode_config["mode"],
		"series": SeriesRules.normalized(str(config.get("series", SeriesRules.SERIES_FT1))),
		"power_tier": mode_config["power_tier"],
		"revision": maxi(0, int(config.get("revision", 0))),
		"locked": bool(config.get("locked", false)),
		"ready_one": bool(config.get("ready_one", false)),
		"ready_two": bool(config.get("ready_two", false)),
	}


static func validation_problem(config: Dictionary) -> String:
	var mode_problem := GameModeRules.validation_problem(config)
	if mode_problem != "":
		return mode_problem
	if not SeriesRules.FORMATS.has(str(config.get("series", ""))):
		return "Format de série inconnu."
	if int(config.get("revision", -1)) < 0:
		return "Révision invalide."
	return ""


static func can_transition(from_phase: String, to_phase: String) -> bool:
	return PHASES.has(from_phase) and PHASES.has(to_phase) \
		and (TRANSITIONS.get(from_phase, []) as Array).has(to_phase)


static func can_edit(is_host: bool, config: Dictionary) -> bool:
	return is_host and not bool(config.get("locked", false))


static func apply_change(config: Dictionary, key: String, value: Variant,
		is_host: bool, locked: bool = false) -> Dictionary:
	var current := normalized(config)
	if not is_host:
		return {"ok": false, "reason": "Seul l'hôte peut modifier les options.", "config": current}
	if locked or bool(current["locked"]):
		return {"ok": false, "reason": "Les règles sont verrouillées pour la série.", "config": current}
	var next := current.duplicate(true)
	match key:
		"mode":
			if not GameModeRules.MODES.has(str(value)):
				return {"ok": false, "reason": "Mode de jeu inconnu.", "config": current}
			next["mode"] = str(value)
			next["power_tier"] = maxi(int(next["power_tier"]),
				GameModeRules.minimum_power_tier(str(next["mode"])))
		"series":
			if not SeriesRules.FORMATS.has(str(value)):
				return {"ok": false, "reason": "Format de série inconnu.", "config": current}
			next["series"] = str(value)
		"power_tier":
			var tier := int(value)
			if tier < GameModeRules.minimum_power_tier(str(next["mode"])) \
					or tier > GameModeRules.MAX_POWER_TIER:
				return {"ok": false, "reason": "Limite de palier invalide.", "config": current}
			next["power_tier"] = tier
		_:
			return {"ok": false, "reason": "Option inconnue.", "config": current}
	if next[key] == current[key]:
		return {"ok": true, "changed": false, "reason": "", "config": current}
	next["revision"] = int(current["revision"]) + 1
	next["ready_one"] = false
	next["ready_two"] = false
	return {"ok": true, "changed": true, "reason": "", "config": next}


static func apply_ready(config: Dictionary, side: int, revision: int, ready: bool) -> Dictionary:
	var current := normalized(config)
	if side != GameState.PLAYER_ONE and side != GameState.PLAYER_TWO:
		return {"ok": false, "reason": "Joueur inconnu.", "config": current}
	if revision != int(current["revision"]):
		return {"ok": false, "reason": "Révision de règles périmée.", "config": current}
	var next := current.duplicate(true)
	next["ready_one" if side == GameState.PLAYER_ONE else "ready_two"] = ready
	return {"ok": true, "reason": "", "config": next}


static func both_ready(config: Dictionary) -> bool:
	var current := normalized(config)
	return bool(current["ready_one"]) and bool(current["ready_two"])


static func lock(config: Dictionary) -> Dictionary:
	var next := normalized(config)
	next["locked"] = true
	return next

