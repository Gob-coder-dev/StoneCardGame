## Orchestration locale des modes et séries de campagne. Elle expose les mêmes
## concepts qu'une préparation PVP, mais ne dépend ni d'ENet ni du salon.
class_name CampaignModeSession
extends RefCounted

const PHASE_RULES_READY := "rules_ready"
const PHASE_PREPARING := "preparing"
const PHASE_LOADOUT_REVEAL := "loadout_reveal"
const PHASE_IN_MATCH := "in_match"
const PHASE_ROUND_RESULT := "round_result"
const PHASE_SERIES_COMPLETE := "series_complete"

signal state_changed(state: Dictionary)
signal preparation_completed(loadout_one: GameLoadout, loadout_two: GameLoadout)
signal failed(message: String)

var _service: ModePreparationService
var _rules: Dictionary = {}
var _profile_one: Dictionary = {}
var _profile_two: Dictionary = {}
var _series: SeriesState = null
var _draft: DraftEngine = null
var _loadout_one: GameLoadout = null
var _loadout_two: GameLoadout = null
var _phase := PHASE_RULES_READY
var _ai_choice_policy: Callable


func _init(service: ModePreparationService = null) -> void:
	_service = service if service != null else ModePreparationService.new()
	_ai_choice_policy = _default_ai_choice


func configure(config: Dictionary, player_profile: Dictionary,
		opponent_profile: Dictionary, seed: int) -> Dictionary:
	var mode_config := GameModeRules.normalized(config)
	_rules = {
		"mode": mode_config["mode"],
		"power_tier": mode_config["power_tier"],
		"series": SeriesRules.normalized(str(config.get("series", SeriesRules.SERIES_FT1))),
		"generator_god_id": str(config.get("generator_god_id", "")),
		"generator_min_god_cards": int(config.get("generator_min_god_cards", 0)),
		"mirror_fixed_deck": (config.get("mirror_fixed_deck", []) as Array).duplicate(),
		"revision": 0,
	}
	_profile_one = _profile_snapshot(player_profile)
	_profile_two = _profile_snapshot(opponent_profile)
	_series = SeriesEngine.begin("campaign-%d" % seed, _rules, seed)
	return prepare_round()


func set_ai_choice_policy(policy: Callable) -> void:
	_ai_choice_policy = policy if policy.is_valid() else _default_ai_choice


func prepare_round() -> Dictionary:
	if _series == null or _series.finished:
		return _failure("Aucune série de campagne active.")
	_draft = null
	_loadout_one = null
	_loadout_two = null
	var reused := SeriesEngine.prepare_round(_series)
	if _series.keeps_loadouts() and bool(reused.get("ok", false)):
		_loadout_one = reused.get("loadout_one") as GameLoadout
		_loadout_two = reused.get("loadout_two") as GameLoadout
		_phase = PHASE_LOADOUT_REVEAL
		_emit_state()
		return {"ok": true, "requires_draft": false, "reused": true}
	var mode := str(_rules["mode"])
	var round_seed := _round_seed()
	if GameModeRules.requires_draft(mode):
		var created := _service.create_draft(round_seed, int(_rules["power_tier"]),
			_profile_one, _profile_two)
		if not bool(created.get("ok", false)):
			return _failure(str(created.get("reason", "Draft impossible.")))
		_draft = created["draft"] as DraftEngine
		_phase = PHASE_PREPARING
		_emit_state()
		return {"ok": true, "requires_draft": true, "reused": false}
	var prepared := _service.prepare_immediate(mode, round_seed,
		int(_rules["power_tier"]), _profile_one, _profile_two, _rules)
	if not bool(prepared.get("ok", false)):
		return _failure(str(prepared.get("reason", "Préparation impossible.")))
	_install_loadouts(prepared["loadout_one"], prepared["loadout_two"])
	return {"ok": true, "requires_draft": false, "reused": false}


