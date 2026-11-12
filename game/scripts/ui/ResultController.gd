## ResultController.gd
## Écran de résultat après une partie. En campagne, la victoire propose les
## niveaux suivants sous forme de cartes qui déposent le joueur sur la carte
## avec la fiche du niveau ouverte ; une série non terminée propose la manche
## suivante. Les adversaires historiques conservent les cinq sorties d'origine.
extends Control

const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const EncounterPathModel := preload("res://scripts/domain/EncounterPath.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")
const EncounterPresenter := preload("res://scripts/ui/campaign/CampaignEncounterPresenter.gd")
const TouchButtonModel := preload("res://scripts/ui/input/TouchButton.gd")

## Deux cartes par ligne sur le canevas 1080. Si un nom de niveau dépasse cette
## longueur, les noms sont retirés partout plutôt que tronqués inégalement.
const NEXT_LEVEL_CARD_WIDTH := 420.0
const NEXT_LEVEL_CARD_HEIGHT := 128.0
const NEXT_LEVEL_NAME_MAX_CHARS := 24
const NEXT_LEVELS_PER_ROW := 2
## Le bloc forme sa propre carte pour se détacher de la récompense ; les cartes
## de niveau gardent un contour épais pour rester lisibles sur fond sombre.
const NEXT_LEVELS_GOLD := Color(1, 0.82, 0.48)
const NEXT_LEVELS_BG := Color(0.075, 0.062, 0.086, 0.94)
const NEXT_LEVEL_BORDER_WIDTH := 5

@onready var result_label: Label = $VBoxCenter/ResultCard/Content/ResultLabel
@onready var score_label: Label = $VBoxCenter/ResultCard/Content/ScoreLabel
@onready var reward_divider: ColorRect = $VBoxCenter/ResultCard/Content/RewardDivider
@onready var rewards: VBoxContainer = $VBoxCenter/ResultCard/Content/Rewards
@onready var reward_soul_row: HBoxContainer = $VBoxCenter/ResultCard/Content/Rewards/SoulRow
@onready var reward_soul_amount: Label = $VBoxCenter/ResultCard/Content/Rewards/SoulRow/Amount
@onready var reward_candle_row: HBoxContainer = $VBoxCenter/ResultCard/Content/Rewards/CandleRow
@onready var reward_candle_amount: Label = $VBoxCenter/ResultCard/Content/Rewards/CandleRow/Amount
@onready var reward_cards: HBoxContainer = $VBoxCenter/ResultCard/Content/Rewards/Cards
@onready var background: MenuBackground = $Background
@onready var next_btn: Button = $VBoxCenter/NextButton
@onready var replay_btn: Button = $VBoxCenter/ReplayButton
@onready var level_btn: Button = $VBoxCenter/LevelsButton
@onready var gods_btn: Button = $VBoxCenter/GodsButton
@onready var menu_btn: Button = $VBoxCenter/MainMenuButton
@onready var save_status: Label = $VBoxCenter/SaveStatus
@onready var retry_save_btn: Button = $VBoxCenter/RetrySaveButton
@onready var next_levels: PanelContainer = $VBoxCenter/NextLevels
@onready var next_levels_title: Label = $VBoxCenter/NextLevels/Column/Title
@onready var next_levels_rows: VBoxContainer = $VBoxCenter/NextLevels/Column/Rows

## Navigation injectable : les tests vérifient la destination réelle sans
## changer de scène. Vide en jeu, la scène est alors ouverte normalement.
var scene_changer: Callable = Callable()

var _campaign := false


func _ready() -> void:
	next_btn.pressed.connect(_on_next_level)
	replay_btn.pressed.connect(_on_replay)
	level_btn.pressed.connect(_on_level_select)
	gods_btn.pressed.connect(_on_god_select)
	menu_btn.pressed.connect(_on_menu)
	retry_save_btn.pressed.connect(_on_retry_save)

	_campaign = BattleContext.has_campaign_node()
	match BattleContext.last_winner:
		GameState.PLAYER_HUMAN:
			result_label.text = "VICTOIRE !"
		GameState.PLAYER_AI:
			result_label.text = "DÉFAITE..."
		_:
			result_label.text = "ÉGALITÉ"
	_play_result_sound()

	var npc := BattleContext.current_opponent()
	if BattleContext.last_winner == GameState.PLAYER_HUMAN:
		background.set_result_victory(StoneLoader.get_god(BattleContext.effective_player_god_id()))
	elif BattleContext.last_winner == GameState.PLAYER_AI:
		background.set_result_defeat(StoneLoader.get_god(BattleContext.effective_opponent_god_id()))
	else:
		background.set_result_draw(StoneLoader.get_god(BattleContext.effective_player_god_id()),
			StoneLoader.get_god(BattleContext.effective_opponent_god_id()))
	var npc_name := UIFormat.combatant_name(str(
		npc.get("combatant_name", npc.get("name", "Adversaire"))), 18)
	var player_name := UIFormat.combatant_name(PlayerData.player_name, 18)
	score_label.text = "%s %d  —  %d %s" % [
		player_name,
		BattleContext.last_score_human,
		BattleContext.last_score_ai,
		npc_name
	]
	_apply_campaign_copy()
	next_levels.add_theme_stylebox_override("panel", UITheme.panel_style(
		NEXT_LEVELS_BG, NEXT_LEVELS_GOLD, 2, 22))
	_refresh_next_button()
	_refresh_next_levels()
	_refresh_save_status()
	_refresh_reward()
	StoryService.register_anchor("result.home", menu_btn)
	StoryService.register_anchor("result.replay", replay_btn)
	StoryService.notify_screen(Routes.CAMPAIGN_RESULT)


