## AITurnRunner.gd
## Orchestre le tour de l'IA : attend un délai (confort), demande un coup à
## l'IA sur un état où la main humaine est masquée, puis joue ce coup via le
## TurnManager. Sépare toute la mécanique "tour IA" du contrôleur d'écran.
class_name AITurnRunner
extends Node

var _ai: AIPlayer = null
var _turn_manager: TurnManager = null
var _timer: Timer = null


## Crée l'IA d'un niveau de npcs.json (voir AIPlayer.LEVELS). Un niveau inconnu,
## déjà signalé au chargement par ContentValidator, retombe sur RandomAI.
static func create_ai(level: String) -> AIPlayer:
	match level:
		"random": return RandomAI.new()
		"greedy": return GreedyAI.new()
		"score": return ScoreAI.new()
	push_warning("AITurnRunner: niveau IA inconnu '%s', RandomAI utilisée." % level)
	return RandomAI.new()


func setup(ai: AIPlayer, turn_manager: TurnManager) -> void:
	_ai = ai
	_turn_manager = turn_manager
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)


## Déclenche le tour de l'IA (appelé par le contrôleur quand c'est à l'IA).
func run_turn() -> void:
	if _ai == null or _turn_manager == null:
		return
	_timer.wait_time = _ai.think_delay
	_timer.start()


func _on_timer_timeout() -> void:
	## L'IA raisonne sur un état où elle ne voit pas la main du joueur humain.
	var state := _turn_manager.get_state_for_ai()
	var move := _ai.choose_move(state)
	if move.is_empty():
		push_error("AITurnRunner: aucun coup valide trouvé pour l'IA.")
		return
	_turn_manager.ai_play(move["row"], move["col"], move["stone_id"])
