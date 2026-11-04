## PvpMatchContext.gd — AutoLoad
## Données transitoires du match PVP local. Rien n'est sauvegardé ici : aucun
## champ du profil du joueur n'est lu pour écrire, et aucune statistique de
## campagne n'est enregistrée par ce mode.
##
## Un seul match vit à la fois ; `clear()` le termine. Le contexte est rempli
## par le salon après validation complète de la configuration de l'hôte.
extends Node

## Configuration validée du match en cours.
var match_id: String = ""
var seed: int = 1
var blocked_cells: Array = []
var starting_player: int = GameState.PLAYER_ONE
var participants: Array = []
## Association peer_id -> PLAYER_ONE / PLAYER_TWO.
var peer_sides: Dictionary = {}
## Configuration brute validée : rejouée telle quelle quand les deux appareils
## confirment le lancement après le pile ou face.
var raw_config: Dictionary = {}
## Camp de cet appareil et identifiant réseau local.
var local_side: int = GameState.PLAYER_ONE
var local_peer_id: int = 0
## Profils échangés pendant la poignée de main (pseudo, dieu et deck).
var local_name: String = ""
var local_god_id: String = ""
var local_deck: Array = []
var remote_name: String = ""
var remote_god_id: String = ""
var remote_deck: Array = []
## Suivi de partie : mis à jour par le coordinateur réseau, jamais sauvegardé.
var turn_number: int = 0
var last_result: Dictionary = {}


func is_active() -> bool:
	return match_id != ""


## Remplit le contexte depuis la configuration validée de l'hôte.
func begin(config: Dictionary, side: int, peer_id: int,
		local_profile: Dictionary, remote_profile: Dictionary) -> void:
	clear()
	raw_config = config.duplicate(true)
	match_id = str(config.get("match_id", ""))
	seed = int(config.get("seed", 1))
	blocked_cells = (config.get("blocked_cells", []) as Array).duplicate()
	starting_player = int(config.get("starting_player", GameState.PLAYER_ONE))
	local_side = side
	local_peer_id = peer_id
	participants = []
	peer_sides = {}
	for entry in config.get("participants", []):
		var participant: Dictionary = (entry as Dictionary).duplicate(true)
		participants.append(participant)
		peer_sides[int(participant.get("peer_id", 0))] = int(participant.get("side", 0))
	local_name = str(local_profile.get("name", "Joueur"))
	local_god_id = str(local_profile.get("god_id", ""))
	local_deck = (local_profile.get("deck", []) as Array).duplicate()
	remote_name = str(remote_profile.get("name", "Adversaire"))
	remote_god_id = str(remote_profile.get("god_id", ""))
	remote_deck = (remote_profile.get("deck", []) as Array).duplicate()
	turn_number = 0
	last_result = {}


func clear() -> void:
	raw_config = {}
	match_id = ""
	seed = 1
	blocked_cells = []
	starting_player = GameState.PLAYER_ONE
	participants = []
	peer_sides = {}
	local_side = GameState.PLAYER_ONE
	local_peer_id = 0
	local_name = ""
	local_god_id = ""
	local_deck = []
	remote_name = ""
	remote_god_id = ""
	remote_deck = []
	turn_number = 0
	last_result = {}


## La configuration validée, prête à être rediffusée sur `match_start`.
func config() -> Dictionary:
	return raw_config.duplicate(true)


func side_of_peer(peer_id: int) -> int:
	return int(peer_sides.get(peer_id, GameState.PLAYER_NONE))


func peer_of_side(side: int) -> int:
	for peer_id in peer_sides:
		if int(peer_sides[peer_id]) == side:
			return int(peer_id)
	return 0


func remote_side() -> int:
	return GameState.PLAYER_TWO if local_side == GameState.PLAYER_ONE else GameState.PLAYER_ONE


func participant_for_side(side: int) -> Dictionary:
	for entry in participants:
		if int((entry as Dictionary).get("side", 0)) == side:
			return (entry as Dictionary).duplicate(true)
	return {}


func deck_of_side(side: int) -> Array:
	var participant := participant_for_side(side)
	return (participant.get("deck", []) as Array).duplicate()


func local_profile() -> Dictionary:
	return {"name": local_name, "god_id": local_god_id, "deck": local_deck.duplicate()}


func remote_profile() -> Dictionary:
	return {"name": remote_name, "god_id": remote_god_id, "deck": remote_deck.duplicate()}


func record_result(winner: int, score_one: int, score_two: int) -> void:
	last_result = {"winner": winner, "score_one": score_one, "score_two": score_two}