## Une manche intermédiaire de série ne doit jamais jouer le verdict final.
func _play_result_sound() -> void:
	var winner := BattleContext.last_winner
	if _campaign and BattleContext.campaign_series_pending():
		match winner:
			GameState.PLAYER_HUMAN:
				Audio.play_jingle(AudioCatalog.SFX_ROUND_WON)
			GameState.PLAYER_AI:
				Audio.play_jingle(AudioCatalog.SFX_ROUND_DEFEAT)
			_:
				Audio.play_jingle(AudioCatalog.SFX_DRAW)
		return
	match winner:
		GameState.PLAYER_HUMAN:
			Audio.play_jingle(AudioCatalog.SFX_VICTORY)
		GameState.PLAYER_AI:
			Audio.play_jingle(AudioCatalog.SFX_DEFEAT)
		_:
			Audio.play_jingle(AudioCatalog.SFX_DRAW)


func _refresh_reward() -> void:
	reward_divider.visible = false
	rewards.visible = false
	for child in reward_cards.get_children():
		reward_cards.remove_child(child)
		child.queue_free()
	if not _campaign or BattleContext.last_winner != GameState.PLAYER_HUMAN \
			or BattleContext.last_reward.is_empty():
		return
	var reward := BattleContext.last_reward
	var souls := int(reward.get("souls", 0))
	var candles := int(reward.get("candles", 0))
	reward_soul_row.visible = souls > 0
	reward_soul_amount.text = "×%s" % UIFormat.integer(souls)
	reward_candle_row.visible = candles > 0
	reward_candle_amount.text = "×%s" % UIFormat.integer(candles)
	for card_reward in reward.get("cards", []):
		_add_reward_card(card_reward, false)
	for card_reward in reward.get("deferred_cards", []):
		_add_reward_card(card_reward, true)
	if souls <= 0 and candles <= 0 and reward_cards.get_child_count() == 0:
		return
	reward_divider.visible = true
	rewards.visible = true
	reward_cards.visible = reward_cards.get_child_count() > 0
	## Le parcours de Pr. Stone met ces récompenses en surbrillance : le bloc
	## entier devient une ancre réelle dès qu'il est visible.
	StoryService.register_anchor("result.rewards", rewards)


func _add_reward_card(card_reward: Dictionary, deferred: bool) -> void:
	var stone_id := StoneLoader.variant_id(str(card_reward.get("lineage_id", "")), 1)
	if stone_id == "":
		return
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size.x = 144
	var card := StoneCard.new()
	card.custom_minimum_size = Vector2(128, 128)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_show_cost(false)
	card.setup(StoneLoader.get_stone(stone_id), StoneCard.OWNER_NONE)
	if deferred:
		card.modulate = Color(0.72, 0.72, 0.78, 1.0)
	wrapper.add_child(card)
	var quantity := Label.new()
	quantity.text = "×%d" % int(card_reward.get("copies", 1))
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity.add_theme_font_size_override("font_size", 24)
	wrapper.add_child(quantity)
	if deferred:
		var god_id := str(card_reward.get("god_id", StoneLoader.stone_affinity(stone_id)))
		var god_name := str(StoneLoader.get_god(god_id).get("name", god_id))
		var status := Label.new()
		status.text = "APRÈS %s" % god_name.to_upper()
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.add_theme_font_size_override("font_size", 16)
		status.add_theme_color_override("font_color", UITheme.COL_WARNING)
		wrapper.add_child(status)
	reward_cards.add_child(wrapper)


