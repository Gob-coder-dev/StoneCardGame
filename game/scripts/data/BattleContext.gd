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
## Préparation optionnelle d'un mode de campagne. Les loadouts restent
## transitoires et ne modifient jamais le profil permanent du joueur.
var campaign_mode_session: CampaignModeSession = null
var player_loadout: GameLoadout = null
var opponent_loadout: GameLoadout = null


## Mémorise le chemin choisi avant même qu'un adversaire ne soit généré.
func select_source(source_id: String) -> void:
	selected_source_id = source_id


## Mémorise la rencontre et son identifiant de statistiques en une seule fois.
func select_opponent(opponent: Dictionary) -> void:
	clear_mode_session()
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


## Configure les modes partagés pour la rencontre sélectionnée. Le mode
## Classique est lui aussi représenté par des loadouts temporaires afin que le
## combat ne dépende plus directement de PlayerData une fois lancé.
func begin_mode(config: Dictionary, seed: int = 0) -> Dictionary:
	clear_mode_session()
	var opponent := current_opponent()
	if opponent.is_empty():
		return {"ok": false, "reason": "Adversaire de campagne absent."}
	var actual_seed := seed if seed != 0 else int(Time.get_unix_time_from_system() * 1000.0)
	campaign_mode_session = CampaignModeSession.new()
	var result := campaign_mode_session.configure(config, {
		"name": PlayerData.player_name,
		"god_id": PlayerData.player_god_id,
		"deck": PlayerData.get_active_deck(),
	}, {
		"name": str(opponent.get("name", "Adversaire")),
		"god_id": str(opponent.get("god_id", "")),
		"deck": (opponent.get("deck", []) as Array).duplicate(true),
	}, actual_seed)
	_sync_mode_loadouts()
	return result


func choose_draft_card(stone_id: String) -> bool:
	if campaign_mode_session == null:
		return false
	var accepted := campaign_mode_session.choose_player(stone_id)
	_sync_mode_loadouts()
	return accepted


func advance_mode_preparation(delta: float) -> bool:
	if campaign_mode_session == null:
		return false
	var completed := campaign_mode_session.advance(delta)
	_sync_mode_loadouts()
	return completed


func confirm_mode_preparation() -> bool:
	if campaign_mode_session == null or not campaign_mode_session.confirm_local():
		return false
	_sync_mode_loadouts()
	return has_prepared_loadouts()


func record_mode_round(winner: int, score_human: int, score_ai: int) -> Dictionary:
	if campaign_mode_session == null:
		return {"ok": false, "reason": "Série de campagne absente."}
	return campaign_mode_session.record_round(winner, score_human, score_ai)


func prepare_next_mode_round() -> Dictionary:
	if campaign_mode_session == null:
		return {"ok": false, "reason": "Série de campagne absente."}
	var result := campaign_mode_session.prepare_round()
	_sync_mode_loadouts()
	forced_first_player = 0
	return result


func has_mode_session() -> bool:
	return campaign_mode_session != null


func has_prepared_loadouts() -> bool:
	return player_loadout != null and opponent_loadout != null \
		and player_loadout.is_valid() and opponent_loadout.is_valid()


func mode_state() -> Dictionary:
	return campaign_mode_session.public_state() if campaign_mode_session != null else {}


func effective_player_god_id() -> String:
	return player_loadout.god_id if player_loadout != null else PlayerData.player_god_id


func effective_player_deck() -> Array:
	return player_loadout.deck.duplicate() if player_loadout != null \
		else PlayerData.get_active_deck()


func effective_opponent_god_id() -> String:
	if opponent_loadout != null:
		return opponent_loadout.god_id
	return str(current_opponent().get("god_id", ""))


func effective_opponent_deck() -> Array:
	if opponent_loadout != null:
		return opponent_loadout.deck.duplicate()
	return (current_opponent().get("deck", []) as Array).duplicate(true)


func clear_mode_session() -> void:
	campaign_mode_session = null
	player_loadout = null
	opponent_loadout = null


func _sync_mode_loadouts() -> void:
	if campaign_mode_session == null:
		player_loadout = null
		opponent_loadout = null
		return
	player_loadout = campaign_mode_session.loadout_one()
	opponent_loadout = campaign_mode_session.loadout_two()


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
