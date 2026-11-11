## CampaignPreparationController.gd
## Préparation locale des modes de campagne : révélation des loadouts générés
## ou draft contre l'IA. Elle réutilise LoadoutCardGrid et CampaignModeSession,
## jamais les contrôleurs ou coordinateurs réseau du PVP.
extends Control

const Routes := preload("res://scripts/ui/GameRoutes.gd")
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")
const EncounterPresenter := preload("res://scripts/ui/campaign/CampaignEncounterPresenter.gd")
const LayoutModel := preload("res://scripts/ui/pvp/PvpPreparationLayout.gd")

@onready var background: MenuBackground = $Background
@onready var back_button: Button = $Root/Header/BackButton
@onready var title_label: Label = $Root/Header/TitleLabel
@onready var timer_label: Label = $Root/Header/TimerLabel
@onready var scroll: ScrollContainer = $Root/Scroll
@onready var content: VBoxContainer = $Root/Scroll/Content
@onready var status_label: Label = $Root/Scroll/Content/StatusLabel
@onready var offers_grid: LoadoutCardGrid = $Root/Scroll/Content/OffersGrid
@onready var deck_title: Label = $Root/Scroll/Content/DeckTitle
@onready var deck_grid: LoadoutCardGrid = $Root/Scroll/Content/DeckGrid
@onready var confirm_button: Button = $Root/ConfirmButton

var _deck_ids: Array = []
var _deck_card_size := UITheme.PVP_FINAL_CARD_MAX
var _layout_fit_pending := false


func _ready() -> void:
	Audio.set_button_sfx(confirm_button, AudioCatalog.SFX_BUTTON_2)
	back_button.pressed.connect(_on_back)
	confirm_button.pressed.connect(_on_confirm)
	offers_grid.card_chosen.connect(_on_card_chosen)
	scroll.resized.connect(_schedule_deck_fit)
	background.set_god(GodIdentityModel.player(PlayerData.player_god_id))
	var service := CampaignContext.get_service()
	var summary := EncounterPresenter.summary(service.node(CampaignContext.active_node_id()),
		PlayerData.player_god_id)
	title_label.text = str(summary.get("name", "PRÉPARATION")).to_upper()
	status_label.visible = false
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
	var draft_open := bool(draft.get("started", false)) and not bool(draft.get("complete", false))
	status_label.visible = false
	status_label.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	offers_grid.visible = draft_open
	if draft_open:
		_deck_ids.clear()
		var offers: Array = draft.get("own_offers", [])
		var own_deck: Array = draft.get("own_deck", [])
		offers_grid.show_cards(offers, UITheme.CARD_HAND, 2, true, "",
			UITheme.PVP_LOCAL_CARD_MAX)
		deck_grid.show_cards(own_deck, UITheme.CARD_DECK, 4, false)
		deck_title.text = "VOTRE DECK — %d / %d" % [own_deck.size(), DeckRules.DECK_SIZE]
		timer_label.visible = true
		timer_label.text = "%d s" % int(ceilf(float(draft.get("remaining_seconds", 0.0))))
		status_label.text = "Choisissez une carte parmi les deux offres. L'IA effectue son propre draft en parallèle."
		status_label.visible = true
		confirm_button.disabled = BattleContext.player_loadout == null
		confirm_button.text = "COMMENCER" if not confirm_button.disabled else "DRAFT EN COURS…"
		return
	timer_label.visible = false
	var own: Dictionary = state.get("own_loadout", {})
	if not own.is_empty():
		_deck_ids = (own.get("deck", []) as Array).duplicate()
		# Même présentation verticale que la révélation PVP : deux colonnes,
		# quatre lignes et une taille limitée par la hauteur disponible.
		deck_grid.show_cards(_deck_ids, _deck_card_size, 2, false, "", _deck_card_size)
		deck_title.text = "VOTRE DECK"
	else:
		_deck_ids.clear()
		deck_grid.show_cards([], UITheme.CARD_DECK, 4, false)
		deck_title.text = "VOTRE DECK"
	confirm_button.disabled = not BattleContext.has_prepared_loadouts()
	confirm_button.text = "⚔  AFFRONTER"
	_schedule_deck_fit()


func _show_missing_session() -> void:
	_deck_ids.clear()
	status_label.text = "Préparation de campagne absente. Revenez à la carte."
	status_label.visible = true
	offers_grid.visible = false
	confirm_button.disabled = true
	confirm_button.text = "INDISPONIBLE"


func _schedule_deck_fit() -> void:
	if _layout_fit_pending or _deck_ids.is_empty() or not is_inside_tree():
		return
	_layout_fit_pending = true
	_fit_deck_layout.call_deferred()


func _fit_deck_layout() -> void:
	_layout_fit_pending = false
	if _deck_ids.is_empty() or scroll.size.x <= 0.0 or scroll.size.y <= 0.0:
		return
	var next_size := LayoutModel.reveal_size(scroll.size,
		content.get_combined_minimum_size().y, deck_grid.size.x, _deck_card_size)
	if next_size == _deck_card_size:
		return
	_deck_card_size = next_size
	deck_grid.show_cards(_deck_ids, _deck_card_size, 2, false, "", _deck_card_size)


func _on_card_chosen(stone_id: String) -> void:
	if BattleContext.choose_draft_card(stone_id):
		_refresh()


func _on_confirm() -> void:
	if not BattleContext.confirm_mode_preparation():
		status_label.text = "Les loadouts ne sont pas encore prêts."
		status_label.visible = true
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
