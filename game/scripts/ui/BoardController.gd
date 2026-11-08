## BoardController.gd
## Coordinateur de l'écran de jeu. Ne dessine rien lui-même : il relie les
## briques entre elles.
##   - MatchDriver   : campagne (bot) ou PVP local (commandes réseau validées)
##   - TurnManager   : logique de jeu (émet les signaux)
##   - BoardView     : affichage du plateau
##   - HandView      : affichage de la main
##
## Rôle : écouter les signaux du TurnManager, dire aux vues de se rafraîchir,
## transmettre les gestes du joueur, enchaîner vers l'écran suivant.
extends Control

const CombatResolverModel := preload("res://scripts/engine/CombatResolver.gd")
const CardDragController := preload("res://scripts/ui/CardDragController.gd")
const CampaignDriver := preload("res://scripts/ui/match/CampaignMatchDriver.gd")
const LanDriver := preload("res://scripts/ui/match/LanMatchDriver.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")
const BattleLayoutModel := preload("res://scripts/ui/BattleLayout.gd")

@onready var root: VBoxContainer = $Root
@onready var turn_manager: TurnManager = $TurnManager
@onready var board_area: Control = $Root/BoardArea
@onready var board_view: BoardView = $Root/BoardArea/BoardView
@onready var hand_label: Label = $Root/HandLabel
@onready var hand_view: HandView = $Root/HandView
@onready var hud: BattleHUD = $Root/HUD
@onready var background: MenuBackground = $Background

var _driver: MatchDriver = null
var _selected_stone_id: String = ""
var _local_captures: int = 0
var _card_drag: CardDragController = null  ## couche du glisser-déposer
var _leaving := false
## Un match PVP terminé passe la main à l'écran de résultat, qui garde la
## session ouverte pour proposer une revanche.
var _finished_pvp := false


func _ready() -> void:
	_connect_signals()
	_driver = (LanDriver.new() if PvpMatchContext.is_active() else CampaignDriver.new()) as MatchDriver
	add_child(_driver)
	_driver.setup(turn_manager)
	_driver.aborted.connect(_on_match_aborted)
	_driver.finished.connect(_on_match_finished)
	_driver.interaction_changed.connect(_update_interaction)
	if not _driver.start():
		_on_start_failed()
		return
	_apply_match_identity()
	## Le layout doit être stabilisé avant la construction des cases. Sinon la
	## zone extensible prend toute la hauteur d'un téléphone 20:9 et crée un vide
	## entre le plateau carré et la main.
	_initialize_view.call_deferred()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _initialize_view() -> void:
	_apply_responsive_layout()
	board_view.build()
	_refresh_after_build()


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout.call_deferred()


func _apply_responsive_layout() -> void:
	if root.size.x <= 0.0 or root.size.y <= 0.0:
		return
	var fixed_height := hud.get_combined_minimum_size().y \
		+ hand_label.get_combined_minimum_size().y
	var layout := BattleLayoutModel.calculate(root.size, fixed_height,
		float(root.get_theme_constant("separation")), float(UITheme.GAP_MEDIUM),
		DeckRules.DECK_SIZE)
	var board_side := float(layout["board_side"])
	board_area.custom_minimum_size.y = board_side
	board_area.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hand_view.configure(int(layout["hand_columns"]), float(layout["hand_card_size"]))
	# Le VBox applique les nouvelles tailles à la frame suivante. Le plateau ne
	# recalcule alors que sa géométrie visuelle, jamais son état de jeu.
	board_view.update_geometry.call_deferred()


func _refresh_after_build() -> void:
	var state := turn_manager.get_state()
	if state == null:
		return
	board_view.refresh(state)
	hand_view.refresh(state.hand_of(_driver.local_side))
	_update_interaction()


func _apply_match_identity() -> void:
	background.set_gods(_driver.local_god, _driver.opponent_god)
	hud.set_names(_driver.local_name, _driver.opponent_name)
	hud.set_gods(_driver.local_god, _driver.opponent_god)
	hud.set_scores(0, 0)
	## Les cases colorées suivent le camp du joueur local sur chaque appareil.
	board_view.local_owner = _driver.local_side


func _on_start_failed() -> void:
	if PvpMatchContext.is_active():
		PvpMatchContext.clear()
		LanSession.leave_with_notice("Impossible de démarrer la partie PVP.")
		call_deferred("_return_to_pvp_lobby")
	else:
		call_deferred("_return_to_cards")


func _return_to_cards() -> void:
	Routes.go(get_tree(), Routes.COLLECTION)


func _return_to_pvp_lobby() -> void:
	Routes.go(get_tree(), Routes.PVP_LOBBY)


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
	## Glisser une carte de la main : la couche est ajoutée en dernier pour
	## que la copie de la carte passe au-dessus du plateau et de la main.
	_card_drag = CardDragController.new()
	_card_drag.name = "CardDrag"
	add_child(_card_drag)
	_card_drag.setup(board_view, _can_drop)
	hand_view.card_press_started.connect(_on_card_press_started)
	_card_drag.drag_started.connect(_on_card_drag_started)
	_card_drag.drop_requested.connect(_on_card_dropped)


## ─── Gestes du joueur ─────────────────────────────────────────────────────────

func _on_card_selected(stone_id: String) -> void:
	if _driver == null or not _driver.can_submit():
		return
	_selected_stone_id = stone_id
	hand_view.set_selected(stone_id)


func _on_cell_pressed(row: int, col: int) -> void:
	if _selected_stone_id == "":
		return
	if _driver.request_move(row, col, _selected_stone_id):
		_selected_stone_id = ""
		hand_view.clear_selection()


