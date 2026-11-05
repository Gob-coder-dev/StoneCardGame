## Passage entre les écrans d'un combat. Aucun de ces champs n'est sauvegardé.
extends Node

const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")

var selected_npc_id: String = ""
## Source du chemin de rencontres ouvert (id de dieu ou Pr.Stone). Elle permet
## de revenir au bon serpentin depuis l'avant-combat et le résultat.
var selected_source_id: String = ""
## Adversaire complet de la rencontre en cours (deck, dieu et profil d'IA).
## Les adversaires historiques de npcs.json restent disponibles : la lecture
## choisit la source qui correspond à selected_npc_id.
var selected_opponent: Dictionary = {}
var forced_first_player: int = 0
var last_winner: int = 0
var last_score_human: int = 0
var last_score_ai: int = 0
var last_captures_human: int = 0
var last_result_npc_id: String = ""
## Une victoire ne débloque la suite que lorsque le profil a réellement été
## écrit. L'erreur reste disponible sur l'écran de résultat pour une nouvelle
## tentative, sans compter deux fois la partie.
var last_result_saved: bool = true
var last_save_error: Error = OK


## Mémorise le chemin choisi avant même qu'un adversaire ne soit généré.
func select_source(source_id: String) -> void:
	selected_source_id = source_id


## Mémorise la rencontre et son identifiant de statistiques en une seule fois.
func select_opponent(opponent: Dictionary) -> void:
	selected_opponent = opponent.duplicate(true)
	selected_npc_id = str(selected_opponent.get("id", ""))
	var source := OpponentCatalogModel.source_id_of(selected_opponent)
	if source != "":
		selected_source_id = source


## Source du chemin à rouvrir : la dernière choisie, sinon celle déduite de
## l'adversaire courant. Vide pour un PNJ historique.
func current_source_id() -> String:
	if selected_source_id != "":
		return selected_source_id
	return OpponentCatalogModel.source_id_of(selected_opponent)


## Source à rouvrir pour la navigation : le chemin courant, sinon le dieu actif
## du joueur. Ce repli est partagé par l'avant-combat, le chemin et le résultat.
func navigation_source_id() -> String:
	var source := current_source_id()
	if source != "":
		return source
	return PlayerData.player_god_id


## Adversaire à utiliser par les écrans de combat. Un adversaire généré n'est
## retenu que si son identifiant est bien celui de la rencontre sélectionnée ;
## sinon on retombe sur le catalogue historique (tests, anciennes sauvegardes).
func current_opponent() -> Dictionary:
	if not selected_opponent.is_empty() and str(selected_opponent.get("id", "")) == selected_npc_id:
		return selected_opponent.duplicate(true)
	return StoneLoader.get_npc(selected_npc_id)


## Enregistre un résultat déjà persistant (fixtures, import ou ancien appel).
## Le plateau utilise `prepare_result()` puis `persist_result()`.
func record_result(winner: int, human: int, ai: int) -> void:
	last_winner = winner
	last_score_human = human
	last_score_ai = ai
	last_captures_human = 0
	last_result_npc_id = selected_npc_id
	last_result_saved = true
	last_save_error = OK


func prepare_result(winner: int, human: int, ai: int, captures_human: int) -> void:
	last_winner = winner
	last_score_human = human
	last_score_ai = ai
	last_captures_human = captures_human
	last_result_npc_id = selected_npc_id
	last_result_saved = false
	last_save_error = OK


## Idempotent après succès. En cas d'échec, PlayerData restaure lui-même les
## statistiques précédentes : rappeler cette méthode ne crée donc aucun doublon.
func persist_result() -> Error:
	if last_result_saved:
		return OK
	last_save_error = PlayerData.record_game(last_result_npc_id, last_winner,
		last_score_human, last_score_ai, last_captures_human)
	last_result_saved = last_save_error == OK
	return last_save_error
