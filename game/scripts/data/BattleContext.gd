## Passage entre les écrans d'un combat. Aucun de ces champs n'est sauvegardé.
extends Node

const ResultPersistence := preload("res://scripts/application/campaign/CampaignResultPersistence.gd")
const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const SeriesEngineModel := preload("res://scripts/domain/SeriesEngine.gd")

var selected_npc_id: String = ""
## Source du chemin de rencontres ouvert (id de dieu ou Pr.Stone). Elle permet
## de revenir au bon serpentin depuis l'avant-combat et le résultat.
var selected_source_id: String = ""
## Adversaire complet de la rencontre en cours (deck, dieu et profil d'IA).
## Les adversaires définis dans npcs.json restent accessibles : la lecture
## choisit la source qui correspond à selected_npc_id.
var selected_opponent: Dictionary = {}
var forced_first_player: int = 0
var last_winner: int = 0
var last_score_human: int = 0
var last_score_ai: int = 0
var last_captures_human: int = 0
## Taille du plateau de la dernière manche : la manche parfaite n'existe que
## sur le plateau complet, jamais sur les 3 × 3 du tutoriel.
var last_board_size: int = GameState.DEFAULT_BOARD_SIZE
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
## Nœud de campagne actif et service propriétaire de la progression. Ces deux
## champs restent transitoires : le fichier de campagne est la seule vérité.
var campaign_node_id: String = ""
var campaign_service: CampaignService = null
## Conserve les étapes déjà persistées et l'identité de la récompense lors d'un réessai.
var _result_persistence: ResultPersistence = null
var last_reward: Dictionary = {}


## Mémorise le chemin choisi avant même qu'un adversaire ne soit généré.
func select_source(source_id: String) -> void:
	selected_source_id = source_id


## Installe le nœud de campagne avant la préparation d'une rencontre. Le
## service est conservé pour appliquer la victoire depuis l'écran de résultat.
func enter_campaign_node(node_id: String, service: CampaignService) -> void:
	clear_mode_session()
	campaign_node_id = node_id
	campaign_service = service
	_result_persistence = null


func clear_campaign_node() -> void:
	campaign_node_id = ""
	campaign_service = null
	clear_mode_session()


func has_campaign_node() -> bool:
	return campaign_node_id != ""


## Une série de plusieurs manches n'est gagnée que lorsque son dernier round
## est gagné. Un FT1 sans session se termine avec le match lui-même.
func campaign_victory_confirmed() -> bool:
	if last_winner != GameState.PLAYER_HUMAN:
		return false
	if campaign_mode_session == null:
		return true
	var state := campaign_mode_session.series()
	return state != null and state.finished and state.winner == GameState.PLAYER_HUMAN


func campaign_series_pending() -> bool:
	if campaign_mode_session == null:
		return false
	var state := campaign_mode_session.series()
	return state != null and not state.finished


## État public de la série de campagne, ou {} hors série multi-manches. C'est
## la même structure que celle publiée à l'écran de résultat.
func campaign_series_state() -> Dictionary:
	if campaign_mode_session == null:
		return {}
	var state := campaign_mode_session.series()
	return SeriesEngineModel.public_state(state) if state != null else {}


## Abandon : la série est concédée à l'adversaire et le profil compte une
## défaite. Le niveau reste non terminé et la manche déjà jouée garde son
## résultat ; une nouvelle entrée repart sur une série neuve.
func abandon_campaign_series() -> Dictionary:
	if campaign_mode_session == null:
		return {"ok": false, "reason": "Aucune série de campagne active."}
	var state := campaign_mode_session.series()
	if state == null or state.finished:
		return {"ok": false, "reason": "La série est déjà terminée."}
	if not last_result_saved:
		return {"ok": false, "reason": "Le résultat de la manche n'est pas encore enregistré."}
	var error := PlayerData.record_forfeit(last_result_npc_id)
	if error != OK:
		return {"ok": false, "reason": "L'abandon n'a pas pu être enregistré."}
	return SeriesEngineModel.concede(state, GameState.PLAYER_TWO)


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


## Publie une session déjà préparée. CampaignContext utilise cette opération
## après l'écriture de la tentative afin qu'un échec de génération ou de disque
## ne laisse jamais un demi-contexte de combat visible.
func install_mode_session(session: CampaignModeSession) -> void:
	clear_mode_session()
	campaign_mode_session = session
	_sync_mode_loadouts()


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
	if completed:
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
	_result_persistence = null
	last_save_error = OK


func prepare_result(winner: int, human: int, ai: int, captures_human: int) -> void:
	last_winner = winner
	last_score_human = human
	last_score_ai = ai
	last_captures_human = captures_human
	last_result_npc_id = selected_npc_id
	last_result_saved = false
	_result_persistence = null
	last_save_error = OK
	last_reward = {}


## Le service conserve un instantané du résultat et l'avancement de ses écritures.
## Les manches suivantes ne peuvent pas modifier une récompense en cours de reprise.
func persist_result() -> Error:
	if last_result_saved:
		return OK
	if _result_persistence == null:
		_result_persistence = ResultPersistence.new(_result_snapshot(), campaign_service, campaign_node_id)
	last_save_error = _result_persistence.persist()
	last_reward = _result_persistence.reward.duplicate(true)
	last_result_saved = last_save_error == OK
	return last_save_error


func _result_snapshot() -> Dictionary:
	var mode := mode_state()
	var rules: Dictionary = mode.get("rules", {})
	var series: Dictionary = mode.get("series", {})
	return {
		"npc_id": last_result_npc_id,
		"winner": last_winner,
		"score_local": last_score_human,
		"score_opponent": last_score_ai,
		"captures": last_captures_human,
		"board_size": last_board_size,
		"mode": str(rules.get("mode", GameModeRules.MODE_CLASSIC)),
		"series": str(rules.get("series", SeriesRules.SERIES_FT1)),
		# record_round avance déjà l'index vers la prochaine manche.
		"round_index": maxi(1, int(series.get("round_index", 2)) - 1),
		"campaign_victory": campaign_victory_confirmed(),
		"opponent_god_id": effective_opponent_god_id(),
	}
