## Règles génériques d'une série de parties. Indépendantes du PVP et de la
## persistance de campagne.
class_name SeriesRules
extends RefCounted

const SERIES_FT1 := "ft1"
const SERIES_FT2 := "ft2"
const SERIES_FT3 := "ft3"
const FORMATS: Array[String] = [SERIES_FT1, SERIES_FT2, SERIES_FT3]
const WINS_NEEDED := {SERIES_FT1: 1, SERIES_FT2: 2, SERIES_FT3: 3}
const MAX_ROUNDS := {SERIES_FT1: 1, SERIES_FT2: 3, SERIES_FT3: 5}
const LABELS := {
	SERIES_FT1: "FT1 — une victoire",
	SERIES_FT2: "FT2 — premier à 2 victoires",
	SERIES_FT3: "FT3 — premier à 3 victoires",
}
const OBJECTIVES := {
	SERIES_FT1: "premier à 1",
	SERIES_FT2: "premier à 2",
	SERIES_FT3: "premier à 3",
}


static func normalized(value: String) -> String:
	return value if FORMATS.has(value) else SERIES_FT1


static func label(value: String) -> String:
	return str(LABELS.get(value, value))


## Formulation courte des cartes de résultat : « FT2 : premier à 2 ».
static func objective_label(value: String) -> String:
	var format := normalized(value)
	return "%s : %s" % [format.to_upper(), str(OBJECTIVES.get(format, ""))]


static func wins_needed(value: String) -> int:
	return int(WINS_NEEDED.get(value, 1))


static func max_rounds(value: String) -> int:
	return int(MAX_ROUNDS.get(value, 1))


static func mode_keeps_loadout(mode: String) -> bool:
	return mode == GameModeRules.MODE_CLASSIC or mode == GameModeRules.MODE_MIRROR