## En campagne, les anciennes sorties « autre niveau » et « autre dieu » ne
## correspondent plus à une navigation : elles ramènent à la carte unifiée.
func _apply_campaign_copy() -> void:
	if not _campaign:
		return
	replay_btn.text = "Rejouer"
	level_btn.text = "Carte de campagne"
	gods_btn.visible = false
	menu_btn.text = "Accueil"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_menu()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_menu()


## Niveau qui suit celui joué dans le même chemin historique. Vide au dernier
## rond et hors du parcours par dieu.
func _next_level() -> Dictionary:
	if _campaign:
		return {}
	var source := BattleContext.current_source_id()
	if source == "":
		return {}
	return EncounterPathModel.next_level(
		OpponentCatalogModel.levels_for(source), BattleContext.selected_npc_id)


## Le suivant n'apparaît qu'après une victoire et s'il reste un rond. En
## campagne, une série non terminée reste jouable même après une manche perdue.
## En campagne, le bouton principal ne sert plus qu'à enchaîner une série : la
## suite du parcours passe par les cartes de niveaux suivants.
func _refresh_next_button() -> void:
	if _campaign:
		next_btn.visible = BattleContext.last_result_saved \
			and BattleContext.campaign_series_pending()
		next_btn.text = "Manche suivante"
		return
	next_btn.text = "Niveau suivant"
	next_btn.visible = BattleContext.last_winner == GameState.PLAYER_HUMAN \
		and BattleContext.last_result_saved and not _next_level().is_empty()


func _refresh_save_status() -> void:
	var failed := not BattleContext.last_result_saved
	save_status.visible = failed
	retry_save_btn.visible = failed
	if failed:
		save_status.text = "La progression n'a pas pu être enregistrée (%s)." \
			% error_string(BattleContext.last_save_error)


func _on_retry_save() -> void:
	retry_save_btn.disabled = true
	var error := BattleContext.persist_result()
	retry_save_btn.disabled = false
	if error == OK:
		save_status.text = "Progression enregistrée."
		save_status.add_theme_color_override("font_color", UITheme.COL_SUCCESS)
		retry_save_btn.visible = false
		_refresh_next_button()
		_refresh_next_levels()
		return
	save_status.text = "Échec de l'enregistrement (%s). Réessayez ou vérifiez l'espace disponible." \
		% error_string(error)
	save_status.add_theme_color_override("font_color", UITheme.COL_ERROR)


func _on_next_level() -> void:
	if _campaign:
		if not BattleContext.campaign_series_pending():
			return
		var prepared := BattleContext.prepare_next_mode_round()
		if not bool(prepared.get("ok", false)):
			_show_action_error(str(prepared.get("reason", "Manche suivante impossible.")))
			return
		Routes.go(get_tree(), Routes.CAMPAIGN_PREPARATION
			if bool(prepared.get("requires_draft", false)) else Routes.PRE_BATTLE)
		return
	var next_level := _next_level()
	if next_level.is_empty() or BattleContext.last_winner != GameState.PLAYER_HUMAN:
		return
	var source := BattleContext.current_source_id()
	var opponent := OpponentCatalogModel.build_for_source(
		source, str(next_level.get("bracket_id", "")), str(next_level.get("difficulty_id", "")))
	if opponent.is_empty():
		push_error("Result: impossible de générer l'adversaire du niveau suivant.")
		return
	BattleContext.select_source(source)
	BattleContext.select_opponent(opponent)
	BattleContext.forced_first_player = 0
	Routes.go(get_tree(), Routes.PRE_BATTLE)


## Successeurs directs du niveau gagné, accessibles et affichables. La carte de
## campagne reste l'écran de décision : aucune de ces cartes ne lance un combat.
func _next_level_entries() -> Array:
	var result: Array = []
	var service := CampaignContext.get_service()
	if service == null or not service.is_ready():
		return result
	var node_id := BattleContext.campaign_node_id
	if node_id == "" or not service.has_node(node_id):
		return result
	for successor_id in service.graph().successors(node_id):
		var id := str(successor_id)
		if not service.is_available(id):
			continue
		var node := service.node(id)
		if node == null:
			continue
		var summary := EncounterPresenter.summary(node, PlayerData.player_god_id)
		if not summary.is_empty():
			result.append(summary)
	return result


## Bloc des niveaux suivants : victoire confirmée, résultat réellement écrit et
## aucune manche de série en attente. Le parcours guidé le masque, puisque son
## spotlight impose son propre chemin.
func _refresh_next_levels() -> void:
	_clear_next_levels()
	next_levels.visible = false
	if not _campaign or not BattleContext.last_result_saved:
		return
	if StoryService.is_tutorial_running():
		return
	if not BattleContext.campaign_victory_confirmed() \
			or BattleContext.campaign_series_pending():
		return
	var entries := _next_level_entries()
	if entries.is_empty():
		return
	next_levels_title.text = "NIVEAU SUIVANT" if entries.size() == 1 else "NIVEAUX SUIVANTS"
	_build_next_level_cards(entries)
	next_levels.visible = true


