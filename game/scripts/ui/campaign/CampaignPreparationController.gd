## CampaignPreparationController.gd
## Préparation locale des modes de campagne : révélation des loadouts générés
## ou draft contre l'IA. Elle réutilise LoadoutCardGrid et CampaignModeSession,
## jamais les contrôleurs ou coordinateurs réseau du PVP.
extends Control

const Routes := preload("res://scripts/ui/GameRoutes.gd")

@onready var background: MenuBackground = $Background
@onready var back_button: Button = $Root/Header/BackButton
@onready var title_label: Label = $Root/Header/TitleLabel
@onready var timer_label: Label = $Root/Header/TimerLabel
@onready var scroll: ScrollContainer = $Root/Scroll
@onready var status_label: Label = $Root/Scroll/Content/StatusLabel
@onready var offers_grid: LoadoutCardGrid = $Root/Scroll/Content/OffersGrid
@onready var deck_title: Label = $Root/Scroll/Content/DeckTitle
@onready var deck_grid: LoadoutCardGrid = $Root/Scroll/Content/DeckGrid
@onready var opponent_title: Label = $Root/Scroll/Content/OpponentTitle
@onready var opponent_grid: LoadoutCardGrid = $Root/Scroll/Content/OpponentGrid
@onready var confirm_button: Button = $Root/ConfirmButton


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	confirm_button.pressed.connect(_on_confirm)
	offers_grid.card_chosen.connect(_on_card_chosen)
	background.set_god(StoneLoader.get_god(PlayerData.player_god_id))
	var summary := CampaignContext.active_summary(PlayerData.player_god_id)
	title_label.text = str(summary.get("name", "PRÉPARATION")).to_upper()
	_refresh()


func _process(delta: float) -> void:
	if BattleContext.campaign_mode_session == null:
		return
	if BattleContext.advance_mode_preparation(delta):
		_refresh()


func _refresh() -> void:
	var state := BattleContext.mode_state()
	if state.is_empty():
		_show_missing_session()
		return
	var rules: Dictionary = state.get("rules", {})
	var draft: Dictionary = state.get("draft", {})
	var mode := str(rules.get("mode", GameModeRules.MODE_CLASSIC))
	var draft_open := bool(draft.get("started", false)) and not bool(draft.get("complete", false))
	offers_grid.visible = draft_open
	if draft_open:
		var offers: Array = draft.get("own_offers", [])
		var own_deck: Array = draft.get("own_deck", [])
		offers_grid.show_cards(offers, UITheme.CARD_HAND, 2, true, "",
			UITheme.PVP_LOCAL_CARD_MAX)
		deck_grid.show_cards(own_deck, UITheme.CARD_DECK, 4, false)
		deck_title.text = "VOTRE DECK — %d / %d" % [own_deck.size(), DeckRules.DECK_SIZE]
		opponent_title.visible = false
		opponent_grid.visible = false
		timer_label.visible = true
		timer_label.text = "%d s" % int(ceilf(float(draft.get("remaining_seconds", 0.0))))
		status_label.text = "Choisissez une carte parmi les deux offres. L'IA effectue son propre draft en parallèle."
		confirm_button.disabled = BattleContext.player_loadout == null
		confirm_button.text = "COMMENCER" if not confirm_button.disabled else "DRAFT EN COURS…"
		return
	timer_label.visible = false
	var own: Dictionary = state.get("own_loadout", {})
	var opponent: Dictionary = state.get("opponent_loadout", {})
	if not own.is_empty():
		deck_grid.show_cards(own.get("deck", []), UITheme.CARD_DECK, 4, false)
		deck_title.text = "VOTRE LOADOUT — %s" % _god_name(str(own.get("god_id", "")))
	else:
		deck_grid.show_cards([], UITheme.CARD_DECK, 4, false)
		deck_title.text = "VOTRE DECK"
	if not opponent.is_empty():
		opponent_title.visible = mode != GameModeRules.MODE_DRAFT
		opponent_grid.visible = opponent_title.visible
		opponent_grid.show_cards(opponent.get("deck", []), UITheme.CARD_DECK, 4, false)
		opponent_title.text = "LOADOUT ADVERSE — %s" % _god_name(str(opponent.get("god_id", "")))
	else:
		opponent_title.visible = false
		opponent_grid.visible = false
	status_label.text = "Loadouts temporaires prêts. Le profil permanent n'est pas modifié."
	confirm_button.disabled = not BattleContext.has_prepared_loadouts()
	confirm_button.text = "⚔  AFFRONTER"


func _show_missing_session() -> void:
	status_label.text = "Préparation de campagne absente. Revenez à la carte."
	offers_grid.visible = false
	opponent_grid.visible = false
	confirm_button.disabled = true
	confirm_button.text = "INDISPONIBLE"


func _god_name(god_id: String) -> String:
	if god_id == "":
		return "Sans dieu"
	return str(StoneLoader.get_god(god_id).get("name", god_id)).to_upper()


func _on_card_chosen(stone_id: String) -> void:
	if BattleContext.choose_draft_card(stone_id):
		_refresh()


func _on_confirm() -> void:
	if not BattleContext.confirm_mode_preparation():
		status_label.text = "Les loadouts ne sont pas encore prêts."
		status_label.add_theme_color_override("font_color", UITheme.COL_ERROR)
		return
	Routes.go(get_tree(), Routes.PRE_BATTLE)


func _on_back() -> void:
	BattleContext.clear_mode_session()
	Routes.go(get_tree(), Routes.CAMPAIGN_MAP)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()
