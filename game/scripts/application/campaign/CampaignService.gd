## CampaignService.gd
## Façade applicative de la carte unifiée. Elle fournit les états
## verrouillé/accessible/terminé, mémorise la sélection, prépare une tentative et
## persiste une victoire de façon idempotente. Elle ne dessine rien et ne
## contient aucune règle de combat.
class_name CampaignService
extends RefCounted

const ContentLoaderModel := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const StoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const UnlockRulesModel := preload("res://scripts/domain/campaign/CampaignUnlockRules.gd")
const ValidatorModel := preload("res://scripts/domain/campaign/CampaignValidator.gd")
const MigrationModel := preload("res://scripts/application/campaign/CampaignSaveMigration.gd")
const FactoryModel := preload("res://scripts/application/campaign/CampaignEncounterFactory.gd")
const PositionStateModel := preload("res://scripts/application/campaign/CampaignMapPositionState.gd")

var _graph: CampaignGraph = null
var _progress: CampaignProgress = null
var _store: CampaignProgressStore = null
var _problems: Array[String] = []
var _load_error: Error = OK

const NAVIGATION_OFFSET_WRITE_THRESHOLD: float = 4.0


func _init(graph: CampaignGraph = null, progress: CampaignProgress = null,
		store: CampaignProgressStore = null,
		problems: Array[String] = []) -> void:
	_graph = graph if graph != null else GraphModel.build({})
	_progress = progress if progress != null else ProgressModel.from_dict({})
	_store = store if store != null else StoreModel.new()
	_problems = problems.duplicate()


## Chargement de production : contenu, validation puis progression et migration.
## Une campagne invalide reste inutilisable mais expose ses diagnostics au lieu
## d'ouvrir une carte partielle.
static func create_default(store_path: String = StoreModel.DEFAULT_PATH,
		legacy_stats: Dictionary = {}) -> CampaignService:
	var content := ContentLoaderModel.read()
	var definition: Dictionary = content.get("definition", {})
	var graph: CampaignGraph = GraphModel.build(definition)
	var problems: Array[String] = []
	for problem in content.get("problems", []):
		problems.append(str(problem))
	var service := CampaignService.new(graph, ProgressModel.from_dict({}),
		StoreModel.new(store_path), problems)
	if problems.is_empty():
		service._load_progress(legacy_stats)
	return service


func _load_progress(legacy_stats: Dictionary) -> void:
	_progress = _store.load_progress()
	if _progress.campaign_version == 0:
		_progress.campaign_version = _graph.campaign_version
	var stats := legacy_stats
	if stats.is_empty():
		stats = PlayerData.stats
	var migrated := MigrationModel.migrate(_graph, stats, _progress)
	if bool(migrated.get("changed", false)):
		_load_error = _store.save(_progress)
		if _load_error != OK:
			_problems.append("Progression de campagne non enregistrée (%s)." % error_string(_load_error))


func is_ready() -> bool:
	return _problems.is_empty() and _load_error == OK


func problems() -> Array[String]:
	return _problems.duplicate()


func load_error() -> Error:
	return _load_error


func graph() -> CampaignGraph:
	return _graph


func progress() -> CampaignProgress:
	return _progress


func store() -> CampaignProgressStore:
	return _store


func has_node(node_id: String) -> bool:
	return _graph.has_node(node_id)


func node(node_id: String) -> CampaignNode:
	return _graph.node(node_id)


func states() -> Dictionary:
	return UnlockRulesModel.states(_graph, _progress.completed)


func state_for(node_id: String) -> int:
	return UnlockRulesModel.state_for(_graph, node_id, _progress.completed)


func is_completed(node_id: String) -> bool:
	return _progress.is_completed(node_id)


func is_available(node_id: String) -> bool:
	return UnlockRulesModel.is_available(_graph, node_id, _progress.completed)


func focus_node_id() -> String:
	return UnlockRulesModel.focus_node_id(_graph, _progress.completed,
		_progress.last_selected)


## Ancre de secours si l'ancienne position référence un nœud supprimé : dernier
## niveau consulté, puis niveau terminé le plus avancé dans l'ordre du contenu.
func navigation_fallback_node_id() -> String:
	if _graph.has_node(_progress.last_selected):
		return _progress.last_selected
	var last_completed := ""
	for node_id in _graph.node_ids():
		if _progress.is_completed(node_id):
			last_completed = node_id
	if last_completed != "":
		return last_completed
	var focus := focus_node_id()
	if _graph.has_node(focus):
		return focus
	return _graph.start_node_id


func has_map_navigation() -> bool:
	return not PositionStateModel.from_dict(_progress.map_navigation).is_empty()