func choose_player(stone_id: String) -> bool:
	if _draft == null or _draft.complete_for(GameState.PLAYER_ONE):
		return false
	var step := _draft.step_for(GameState.PLAYER_ONE)
	var chosen := _draft.choose(GameState.PLAYER_ONE, stone_id)
	if not bool(chosen.get("ok", false)):
		return false
	if not _draft.complete_for(GameState.PLAYER_TWO):
		var offers := _draft.offers_for_step(GameState.PLAYER_TWO, step)
		var ai_pick := str(_ai_choice_policy.call(offers.duplicate(), _draft.public_state(
			GameState.PLAYER_TWO), _round_seed() + step))
		if not offers.has(ai_pick):
			ai_pick = str(offers[0]) if not offers.is_empty() else ""
		if ai_pick != "":
			_draft.choose(GameState.PLAYER_TWO, ai_pick)
	if _draft.is_complete():
		_finish_draft()
	else:
		_emit_state()
	return true


func advance(delta: float) -> bool:
	if _draft == null or not _draft.advance(delta):
		return false
	_finish_draft()
	return true


func is_drafting() -> bool:
	return _draft != null and not _draft.is_complete()


func remaining_seconds() -> float:
	return _draft.remaining_seconds() if _draft != null else 0.0


func confirm_local() -> bool:
	if _loadout_one == null or _loadout_two == null:
		return false
	_phase = PHASE_IN_MATCH
	preparation_completed.emit(_loadout_one.copy(), _loadout_two.copy())
	_emit_state()
	return true


func record_round(winner: int, score_one: int, score_two: int) -> Dictionary:
	var result := SeriesEngine.record_round(_series, winner, score_one, score_two)
	if bool(result.get("ok", false)):
		_phase = PHASE_SERIES_COMPLETE if _series.finished else PHASE_ROUND_RESULT
		_emit_state()
	return result


func public_state() -> Dictionary:
	return {
		"phase": _phase,
		"rules": _rules.duplicate(true),
		"series": SeriesEngine.public_state(_series),
		"own_loadout": _loadout_one.to_dict() if _loadout_one != null else {},
		"opponent_loadout": _loadout_two.to_dict() if _loadout_two != null else {},
		"draft": _draft.public_state(GameState.PLAYER_ONE) if _draft != null else {},
		"remaining_seconds": _draft.remaining_seconds() if _draft != null else 0.0,
	}


func series() -> SeriesState:
	return _series


func rules() -> Dictionary:
	return _rules.duplicate(true)


func loadout_one() -> GameLoadout:
	return _loadout_one.copy() if _loadout_one != null else null


func loadout_two() -> GameLoadout:
	return _loadout_two.copy() if _loadout_two != null else null


func _finish_draft() -> void:
	var prepared := _service.loadouts_from_draft(_draft, _round_seed())
	if not bool(prepared.get("ok", false)):
		_failure(str(prepared.get("reason", "Draft invalide.")))
		return
	_install_loadouts(prepared["loadout_one"], prepared["loadout_two"])


func _install_loadouts(one: GameLoadout, two: GameLoadout) -> void:
	_loadout_one = one.copy()
	_loadout_two = two.copy()
	SeriesEngine.remember_loadouts(_series, _loadout_one, _loadout_two)
	_phase = PHASE_LOADOUT_REVEAL
	_emit_state()


func _round_seed() -> int:
	return _series.seed + _series.round_index * 104729


static func _profile_snapshot(profile: Dictionary) -> Dictionary:
	return {
		"name": str(profile.get("name", "")),
		"god_id": str(profile.get("god_id", "")),
		"deck": (profile.get("deck", []) as Array).duplicate(true),
	}


static func _default_ai_choice(offers: Array, _state: Dictionary, seed: int) -> String:
	if offers.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return str(offers[rng.randi_range(0, offers.size() - 1)])


func _emit_state() -> void:
	state_changed.emit(public_state())


func _failure(message: String) -> Dictionary:
	failed.emit(message)
	return {"ok": false, "reason": message}
