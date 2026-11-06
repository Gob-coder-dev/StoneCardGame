## Façade de compatibilité des règles de match.
##
## Le domaine est séparé entre GameModeRules (modes/paliers), SeriesRules
## (FT1/FT2/FT3) et PvpLobbyRules (PRÊT/révision/phases). Cette façade conserve
## l'API historique pour le protocole et les scènes existantes.
class_name MatchRules
extends RefCounted

const ModeRules := preload("res://scripts/domain/GameModeRules.gd")
const FormatRules := preload("res://scripts/domain/SeriesRules.gd")
const LobbyRules := preload("res://scripts/domain/PvpLobbyRules.gd")

const MODE_CLASSIC := ModeRules.MODE_CLASSIC
const MODE_RANDOM := ModeRules.MODE_RANDOM
const MODE_MIRROR := ModeRules.MODE_MIRROR
const MODE_DRAFT := ModeRules.MODE_DRAFT
const MODES := ModeRules.MODES
const MODE_LABELS := ModeRules.MODE_LABELS

const SERIES_FT1 := FormatRules.SERIES_FT1
const SERIES_FT2 := FormatRules.SERIES_FT2
const SERIES_FT3 := FormatRules.SERIES_FT3
const SERIES_FORMATS := FormatRules.FORMATS
const WINS_NEEDED := FormatRules.WINS_NEEDED
const MAX_ROUNDS := FormatRules.MAX_ROUNDS
const SERIES_LABELS := FormatRules.LABELS

const MIN_POWER_TIER := ModeRules.MIN_POWER_TIER
const MAX_POWER_TIER := ModeRules.MAX_POWER_TIER
const DEFAULT_POWER_TIER := ModeRules.DEFAULT_POWER_TIER

const PHASE_LOBBY_EDITING := LobbyRules.PHASE_LOBBY_EDITING
const PHASE_RULES_READY := LobbyRules.PHASE_RULES_READY
const PHASE_PREPARING := LobbyRules.PHASE_PREPARING
const PHASE_LOADOUT_REVEAL := LobbyRules.PHASE_LOADOUT_REVEAL
const PHASE_LOADOUT_READY := LobbyRules.PHASE_LOADOUT_READY
const PHASE_IN_MATCH := LobbyRules.PHASE_IN_MATCH
const PHASE_ROUND_RESULT := LobbyRules.PHASE_ROUND_RESULT
const PHASE_SERIES_COMPLETE := LobbyRules.PHASE_SERIES_COMPLETE
const PHASES := LobbyRules.PHASES
const TRANSITIONS := LobbyRules.TRANSITIONS


static func default_config() -> Dictionary:
	return LobbyRules.default_config()


static func normalized(config: Dictionary) -> Dictionary:
	return LobbyRules.normalized(config)


static func validation_problem(config: Dictionary) -> String:
	return LobbyRules.validation_problem(config)


static func mode_label(mode: String) -> String:
	return ModeRules.mode_label(mode)


static func series_label(series: String) -> String:
	return FormatRules.label(series)


static func wins_needed(series: String) -> int:
	return FormatRules.wins_needed(series)


static func max_rounds(series: String) -> int:
	return FormatRules.max_rounds(series)


static func mode_keeps_loadout(mode: String) -> bool:
	return FormatRules.mode_keeps_loadout(mode)


static func mode_generates_loadout(mode: String) -> bool:
	return ModeRules.generates_loadout(mode)


static func mode_requires_draft(mode: String) -> bool:
	return ModeRules.requires_draft(mode)


static func minimum_power_tier(mode: String) -> int:
	return ModeRules.minimum_power_tier(mode)


static func requires_preparation(mode: String) -> bool:
	return ModeRules.requires_preparation(mode)


static func can_transition(from_phase: String, to_phase: String) -> bool:
	return LobbyRules.can_transition(from_phase, to_phase)


static func can_edit(is_host: bool, config: Dictionary) -> bool:
	return LobbyRules.can_edit(is_host, config)


static func apply_change(config: Dictionary, key: String, value: Variant,
		is_host: bool, locked: bool = false) -> Dictionary:
	return LobbyRules.apply_change(config, key, value, is_host, locked)


static func apply_ready(config: Dictionary, side: int, revision: int,
		ready: bool) -> Dictionary:
	return LobbyRules.apply_ready(config, side, revision, ready)


static func both_ready(config: Dictionary) -> bool:
	return LobbyRules.both_ready(config)


static func lock(config: Dictionary) -> Dictionary:
	return LobbyRules.lock(config)


static func summary_lines(config: Dictionary) -> Array[String]:
	var current := normalized(config)
	var lines: Array[String] = [
		"Mode : %s" % mode_label(str(current["mode"])),
		"Série : %s" % series_label(str(current["series"])),
	]
	if str(current["mode"]) != MODE_CLASSIC:
		lines.append("Palier maximal : %d" % int(current["power_tier"]))
	lines.append("Révision : %d" % int(current["revision"]))
	return lines


static func summary(config: Dictionary) -> String:
	return " • ".join(summary_lines(config))