func _clear_next_levels() -> void:
	for child in next_levels_rows.get_children():
		next_levels_rows.remove_child(child)
		child.queue_free()


## Deux cartes par ligne, la dernière centrée : chaque rangée est une HBox
## alignée au centre, jamais une grille qui collerait la carte seule à gauche.
func _build_next_level_cards(entries: Array) -> void:
	var show_name := true
	for summary in entries:
		if str(summary.get("name", "")).length() > NEXT_LEVEL_NAME_MAX_CHARS:
			show_name = false
			break
	var row: HBoxContainer = null
	for index in range(entries.size()):
		if index % NEXT_LEVELS_PER_ROW == 0:
			row = HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", UITheme.GAP_SMALL)
			next_levels_rows.add_child(row)
		row.add_child(_make_next_level_card(entries[index], show_name))


## La carte n'affiche que le dieu et le mode, de quoi choisir sans rouvrir la
## carte. Un appui dépose la demande de fiche, jamais un lancement.
func _make_next_level_card(summary: Dictionary, show_name: bool) -> Button:
	var card: Button = TouchButtonModel.new()
	card.custom_minimum_size = Vector2(NEXT_LEVEL_CARD_WIDTH, NEXT_LEVEL_CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.text = ""
	card.clip_contents = true
	var accent := Color(str(summary.get("accent", UITheme.COL_NEON_PINK.to_html())))
	var normal := UITheme.panel_style(
		UITheme.COL_SURFACE, accent, NEXT_LEVEL_BORDER_WIDTH, 18)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = UITheme.COL_SURFACE.lightened(0.08)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = UITheme.COL_SURFACE.darkened(0.12)
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", pressed)
	card.add_theme_stylebox_override("hover_pressed", pressed)
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 14.0
	content.offset_right = -14.0
	content.offset_top = 10.0
	content.offset_bottom = -10.0
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 2)
	card.add_child(content)
	content.add_child(_next_level_label(
		str(summary.get("opponent_god_label", "")), 30, accent))
	content.add_child(_next_level_label(
		str(summary.get("mode_label", "")), 24, UITheme.COL_TEXT_DIM))
	if show_name:
		content.add_child(_next_level_label(
			str(summary.get("name", "")), 20, UITheme.COL_TEXT_DIM))
	card.pressed.connect(_on_next_level_pressed.bind(str(summary.get("id", ""))))
	return card


func _next_level_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Même une carte ne lance rien : elle demande la fiche du niveau sur la carte,
## où « AFFRONTER » reste le seul déclencheur.
func _on_next_level_pressed(node_id: String) -> void:
	if node_id == "":
		return
	CampaignContext.request_node(node_id)
	Routes.go_with_override(get_tree(), scene_changer, Routes.CAMPAIGN_MAP)


func _on_replay() -> void:
	## Une revanche commence par un nouveau tirage au sort.
	BattleContext.forced_first_player = 0
	if _campaign:
		var replay := CampaignContext.replay_current()
		if not bool(replay.get("ok", false)):
			_show_action_error(str(replay.get("reason", "Revanche impossible.")))
			return
		Routes.go(get_tree(), Routes.CAMPAIGN_PREPARATION
			if bool(replay.get("needs_preparation", false)) else Routes.PRE_BATTLE)
		return
	Routes.go(get_tree(), Routes.PRE_BATTLE)


## En campagne unifié, « autre niveau » signifie revenir à la carte. Le
## parcours historique par dieu reste disponible pour ses propres résultats.
func _on_level_select() -> void:
	if _campaign:
		CampaignContext.focus_node_id = BattleContext.campaign_node_id
		Routes.go(get_tree(), Routes.CAMPAIGN_MAP)
		return
	BattleContext.select_source(BattleContext.navigation_source_id())
	Routes.go(get_tree(), Routes.ENCOUNTER_PATH)


func _on_god_select() -> void:
	if _campaign:
		Routes.go(get_tree(), Routes.CAMPAIGN_MAP)
		return
	Routes.go(get_tree(), Routes.ENCOUNTER_SELECT)


func _on_menu() -> void:
	Routes.go(get_tree(), Routes.MAIN_MENU)


func _show_action_error(message: String) -> void:
	save_status.visible = true
	retry_save_btn.visible = false
	save_status.text = message
	save_status.add_theme_color_override("font_color", UITheme.COL_ERROR)
