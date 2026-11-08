## CampaignContext.gd
## État transitoire partagé par la carte, la fiche de niveau, la préparation et
## le résultat. Il possède le service de campagne et prépare une rencontre sans
## jamais écrire les decks générés dans le profil permanent.
extends Node

const ServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
const FactoryModel := preload("res://scripts/application/campaign/CampaignEncounterFactory.gd")

## Dernier nœud à recentrer sur la carte. Il n'est pas une progression : la
## vérité sauvegardée reste `CampaignProgress.last_selected`.
var focus_node_id: String = ""

var _service: CampaignService = null
var _test_service: CampaignService = null


func get_service() -> CampaignService:
	if _test_service != null:
		return _test_service
	if _service == null:
		_service = ServiceModel.create_default()
	return _service


## Les suites d'interface injectent un service sur un fichier temporaire.
func set_service_for_tests(service: CampaignService) -> void:
	_test_service = service
	focus_node_id = ""


func reset_for_tests() -> void:
	_test_service = null
	_service = null
	focus_node_id = ""


## Prépare une tentative complète de façon transactionnelle : toutes les
## générations sont validées avant l'écriture, puis le contexte est publié en
## une seule étape. Aucun loadout n'est écrit dans PlayerData.
func enter_node(node_id: String) -> Dictionary:
	var service := get_service()
	if not service.is_ready():
		return _failure(_first_problem(service))
	var node := service.node(node_id)
	if node == null:
		return _failure("Niveau de campagne inconnu.")
	if not service.is_available(node_id):
		return _failure("Ce niveau est encore verrouillé.")
	var player_deck := PlayerData.get_active_deck()
	if not DeckRules.is_deck_valid(player_deck, PlayerData.player_god_id):
		return _failure("Complétez votre deck avant de lancer une campagne.")
	var attempt := service.next_attempt_number(node_id)
	if attempt <= 0:
		return _failure("Numéro de tentative invalide.")
	var built := FactoryModel.build(node, service.graph().campaign_version,
		PlayerData.player_god_id, player_deck, attempt)
	if not bool(built.get("ok", false)):
		return _failure(str(built.get("reason", "Rencontre impossible à préparer.")))
	var prepared_session: CampaignModeSession = null
	if node.needs_series_session():
		var prepared := _prepare_mode_session(built)
		if not bool(prepared.get("ok", false)):
			return _failure(str(prepared.get("reason", "Session de campagne impossible.")))
		prepared_session = prepared.get("session") as CampaignModeSession
	var attempt_result := service.begin_attempt(node_id, node.tutorial_id)
	if not bool(attempt_result.get("ok", false)):
		return _failure("La tentative n'a pas pu être enregistrée (%s)." % error_string(
			int(attempt_result.get("error", ERR_FILE_CANT_WRITE))))
	BattleContext.enter_campaign_node(node_id, service)
	BattleContext.select_opponent(built["opponent"])
	BattleContext.forced_first_player = 0
	if prepared_session != null:
		BattleContext.install_mode_session(prepared_session)
	focus_node_id = node_id
	return {
		"ok": true,
		"reason": "",
		"node": node,
		"attempt": attempt,
		"seed": int(built["seed"]),
		"needs_preparation": node.needs_preparation(),
		"needs_series_session": node.needs_series_session(),
	}


func _prepare_mode_session(built: Dictionary) -> Dictionary:
	var opponent: Dictionary = built.get("opponent", {})
	var session := CampaignModeSession.new()
	var result := session.configure(built.get("mode_config", {}), {
		"name": PlayerData.player_name,
		"god_id": PlayerData.player_god_id,
		"deck": PlayerData.get_active_deck(),
	}, {
		"name": str(opponent.get("name", "Adversaire")),
		"god_id": str(opponent.get("god_id", "")),
		"deck": (opponent.get("deck", []) as Array).duplicate(true),
	}, int(built.get("seed", 0)))
	if not bool(result.get("ok", false)):
		return {"ok": false, "reason": str(result.get("reason", "Session invalide.")),
			"session": null}
	return {"ok": true, "reason": "", "session": session}


## Rejoue le nœud courant en repartant d'une tentative neuve.
func replay_current() -> Dictionary:
	if BattleContext.campaign_node_id == "":
		return _failure("Aucun niveau de campagne à rejouer.")
	return enter_node(BattleContext.campaign_node_id)


func active_node_id() -> String:
	return BattleContext.campaign_node_id


func _first_problem(service: CampaignService) -> String:
	var problems := service.problems()
	return problems[0] if not problems.is_empty() else "Campagne indisponible."


func _failure(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"node": null,
		"attempt": 0,
		"seed": 0,
		"needs_preparation": false,
		"needs_series_session": false,
	}
