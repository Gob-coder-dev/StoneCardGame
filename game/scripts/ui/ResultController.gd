## ResultController.gd
## Écran de résultat après une partie. En campagne, la victoire d'un nœud
## ramène à la carte unifiée ; une série non terminée propose la manche
## suivante. Les adversaires historiques conservent les cinq sorties d'origine.
extends Control

const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const EncounterPathModel := preload("res://scripts/domain/EncounterPath.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")

@onready var result_label: Label = $VBoxCenter/ResultCard/Content/ResultLabel
@onready var score_label: Label = $VBoxCenter/ResultCard/Content/ScoreLabel
@onready var reward_divider: ColorRect = $VBoxCenter/ResultCard/Content/RewardDivider
@onready var rewards: VBoxContainer = $VBoxCenter/ResultCard/Content/Rewards
@onready var reward_soul_row: HBoxContainer = $VBoxCenter/ResultCard/Content/Rewards/SoulRow
@onready var reward_soul_amount: Label = $VBoxCenter/ResultCard/Content/Rewards/SoulRow/Amount
@onready var reward_cards: HBoxContainer = $VBoxCenter/ResultCard/Content/Rewards/Cards
@onready var background: MenuBackground = $Background
@onready var next_btn: Button = $VBoxCenter/NextButton
@onready var replay_btn: Button = $VBoxCenter/ReplayButton
@onready var level_btn: Button = $VBoxCenter/LevelsButton
@onready var gods_btn: Button = $VBoxCenter/GodsButton
@onready var menu_btn: Button = $VBoxCenter/MainMenuButton
@onready var save_status: Label = $VBoxCenter/SaveStatus
@onready var retry_save_btn: Button = $VBoxCenter/RetrySaveButton

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
	_refresh_next_button()
	_refresh_save_status()
	_refresh_reward()


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
	reward_soul_row.visible = souls > 0
	reward_soul_amount.text = "×%s" % UIFormat.integer(souls)
	for card_reward in reward.get("cards", []):
		var stone_id := StoneLoader.variant_id(str(card_reward.get("lineage_id", "")), 1)
		if stone_id == "":
			continue
		var wrapper := VBoxContainer.new()
		wrapper.custom_minimum_size.x = 128
		var card := StoneCard.new()
		card.custom_minimum_size = Vector2(128, 128)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.set_show_cost(false)
		card.setup(StoneLoader.get_stone(stone_id), StoneCard.OWNER_NONE)
		wrapper.add_child(card)
		var quantity := Label.new()
		quantity.text = "×%d" % int(card_reward.get("copies", 1))
		quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quantity.add_theme_font_size_override("font_size", 24)
		wrapper.add_child(quantity)
		reward_cards.add_child(wrapper)
	if souls <= 0 and reward_cards.get_child_count() == 0:
		return
	reward_divider.visible = true
	rewards.visible = true
	reward_cards.visible = reward_cards.get_child_count() > 0


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
func _refresh_next_button() -> void:
	if _campaign:
		var pending := BattleContext.campaign_series_pending()
		var victory := BattleContext.last_winner == GameState.PLAYER_HUMAN \
			and BattleContext.campaign_victory_confirmed()
		next_btn.visible = BattleContext.last_result_saved and (pending or victory)
		if pending:
			next_btn.text = "Manche suivante"
		elif victory:
			next_btn.text = "Retour à la carte"
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
		return
	save_status.text = "Échec de l'enregistrement (%s). Réessayez ou vérifiez l'espace disponible." \
		% error_string(error)
	save_status.add_theme_color_override("font_color", UITheme.COL_ERROR)


func _on_next_level() -> void:
	if _campaign:
		if BattleContext.campaign_series_pending():
			var prepared := BattleContext.prepare_next_mode_round()
			if not bool(prepared.get("ok", false)):
				_show_action_error(str(prepared.get("reason", "Manche suivante impossible.")))
				return
			Routes.go(get_tree(), Routes.CAMPAIGN_PREPARATION
				if bool(prepared.get("requires_draft", false)) else Routes.PRE_BATTLE)
			return
		CampaignContext.focus_node_id = BattleContext.campaign_node_id
		Routes.go(get_tree(), Routes.CAMPAIGN_MAP)
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