## Position de navigation résolue avec les mêmes règles de repli que la carte.
## Une vieille sauvegarde sans champ `map_navigation` pointe sur le départ.
func map_navigation_state():
	if not has_map_navigation():
		return PositionStateModel.make(_graph.start_node_id, 0.0, 0.0)
	return PositionStateModel.from_dict(_progress.map_navigation).resolved(
		_graph, navigation_fallback_node_id())


## Sauvegarde uniquement la navigation ; la progression et la sélection sont
## recopiées telles quelles. Le debounce de l'appelant est complété par un seuil
## logique afin qu'un mouvement imperceptible ne réécrive pas tout le fichier.
func save_map_navigation(anchor_node_id: String, offset_y: float,
		scroll_vertical: float) -> Error:
	if not _graph.has_node(anchor_node_id):
		return ERR_DOES_NOT_EXIST
	var state = PositionStateModel.make(anchor_node_id, offset_y, scroll_vertical)
	var serialized: Dictionary = state.to_dict()
	var previous = PositionStateModel.from_dict(_progress.map_navigation)
	if previous.anchor_node_id == state.anchor_node_id \
			and absf(previous.offset_y - state.offset_y) < NAVIGATION_OFFSET_WRITE_THRESHOLD:
		return OK
	var copy := _progress.duplicate_progress()
	copy.set_map_navigation(serialized)
	var error := _store.save(copy)
	if error != OK:
		return error
	_progress = copy
	return OK


func encounter_for(node_id: String, player_god_id: String, player_deck: Array,
		attempt: int) -> Dictionary:
	return FactoryModel.build(_graph.node(node_id), _graph.campaign_version,
		player_god_id, player_deck, attempt)


## Mémorise le dernier nœud consulté. L'écriture précède la mise à jour mémoire :
## un échec disque n'altère pas la progression affichée.
func select_node(node_id: String) -> Error:
	if not has_node(node_id):
		return ERR_DOES_NOT_EXIST
	if _progress.last_selected == node_id:
		return OK
	var copy := _progress.duplicate_progress()
	copy.set_last_selected(node_id)
	var error := _store.save(copy)
	if error != OK:
		return error
	_progress = copy
	return OK


## Ouvre une tentative. Le numéro sert seulement aux graines per_attempt ; il
## est enregistré avec le dernier nœud consulté et l'état de tutoriel.
func begin_attempt(node_id: String, tutorial_id: String = "",
		tutorial_state: String = "seen") -> Dictionary:
	if not has_node(node_id):
		return {"ok": false, "error": ERR_DOES_NOT_EXIST, "attempt": 0}
	var copy := _progress.duplicate_progress()
	copy.set_last_selected(node_id)
	copy.campaign_version = _graph.campaign_version
	if tutorial_id != "":
		copy.set_tutorial_state(tutorial_id, tutorial_state)
	var attempt := copy.record_attempt(node_id)
	var error := _store.save(copy)
	if error != OK:
		return {"ok": false, "error": error, "attempt": 0}
	_progress = copy
	return {"ok": true, "error": OK, "attempt": attempt}


## Numéro candidat sans mutation. La rencontre peut ainsi valider toutes ses
## générations avant que begin_attempt() ne publie la tentative sur disque.
func next_attempt_number(node_id: String) -> int:
	if not has_node(node_id):
		return 0
	return _progress.attempts_for(node_id) + 1


## Applied once. La copie n'est publiée qu'après réussite de l'écriture : la
## carte ne peut pas débloquer une suite qui n'existe pas sur le disque.
func complete_node(node_id: String) -> Error:
	if not has_node(node_id):
		return ERR_DOES_NOT_EXIST
	if _progress.is_completed(node_id):
		return OK
	var copy := _progress.duplicate_progress()
	copy.campaign_version = _graph.campaign_version
	copy.mark_completed(node_id)
	var error := _store.save(copy)
	if error != OK:
		return error
	_progress = copy
	return OK


func mark_tutorial_state(tutorial_id: String, state: String) -> Error:
	if tutorial_id == "" or _progress.tutorial_state(tutorial_id) == state:
		return OK
	var copy := _progress.duplicate_progress()
	copy.set_tutorial_state(tutorial_id, state)
	var error := _store.save(copy)
	if error != OK:
		return error
	_progress = copy
	return OK


func story_state(key: String) -> bool:
	return _progress.story_state(key)


## Même transaction que la progression : l'état n'est publié qu'après l'écriture.
func mark_story_state(key: String, value: bool = true) -> Error:
	if key == "":
		return ERR_INVALID_PARAMETER
	if _progress.story_state(key) == value:
		return OK
	var copy := _progress.duplicate_progress()
	copy.set_story_state(key, value)
	var error := _store.save(copy)
	if error != OK:
		return error
	_progress = copy
	return OK
