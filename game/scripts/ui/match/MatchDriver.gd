## MatchDriver.gd
## Contrat commun aux deux façons de jouer un combat : la campagne et le PVP
## local. Le contrôleur d'écran ne connaît que ce contrat ; il ne sait pas si
## l'adversaire est une IA ou un second téléphone.
##
## Un driver décide qui peut jouer, transmet les intentions et signale les fins
## anormales. La présentation du plateau, des cartes et des animations reste
## entièrement dans BoardController et ses vues.
class_name MatchDriver
extends Node

## Partie interrompue : déconnexion, désynchronisation ou erreur réseau.
signal aborted(message: String)
## Fin normale. Le driver campagne ne l'émet pas : il laisse le résultat de
## campagne s'afficher comme avant.
signal finished(winner: int, score_one: int, score_two: int)
## La possibilité de jouer du joueur local vient de changer. En PVP, le tour
## n'est ouvert qu'une fois l'hôte satisfait des deux empreintes d'état.
signal interaction_changed

var turn_manager: TurnManager = null
## Camp de cet appareil (PLAYER_ONE à gauche de l'écran, PLAYER_TWO à droite).
var local_side: int = GameState.PLAYER_ONE
var local_name: String = "Joueur"
var opponent_name: String = "Adversaire"
var local_god: Dictionary = {}
var opponent_god: Dictionary = {}
## Seule la campagne enregistre des statistiques persolnelles.
var records_campaign_stats: bool = true


func setup(manager: TurnManager) -> void:
	turn_manager = manager


## Prépare la partie. Renvoie false si elle ne peut pas démarrer.
func start() -> bool:
	return false


## Le joueur local peut-il agir maintenant ?
func can_submit() -> bool:
	return false


## Transmet un coup du joueur local. Renvoie true s'il a été accepté ou envoyé.
func request_move(_row: int, _col: int, _stone_id: String) -> bool:
	return false


func on_turn_started(_player: int) -> void:
	pass


## Appelé après chaque tour résolu, avant l'ouverture du tour suivant.
func on_turn_ended() -> void:
	pass


func on_game_over(_winner: int, _score_one: int, _score_two: int) -> void:
	pass


func shutdown() -> void:
	pass
