## Adaptateur local de la préparation de campagne. Le rendu est partagé avec le
## PVP par ModePreparationView ; seules l'IA et la navigation restent ici.
extends Control

const Routes := preload("res://scripts/ui/GameRoutes.gd")

@onready var background: MenuBackground = $Background
@onready var back_button: Button = $Root/Header/BackButton
@onready var title_label: Label = $Root/Header/Titles/Title
@onready var round_label: Label = $Root/Header/Titles/RoundLabel
@onready var scroll: ScrollContainer = $Root/Scroll
@onready var preparation_view = $Root/Scroll/PreparationView
@onready var status_label: Label = $Root/Footer/StatusLabel
@onready var confirm_button: Button = $Root/Footer/ConfirmButton


func _ready() -> void:
	Audio.set_button_sfx(confirm_button, AudioCatalog.SFX_BUTTON_2)
	back_button.pressed.connect(_on_back)
	confirm_button.pressed.connect(_on_confirm)
	preparation_view.card_chosen.connect(_on_card_chosen)
	preparation_view.bind_scroll(scroll)
	_refresh()


func _process(delta: float) -> void:
	if BattleContext.campaign_mode_session == null:
		return
	var completed := BattleContext.advance_mode_preparation(delta)
	preparation_view.set_remaining_seconds(BattleContext.campaign_mode_session.remaining_seconds())
	if completed:
		_refresh()


func _refresh() -> void:
	set_process(BattleContext.campaign_mode_session != null \
		and BattleContext.campaign_mode_session.is_drafting())
	var state := BattleContext.mode_state()
	if state.is_empty():
		_show_missing_session()
		return
	var rules: Dictionary = state.get("rules", {})
	var mode := str(rules.get("mode", GameModeRules.MODE_CLASSIC))
	var format := str(rules.get("series", SeriesRules.SERIES_FT1))
	title_label.text = "PRÉPARATION • %s" % GameModeRules.mode_label(mode).to_upper()
	var series: Dictionary = state.get("series", {})
	round_label.text = "Partie simple" if format == SeriesRules.SERIES_FT1 \
		else "MANCHE %d • %s" % [int(series.get("round_index", 1)), format.to_upper()]
	status_label.visible = false
	status_label.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	var draft: Dictionary = state.get("draft", {})
	var draft_open := bool(draft.get("started", false)) and not bool(draft.get("own_complete", false))
	if draft_open:
		preparation_view.show_draft(draft)
		confirm_button.visible = false
		return
	var own: Dictionary = state.get("own_loadout", {})
	if own.is_empty():
		preparation_view.show_waiting("Préparation du deck en cours…")
		confirm_button.visible = false
		return
	var god: Dictionary = preparation_view.show_loadout(own,
		int(rules.get("power_tier", GameModeRules.DEFAULT_POWER_TIER)), format)
	background.set_god(god)
	confirm_button.visible = true
	confirm_button.disabled = not BattleContext.has_prepared_loadouts()
	confirm_button.text = "⚔  AFFRONTER"


func _show_missing_session() -> void:
	preparation_view.show_waiting("Préparation de campagne absente. Revenez à la carte.")
	status_label.text = "La session de préparation n'est plus disponible."
	status_label.visible = true
	status_label.add_theme_color_override("font_color", UITheme.COL_ERROR)
	confirm_button.visible = false


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
