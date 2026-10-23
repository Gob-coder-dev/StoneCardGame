## BoardController.gd
## Coordinateur de l'écran de jeu. Ne dessine rien lui-même : il relie les
## briques entre elles.
##   - TurnManager   : logique de jeu (émet les signaux)
##   - BoardView     : affichage du plateau
##   - HandView      : affichage de la main
##   - AITurnRunner  : tour de l'IA
##
## Rôle : écouter les signaux du TurnManager, dire aux vues de se rafraîchir,
## transmettre les gestes du joueur, enchaîner vers l'écran de résultat.
extends Control

const CombatResolverModel := preload("res://scripts/engine/CombatResolver.gd")

@onready var turn_manager: TurnManager = $TurnManager
@onready var board_view: BoardView = $Root/BoardArea/BoardView
@onready var hand_view: HandView = $Root/HandView
@onready var hud: BattleHUD = $Root/HUD

var _ai_runner: AITurnRunner = null
var _npc_data: Dictionary = {}
var _selected_stone_id: String = ""
var _human_captures: int = 0


func _ready() -> void:
	_connect_signals()
	## Construire le plateau une fois la taille connue (point 7).
	board_view.build.call_deferred()
	if DeckRules.is_deck_valid(PlayerData.player_deck, PlayerData.player_god_id) and BattleContext.selected_npc_id != "":
		call_deferred("_start_battle", PlayerData.player_deck, BattleContext.selected_npc_id)
	else:
		call_deferred("_return_to_cards")


func _return_to_cards() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/CollectionScreen.tscn")


func _connect_signals() -> void:
	board_view.cell_pressed.connect(_on_cell_pressed)
	hand_view.card_selected.connect(_on_card_selected)
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.stone_placed.connect(_on_stone_placed)
	turn_manager.stone_captured.connect(_on_stone_captured)
	turn_manager.turn_ended.connect(_on_turn_ended)
	turn_manager.game_over.connect(_on_game_over)
	turn_manager.invalid_move.connect(_on_invalid_move)
	turn_manager.presentation_requested.connect(_on_presentation_requested)


func _start_battle(human_deck: Array, npc_id: String) -> void:
	_npc_data = StoneLoader.get_npc(npc_id)
	if _npc_data.is_empty():
		push_error("BoardController: NPC '%s' introuvable." % npc_id)
		return

	board_view.build()  ## garantit la construction si pas encore faite

	var human_hand := StoneLoader.build_hand(human_deck)
	var ai_hand := StoneLoader.build_hand(_npc_data["deck"])

	## Préparer l'IA et son runner.
	var ai := AITurnRunner.create_ai(str(_npc_data.get("ai_level", "")))
	_ai_runner = AITurnRunner.new()
	add_child(_ai_runner)
	_ai_runner.setup(ai, turn_manager)

	## Renseigner les noms du HUD une fois pour toutes.
	var human_god := StoneLoader.get_god(PlayerData.player_god_id)
	var ai_god := StoneLoader.get_god(str(_npc_data.get("god_id", "")))
	hud.set_names(
		"%s • %s" % [PlayerData.player_name, human_god.get("name", "")],
		"%s • %s" % [_npc_data.get("name", "Adversaire"), ai_god.get("name", "")]
	)
	hud.set_scores(0, 0)

	var blocked := BoardSetupGenerator.generate()
	turn_manager.start_game(
		human_hand, ai_hand, blocked, npc_id, BattleContext.forced_first_player,
		PlayerData.player_god_id, str(_npc_data.get("god_id", ""))
	)


## ─── Gestes du joueur ─────────────────────────────────────────────────────────

func _on_card_selected(stone_id: String) -> void:
	if turn_manager.get_state().current_player != GameState.PLAYER_HUMAN:
		return
	_selected_stone_id = stone_id
	hand_view.set_selected(stone_id)


func _on_cell_pressed(row: int, col: int) -> void:
	if _selected_stone_id == "":
		return
	if turn_manager.human_play(row, col, _selected_stone_id):
		_selected_stone_id = ""
		hand_view.clear_selection()


## ─── Réactions aux signaux du TurnManager ────────────────────────────────────

func _on_turn_started(player: int) -> void:
	var state := turn_manager.get_state()
	board_view.refresh(state)
	board_view.animations.set_swarm_links(CombatResolverModel.swarm_links(state))
	hand_view.refresh(state.human_hand)
	## Surligne la plaque du joueur actif (indicateur de tour visuel).
	hud.set_active_player(player)

	if player == GameState.PLAYER_HUMAN:
		board_view.set_input_enabled(true)
	else:
		board_view.set_input_enabled(false)
		_ai_runner.run_turn()


func _on_stone_placed(row: int, col: int, _stone_id: String, _owner: int) -> void:
	var state := turn_manager.get_state()
	board_view.refresh(state)
	hand_view.refresh(state.human_hand)
	board_view.set_input_enabled(false)


func _on_stone_captured(row: int, col: int, new_owner: int) -> void:
	if new_owner == GameState.PLAYER_HUMAN:
		_human_captures += 1
	board_view.animations.animate_capture(row, col, new_owner)


func _on_turn_ended(score_human: int, score_ai: int) -> void:
	hud.set_scores(score_human, score_ai)


func _on_game_over(winner: int, score_human: int, score_ai: int) -> void:
	hud.set_game_over()
	BattleContext.record_result(winner, score_human, score_ai)
	PlayerData.record_game(BattleContext.selected_npc_id, winner, score_human, score_ai, _human_captures)
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file("res://scenes/menus/Result.tscn")


func _on_invalid_move(_reason: String) -> void:
	## Coup refusé : rien à afficher (le joueur peut simplement réessayer).
	pass


## Relais unique de présentation ; les annonces métier ne déclenchent aucun dessin.
func _on_presentation_requested(step: CombatPresentation) -> void:
	if step.kind == CombatPresentation.Kind.EFFECTS:
		board_view.refresh(turn_manager.get_state())
	board_view.animations.present(step)
