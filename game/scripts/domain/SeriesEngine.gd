## SeriesEngine.gd
## Opérations pures d'une série, communes à la campagne et au PVP. Un match se
## termine, une manche est enregistrée, puis la série décide de la suite.
class_name SeriesEngine
extends RefCounted

const NEXT_IDLE := "idle"
const NEXT_MATCH := "match"
const NEXT_PREPARATION := "preparation"
const NEXT_COMPLETE := "complete"


static func begin(series_id: String, rules: Dictionary, generation_seed: int) -> SeriesState:
	return SeriesState.create(series_id, rules, generation_seed)


## Enregistre le verdict d'une manche. Une égalité ne marque aucun point et
## n'arrête jamais la série : elle ouvre simplement la manche suivante.
static func record_round(series: SeriesState, round_winner: int,
		score_one: int = 0, score_two: int = 0) -> Dictionary:
	if series == null:
		return {"ok": false, "reason": "Série absente."}
	if series.finished:
		return {"ok": false, "reason": "La série est déjà terminée.", "series": series}
	if round_winner != GameState.PLAYER_NONE \
			and round_winner != GameState.PLAYER_ONE \
			and round_winner != GameState.PLAYER_TWO:
		return {"ok": false, "reason": "Vainqueur de manche invalide.", "series": series}
	var entry := {
		"round_index": series.round_index,
		"winner": round_winner,
		"score_one": score_one,
		"score_two": score_two,
		"draw": round_winner == GameState.PLAYER_NONE,
	}
	series.round_results.append(entry)
	var round_won := round_winner != GameState.PLAYER_NONE
	if round_winner == GameState.PLAYER_ONE:
		series.wins_one += 1
	elif round_winner == GameState.PLAYER_TWO:
		series.wins_two += 1
	else:
		series.ties += 1
	series.round_index += 1
	var final_winner := GameState.PLAYER_NONE
	if series.wins_one >= series.wins_needed:
		final_winner = GameState.PLAYER_ONE
	elif series.wins_two >= series.wins_needed:
		final_winner = GameState.PLAYER_TWO
	if final_winner != GameState.PLAYER_NONE:
		series.finished = true
		series.winner = final_winner
	# Invariant : une égalité ne peut ni terminer la série ni modifier les
	# scores. Le nombre de manches hors égalités ne peut pas dépasser le format,
	# puisque le premier à N victoires est atteint au plus tard à 2N-1 manches.
	return {
		"ok": true,
		"reason": "",
		"series": series,
		"round_won": round_won,
		"series_finished": series.finished,
		"final_winner": series.winner,
		"next_round_index": series.round_index,
	}


## Prépare les loadouts d'une nouvelle manche. Classique et Miroir conservent
## les loadouts de la série ; Aléatoire et Sélection les effacent pour forcer
## une nouvelle génération ou un nouveau draft.
static func prepare_round(series: SeriesState, new_loadout_one: GameLoadout = null,
		new_loadout_two: GameLoadout = null) -> Dictionary:
	if series == null:
		return {"ok": false, "reason": "Série absente.", "series": series}
	if series.finished:
		return {"ok": false, "reason": "La série est terminée.", "series": series}
	if series.keeps_loadouts():
		if series.loadout_one == null or series.loadout_two == null:
			return {"ok": false, "reason": "Loadouts conservés manquants.", "series": series}
		return {"ok": true, "reason": "", "series": series,
			"loadout_one": series.loadout_one.copy(), "loadout_two": series.loadout_two.copy(),
			"reused": true}
	if new_loadout_one == null or new_loadout_two == null:
		series.loadout_one = null
		series.loadout_two = null
		return {"ok": true, "reason": "", "series": series,
			"loadout_one": null, "loadout_two": null, "reused": false}
	series.loadout_one = null
	series.loadout_two = null
	return {"ok": true, "reason": "", "series": series,
		"loadout_one": new_loadout_one.copy(), "loadout_two": new_loadout_two.copy(),
		"reused": false}


## Fige les loadouts d'une manche pour les modes qui les conservent. Les modes
## à régénération ne les mémorisent pas dans la série.
static func remember_loadouts(series: SeriesState, loadout_one: GameLoadout,
		loadout_two: GameLoadout) -> void:
	if series == null or not series.keeps_loadouts():
		return
	series.loadout_one = loadout_one.copy()
	series.loadout_two = loadout_two.copy()


## Abandon : l'adversaire reçoit les victoires qui lui manquaient pour atteindre
## l'objectif, afin que le score final reste lisible. Une égalité déjà comptée
## n'est jamais effacée. La manche déjà jouée garde son propre résultat.
static func concede(series: SeriesState, winner_side: int) -> Dictionary:
	if series == null:
		return {"ok": false, "reason": "Série absente."}
	if series.finished:
		return {"ok": false, "reason": "La série est déjà terminée.", "series": series}
	if winner_side != GameState.PLAYER_ONE and winner_side != GameState.PLAYER_TWO:
		return {"ok": false, "reason": "Vainqueur de série invalide.", "series": series}
	if winner_side == GameState.PLAYER_ONE:
		series.wins_one = series.wins_needed
	else:
		series.wins_two = series.wins_needed
	series.finished = true
	series.winner = winner_side
	series.abandoned = true
	return {"ok": true, "reason": "", "series": series, "final_winner": winner_side}


static func public_state(series: SeriesState) -> Dictionary:
	if series == null:
		return {}
	return {
		"series_id": series.series_id,
		"mode": series.mode,
		"series": series.series_format,
		"rules_revision": series.rules_revision,
		"power_tier": series.power_tier,
		"wins_one": series.wins_one,
		"wins_two": series.wins_two,
		"wins_needed": series.wins_needed,
		"max_rounds": series.max_rounds,
		"round_index": series.round_index,
		"ties": series.ties,
		"finished": series.finished,
		"winner": series.winner,
		"abandoned": series.abandoned,
		"seed": series.generation_seed,
		"keeps_loadouts": series.keeps_loadouts(),
	}


## Prochaine étape après un résultat de manche.
static func next_step(series: SeriesState) -> String:
	if series == null:
		return NEXT_IDLE
	if series.finished:
		return NEXT_COMPLETE
	if GameModeRules.requires_preparation(series.mode):
		return NEXT_PREPARATION
	return NEXT_MATCH
