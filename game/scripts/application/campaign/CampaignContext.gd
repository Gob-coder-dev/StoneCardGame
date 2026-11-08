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


## Prépare une tentative complète : incrémente la tentative, construit
## l'adversaire, installe le contexte de combat et démarre la session de série
## si le mode ou le format l'exige. Aucun loadout n'est écrit dans PlayerData.
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
	var attempt_result := service.begin_attempt(node_id, node.tutorial_id)
	if not bool(attempt_result.get("ok", false)):
		return _failure("La tentative n'a pas pu être enregistrée (%s)." % error_string(
			int(attempt_result.get("error", ERR_FILE_CANT_WRITE))))
	var attempt := int(attempt_result.get("attempt", 1))
	var built := FactoryModel.build(node, service.graph().campaign_version,
		PlayerData.player_god_id, player_deck, attempt)
	if not bool(built.get("ok", false)):
		return _failure(str(built.get("reason", "Rencontre impossible à préparer.")))
	BattleContext.enter_campaign_node(node_id, service)
	BattleContext.select_opponent(built["opponent"])
	BattleContext.forced_first_player = 0
	if node.needs_series_session():
		var started := BattleContext.begin_mode(built["mode_config"], int(built["seed"]))
		if not bool(started.get("ok", false)):
			BattleContext.clear_campaign_node()
			return _failure(str(started.get("reason", "Session de campagne impossible.")))
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


## Rejoue le nœud courant en repartant d'une tentative neuve.
func replay_current() -> Dictionary:
	if BattleContext.campaign_node_id == "":
		return _failure("Aucun niveau de campagne à rejouer.")
	return enter_node(BattleContext.campaign_node_id)


func active_node_id() -> String:
	return BattleContext.campaign_node_id


func active_summary(player_god_id: String = "") -> Dictionary:
	var node_id := active_node_id()
	if node_id == "":
		return {}
	return get_service().summary(node_id, player_god_id)


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
