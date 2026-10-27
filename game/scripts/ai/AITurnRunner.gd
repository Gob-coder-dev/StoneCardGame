## AITurnRunner.gd
## Orchestre le tour de l'IA : prépare sa réflexion sur un état où la main
## humaine est masquée, l'avance par petites tranches à chaque image pour ne
## pas figer l'écran, attend au moins le délai de réflexion de l'IA, puis joue
## le coup via le TurnManager. Sans minuteur ni attente : fermer la scène ou
## relancer la partie abandonne simplement la réflexion en cours.
class_name AITurnRunner
extends Node

const Profile := preload("res://scripts/ai/AIProfile.gd")
const ProfileAIModel := preload("res://scripts/ai/ProfileAI.gd")
const MoveSearchModel := preload("res://scripts/ai/MoveSearch.gd")

## Temps de calcul accordé à l'IA à chaque image, en microsecondes.
const FRAME_BUDGET_USEC := 4000

var _ai: AIPlayer = null
var _turn_manager: TurnManager = null
var _search: MoveSearchModel = null
## Partie réelle pour laquelle l'IA réfléchit : un redémarrage annule le coup.
var _game: GameState = null
var _elapsed := 0.0


## Crée l'IA décrite par le champ "ai" d'un adversaire de npcs.json.
static func create_ai(profile_data: Variant) -> AIPlayer:
	return ProfileAIModel.new(Profile.new(profile_data))


func _ready() -> void:
	set_process(false)


func setup(ai: AIPlayer, turn_manager: TurnManager) -> void:
	_ai = ai
	_turn_manager = turn_manager


## Déclenche le tour de l'IA (appelé par le contrôleur quand c'est à l'IA).
func run_turn() -> void:
	cancel()
	if _ai == null or _turn_manager == null or _turn_manager.get_state() == null:
		return
	_game = _turn_manager.get_state()
	## L'IA raisonne sur un état où elle ne voit pas la main du joueur humain.
	_search = _ai.start_search(_turn_manager.get_state_for_ai())
	_elapsed = 0.0
	set_process(_search != null)


## Abandonne la réflexion en cours sans jouer.
func cancel() -> void:
	_search = null
	_game = null
	set_process(false)


func is_thinking() -> bool:
	return _search != null


func _process(delta: float) -> void:
	if _search == null or not _is_ai_turn_of_watched_game():
		cancel()
		return
	_elapsed += delta
	var finished := _search.step(FRAME_BUDGET_USEC)
	if not finished or _elapsed < _ai.think_delay:
		return
	var move := _search.chosen_move()
	cancel()
	if move.is_empty():
		push_error("AITurnRunner: aucun coup valide trouvé pour l'IA.")
	elif not _turn_manager.ai_play(move["row"], move["col"], move["stone_id"]):
		push_error("AITurnRunner: coup refusé %s." % str(move))


func _is_ai_turn_of_watched_game() -> bool:
	if not is_instance_valid(_turn_manager):
		return false
	var state := _turn_manager.get_state()
	return state != null and state == _game and not state.is_game_over \
		and state.current_player == GameState.PLAYER_AI


func _exit_tree() -> void:
	cancel()
