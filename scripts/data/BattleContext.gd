## Passage entre les écrans d'un combat. Aucun de ces champs n'est sauvegardé.
extends Node

var selected_npc_id: String = ""
var forced_first_player: int = 0
var last_winner: int = 0
var last_score_human: int = 0
var last_score_ai: int = 0

func record_result(winner: int, human: int, ai: int) -> void:
	last_winner = winner
	last_score_human = human
	last_score_ai = ai
