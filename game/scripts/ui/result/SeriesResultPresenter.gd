## SeriesResultPresenter.gd
## Présentation commune du résultat d'une série FT2/FT3. La campagne et le PVP
## lisent exactement les mêmes textes : titre de manche ou verdict final, score
## du round, score de la série et objectif. Aucune règle et aucune écriture ici.
class_name SeriesResultPresenter
extends RefCounted

const GameModeRulesModel := preload("res://scripts/domain/GameModeRules.gd")
const SeriesRulesModel := preload("res://scripts/domain/SeriesRules.gd")


## Vrai pour une série multi-manches. Le format FT1 garde l'écran classique.
static func is_series(series: Dictionary) -> bool:
	return series.has("wins_needed") \
		and str(series.get("series", "")) != SeriesRulesModel.SERIES_FT1


## Score d'un camp, du point de vue du joueur local. Les noms arrivent déjà
## raccourcis par l'écran : le format reste identique partout.
static func score_line(score_one: int, score_two: int, local_one: bool,
		local_name: String, remote_name: String) -> String:
	var mine := score_one if local_one else score_two
	var theirs := score_two if local_one else score_one
	return "%s %d  —  %d %s" % [local_name, mine, theirs, remote_name]


## Vue complète à partir de l'état public de la série et du résultat de manche.
## `local_side` est le camp du joueur : PLAYER_ONE en campagne, le côté réseau
## en PVP. Une série terminée reprend le verdict classique et le score final.
static func view(series: Dictionary, round_result: Dictionary, local_side: int,
		local_name: String, remote_name: String) -> Dictionary:
	var local_one := local_side == GameState.PLAYER_ONE
	var my_wins := int(series.get("wins_one" if local_one else "wins_two", 0))
	var other_wins := int(series.get("wins_two" if local_one else "wins_one", 0))
	var round_winner := int(round_result.get("winner", GameState.PLAYER_NONE))
	var finished := bool(series.get("finished", false))
	var series_winner := int(series.get("winner", GameState.PLAYER_NONE))
	var round_number := maxi(1, int(series.get("round_index", 1)) - 1)
	var abandoned := bool(series.get("abandoned", false))
	var title := _round_title(round_number, round_winner, local_side)
	if finished:
		title = _final_title(series_winner, local_side)
	return {
		"finished": finished,
		"title": title,
		"round_number": round_number,
		"round_score": score_line(int(round_result.get("score_one", 0)),
			int(round_result.get("score_two", 0)), local_one, local_name, remote_name),
		"score": "%s %d  —  %d %s" % [local_name, my_wins, other_wins, remote_name],
		"caption": "Mode de jeu : %s • %s" % [
			GameModeRulesModel.mode_label(str(series.get("mode", ""))),
			SeriesRulesModel.objective_label(str(series.get("series", "")))],
		"abandoned": abandoned,
		"note": "Série abandonnée" if abandoned else "",
		"local_won": finished and series_winner == local_side,
		"local_one": local_one,
	}


static func _round_title(number: int, winner: int, local_side: int) -> String:
	if winner == GameState.PLAYER_NONE:
		return "MANCHE %d ÉGALITÉ" % number
	if winner == local_side:
		return "MANCHE %d GAGNÉE" % number
	return "MANCHE %d PERDUE" % number


static func _final_title(winner: int, local_side: int) -> String:
	if winner == GameState.PLAYER_NONE:
		return "ÉGALITÉ"
	return "VICTOIRE !" if winner == local_side else "DÉFAITE..."