## Le glissement n'est suivi que lorsque le joueur peut réellement jouer.
func _on_card_press_started(stone_id: String, card: StoneCard, pointer: int, canvas_position: Vector2) -> void:
	if _human_can_play():
		_card_drag.begin(stone_id, card, pointer, canvas_position)


## Une carte glissée n'est pas sélectionnée : une sélection précédente est retirée.
func _on_card_drag_started(_stone_id: String) -> void:
	_selected_stone_id = ""
	hand_view.clear_selection()


func _on_card_dropped(stone_id: String, row: int, col: int) -> void:
	_driver.request_move(row, col, stone_id)


## Mêmes règles que pour un appui : PlacementRules décide, au tour du joueur.
func _can_drop(stone_id: String, row: int, col: int) -> bool:
	return _human_can_play() \
		and PlacementRules.is_valid(turn_manager.get_state(), row, col, stone_id, _driver.local_side)


func _human_can_play() -> bool:
	return _driver != null and _driver.can_submit()


## Seul le camp local peut toucher le plateau, et seulement quand le driver
## autorise réellement un coup (en PVP : après confirmation de l'hôte).
func _update_interaction() -> void:
	if _driver == null:
		return
	var state := turn_manager.get_state()
	if state == null or state.is_game_over:
		board_view.set_input_enabled(false)
		return
	board_view.set_input_enabled(state.current_player == _driver.local_side \
		and _driver.can_submit())


## ─── Réactions aux signaux du TurnManager ────────────────────────────────────

func _on_turn_started(player: int) -> void:
	var state := turn_manager.get_state()
	board_view.refresh(state)
	## Le plateau n'est construit qu'à la première frame : il n'y a encore
	## aucun lien d'Essaim à dessiner avant le premier coup.
	if board_view.animations != null:
		board_view.animations.set_swarm_links(CombatResolverModel.swarm_links(state))
	hand_view.refresh(state.hand_of(_driver.local_side))
	## Surligne la plaque du joueur actif : la plaque de gauche est toujours le
	## joueur local, même lorsque le camp réseau est PLAYER_TWO.
	hud.set_active_player(GameState.PLAYER_HUMAN if player == _driver.local_side else GameState.PLAYER_AI)

	## Le PVP n'ouvre son tour qu'après la confirmation de l'hôte : l'écoute de
	## `interaction_changed` réactive les cases à ce moment-là.
	_update_interaction()
	_driver.on_turn_started(player)


func _on_stone_placed(row: int, col: int, _stone_id: String, _owner: int) -> void:
	var state := turn_manager.get_state()
	board_view.refresh(state)
	hand_view.refresh(state.hand_of(_driver.local_side))
	board_view.set_input_enabled(false)


func _on_stone_captured(row: int, col: int, new_owner: int) -> void:
	if new_owner == _driver.local_side:
		_local_captures += 1
	board_view.animations.animate_capture(row, col, new_owner)


func _on_turn_ended(score_human: int, score_ai: int) -> void:
	## Le HUD affiche toujours le local à gauche.
	var local_score := score_human if _driver.local_side == GameState.PLAYER_ONE else score_ai
	var remote_score := score_ai if _driver.local_side == GameState.PLAYER_ONE else score_human
	hud.set_scores(local_score, remote_score)
	_driver.on_turn_ended()


func _on_game_over(winner: int, score_human: int, score_ai: int) -> void:
	hud.set_game_over()
	if _driver.records_campaign_stats:
		BattleContext.prepare_result(winner, score_human, score_ai, _local_captures)
		# La série doit connaître la manche avant l'enregistrement : un FT2 n'est
		# gagné qu'après la dernière manche, pas après le premier match.
		if BattleContext.has_mode_session():
			BattleContext.record_mode_round(winner, score_human, score_ai)
		BattleContext.persist_result()
		await get_tree().create_timer(1.5).timeout
		Routes.go(get_tree(), Routes.CAMPAIGN_RESULT)
		return
	_driver.on_game_over(winner, score_human, score_ai)


func _on_invalid_move(_reason: String) -> void:
	## Coup refusé : rien à afficher (le joueur peut simplement réessayer).
	pass


## Relais unique de présentation ; les annonces métier ne déclenchent aucun dessin.
func _on_presentation_requested(step: CombatPresentation) -> void:
	if step.kind == CombatPresentation.Kind.EFFECTS:
		board_view.refresh(turn_manager.get_state())
	board_view.animations.present(step)


## ─── Fin de match PVP local ──────────────────────────────────────────────────

func _on_match_finished(winner: int, score_one: int, score_two: int) -> void:
	if _leaving:
		return
	_leaving = true
	PvpMatchContext.record_result(winner, score_one, score_two)
	await get_tree().create_timer(1.5).timeout
	## Le verdict, le score et la revanche appartiennent à l'écran de résultat :
	## la session réseau reste ouverte jusqu'à ce qu'il soit quitté.
	_finished_pvp = true
	Routes.go(get_tree(), Routes.PVP_RESULT)


func _on_match_aborted(message: String) -> void:
	if _leaving:
		return
	_leaving = true
	PvpMatchContext.clear()
	LanSession.leave_with_notice(message)
	Routes.go(get_tree(), Routes.PVP_LOBBY)


func _exit_tree() -> void:
	if _driver != null:
		_driver.shutdown()
	if _finished_pvp:
		return
	if PvpMatchContext.is_active():
		## Quitter le plateau ferme toujours la session réseau, même si la scène
		## est libérée avant la fin du match.
		PvpMatchContext.clear()
		LanSession.reset()
