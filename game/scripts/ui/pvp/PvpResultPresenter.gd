## Présentation pure du résultat PVP. Elle transforme un snapshot en textes et
## action principale, sans connaître les boutons, les scènes ou la session.
class_name PvpResultPresenter
extends RefCounted

const SeriesPresenter := preload("res://scripts/ui/result/SeriesResultPresenter.gd")


static func simple(result: Dictionary, local_side: int, local_name: String,
		remote_name: String, has_series: bool) -> Dictionary:
	var winner := int(result.get("winner", GameState.PLAYER_NONE))
	var score_one := int(result.get("score_one", 0))
	var score_two := int(result.get("score_two", 0))
	var local_one := local_side == GameState.PLAYER_ONE
	var local_score := score_one if local_one else score_two
	var remote_score := score_two if local_one else score_one
	var verdict := "ÉGALITÉ"
	if winner == local_side:
		verdict = "VICTOIRE !"
	elif winner != GameState.PLAYER_NONE:
		verdict = "DÉFAITE..."
	return {
		"title": verdict,
		"detail": "PVP LOCAL • %s contre %s" % [local_name, remote_name],
		"score": "%s %d  —  %d %s" % [local_name, local_score, remote_score, remote_name],
		"status": "Égalité : rejouez une partie." if winner == GameState.PLAYER_NONE else "",
		"primary_mode": "series_rematch" if has_series else "classic_rematch",
		"primary_text": "REVANCHE",
		"winner": winner,
		"local_one": local_one,
	}


## Une manche de série parle comme la campagne : verdict de manche, score du
## round puis score de série dans le cadre commun. La fin de série reprend le
## menu victoire/défaite classique et son action « nouvelle série ».
static func series(series_state: Dictionary, round_result: Dictionary, local_side: int,
		local_name: String, remote_name: String) -> Dictionary:
	var view := SeriesPresenter.view(series_state, round_result, local_side,
		local_name, remote_name)
	var finished := bool(view.get("finished", false))
	var winner := int(series_state.get("winner", GameState.PLAYER_NONE))
	var status := "Objectif : premier à %d victoire(s)." % int(series_state.get("wins_needed", 1))
	if finished:
		status = "Vainqueur de la série : %s" % (local_name if winner == local_side else (
			remote_name if winner != GameState.PLAYER_NONE else "égalité"))
	return {
		"title": str(view["title"]),
		"detail": "PVP LOCAL • %s contre %s" % [local_name, remote_name],
		"score": str(view["round_score"]),
		"series_view": view,
		"status": status,
		"primary_mode": "series_rematch" if finished else "next",
		"primary_text": "NOUVELLE SÉRIE" if finished else "PARTIE SUIVANTE",
		"winner": winner if finished else int(round_result.get("winner", GameState.PLAYER_NONE)),
		"local_one": local_side == GameState.PLAYER_ONE,
	}
