## Vue commune des préparations Aléatoire, Miroir et Sélection.
## Elle ne connaît ni le réseau ni la campagne : les contrôleurs lui projettent
## un état local déjà filtré et relaient l'intention de choisir une carte.
class_name ModePreparationView
extends VBoxContainer

signal card_chosen(stone_id: String)

const LayoutModel := preload("res://scripts/ui/preparation/ModePreparationLayout.gd")
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")

@onready var draft_panel: VBoxContainer = $DraftPanel
@onready var opponent_info: Label = $DraftPanel/OpponentPanel/OpponentBox/OpponentInfo
@onready var opponent_grid: LoadoutCardGrid = \
	$DraftPanel/OpponentPanel/OpponentBox/OpponentGrid
@onready var local_grid: LoadoutCardGrid = $DraftPanel/LocalPanel/LocalBox/LocalGrid
@onready var draft_status: Label = $DraftPanel/LocalPanel/LocalBox/DraftStatus
@onready var draft_info: Label = $DraftPanel/LocalPanel/LocalBox/DraftInfo
@onready var draft_timer: Label = $DraftPanel/LocalPanel/LocalBox/DraftTimer
@onready var draft_deck_grid: LoadoutCardGrid = \
	$DraftPanel/DraftDeckPanel/DraftDeckBox/DraftDeckGrid
@onready var draft_deck_title: Label = \
	$DraftPanel/DraftDeckPanel/DraftDeckBox/DraftDeckTitle
@onready var reveal_panel: VBoxContainer = $RevealPanel
@onready var god_portrait: GodPortrait = $RevealPanel/GodPanel/GodBox/GodPortrait
@onready var god_name: Label = $RevealPanel/GodPanel/GodBox/GodInfo/GodName
@onready var god_family: Label = $RevealPanel/GodPanel/GodBox/GodInfo/GodFamily
@onready var loadout_info: Label = $RevealPanel/GodPanel/GodBox/GodInfo/LoadoutInfo
@onready var deck_grid: LoadoutCardGrid = $RevealPanel/DeckGrid
@onready var wait_label: Label = $WaitLabel

var _scroll: ScrollContainer = null
var _draft: Dictionary = {}
var _loadout: Dictionary = {}
var _chosen := ""
var _tier := GameModeRules.DEFAULT_POWER_TIER
var _format := SeriesRules.SERIES_FT1
var _draft_deck_columns := 4
var _opponent_card_size := UITheme.PVP_OPPONENT_CARD_MAX
var _local_card_size := UITheme.PVP_LOCAL_CARD_MAX
var _draft_card_size := UITheme.PVP_DRAFT_CARD_MAX
var _final_card_size := UITheme.PVP_FINAL_CARD_MAX
var _layout_fit_pending := false
var _displayed_second := -1


func _ready() -> void:
	local_grid.card_chosen.connect(card_chosen.emit)


func bind_scroll(value: ScrollContainer) -> void:
	if _scroll != null and _scroll.resized.is_connected(_on_scroll_resized):
		_scroll.resized.disconnect(_on_scroll_resized)
	_scroll = value
	if _scroll != null and not _scroll.resized.is_connected(_on_scroll_resized):
		_scroll.resized.connect(_on_scroll_resized)
	_on_scroll_resized()


func show_draft(draft: Dictionary, chosen: String = "") -> void:
	_draft = draft.duplicate(true)
	_loadout.clear()
	_chosen = chosen
	draft_panel.visible = true
	reveal_panel.visible = false
	wait_label.visible = false
	_render_draft()
	_schedule_layout_fit()


func show_loadout(loadout: Dictionary, power_tier: int,
		series_format: String) -> Dictionary:
	_draft.clear()
	_loadout = loadout.duplicate(true)
	_tier = power_tier
	_format = series_format
	draft_panel.visible = false
	reveal_panel.visible = true
	wait_label.visible = false
	_displayed_second = -1
	var god := GodIdentityModel.player(str(loadout.get("god_id", "")))
	god_portrait.setup(god)
	god_name.text = str(god.get("name", "Sans dieu"))
	var family := str(god.get("family_name", ""))
	god_family.text = family if family != "" else "Dieu"
	god_family.add_theme_color_override("font_color",
		Color(str(god.get("color", UITheme.COL_TEXT.to_html()))))
	var deck: Array = loadout.get("deck", [])
	var total := float(int(loadout.get("total_quarters", 0))) \
		/ float(StoneCostRules.COST_SCALE)
	loadout_info.text = "%d cartes • %.2f points • palier %d • %s" % [
		deck.size(), total, power_tier, series_format.to_upper()
	]
	deck_grid.show_cards(deck, _final_card_size, 2, false, "", _final_card_size)
	_schedule_layout_fit()
	return god


func show_waiting(message: String) -> void:
	_draft.clear()
	_loadout.clear()
	draft_panel.visible = false
	reveal_panel.visible = false
	wait_label.visible = true
	wait_label.text = message
	_displayed_second = -1


## Actualisation légère : aucune carte n'est reconstruite tant que seule la
## seconde affichée change.
func set_remaining_seconds(remaining: float) -> void:
	if not draft_panel.visible:
		draft_timer.visible = false
		_displayed_second = -1
		return
	var second := maxi(0, int(ceilf(remaining)))
	draft_timer.visible = true
	if second == _displayed_second:
		return
	_displayed_second = second
	draft_timer.text = "Temps de sélection : %d s" % second
	var color := UITheme.COL_WARNING
	if second <= 5:
		color = UITheme.COL_ERROR
	elif second <= 10:
		color = UITheme.COL_ACCENT_LIGHT
	draft_timer.add_theme_color_override("font_color", color)


func _render_draft() -> void:
	var own_side := int(_draft.get("own_side", GameState.PLAYER_ONE))
	var opponent_offers: Array = _draft.get("offers_two", []) \
		if own_side == GameState.PLAYER_ONE else _draft.get("offers_one", [])
	var own_offers: Array = _draft.get("own_offers", [])
	var step := int(_draft.get("own_step", _draft.get("step", 0)))
	var total := int(_draft.get("total_steps", DeckRules.DECK_SIZE))
	var opponent_step := clampi(int(_draft.get("opponent_step", 0)), 0, total)
	var own_deck: Array = (_draft.get("own_deck", []) as Array).duplicate(true)
	opponent_info.text = "Adversaire : %d / %d cartes choisies" % [opponent_step, total]
	opponent_grid.show_cards(opponent_offers, _opponent_card_size, 2, false, "",
		_opponent_card_size)
	local_grid.show_cards(own_offers, _local_card_size, 2,
		_chosen == "" and not own_offers.is_empty(), _chosen, _local_card_size)
	draft_deck_grid.show_cards(own_deck, _draft_card_size, _draft_deck_columns,
		false, "", _draft_card_size)
	draft_deck_title.text = "VOTRE DECK — %d / %d" % [own_deck.size(), total]
	if _chosen != "":
		draft_status.text = "Choix enregistré."
	elif own_offers.is_empty():
		draft_status.text = "Votre deck est terminé."
	else:
		draft_status.text = "Choisissez une carte."
	draft_info.text = "Étape %d / %d • %d cartes choisies" % [
		mini(step + 1, total), total, own_deck.size()
	]
	set_remaining_seconds(float(_draft.get("remaining_seconds", 0.0)))


func _on_scroll_resized() -> void:
	if _scroll == null:
		return
	var columns := LayoutModel.draft_columns(_scroll.size.x)
	if columns != _draft_deck_columns:
		_draft_deck_columns = columns
		if draft_panel.visible and not _draft.is_empty():
			_render_draft()
	_schedule_layout_fit()


func _schedule_layout_fit() -> void:
	if _layout_fit_pending or not is_inside_tree() or _scroll == null:
		return
	_layout_fit_pending = true
	_fit_current_layout.call_deferred()


func _fit_current_layout() -> void:
	_layout_fit_pending = false
	if _scroll == null or _scroll.size.x <= 0.0 or _scroll.size.y <= 0.0:
		return
	var changed := _fit_draft_layout() if draft_panel.visible \
		else (_fit_reveal_layout() if reveal_panel.visible else false)
	if changed:
		if draft_panel.visible:
			_render_draft()
		elif reveal_panel.visible:
			show_loadout(_loadout, _tier, _format)
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar.max_value <= bar.page + 1.0:
		_scroll.scroll_vertical = 0


func _fit_draft_layout() -> bool:
	var next := LayoutModel.draft_sizes(size, _scroll.size,
		draft_panel.get_combined_minimum_size().y,
		[opponent_grid.size.x, local_grid.size.x, draft_deck_grid.size.x],
		[opponent_grid.get_child_count(), local_grid.get_child_count(),
			draft_deck_grid.get_child_count()], _draft_deck_columns,
		[_opponent_card_size, _local_card_size, _draft_card_size])
	var next_opponent := int(next["opponent"])
	var next_local := int(next["local"])
	var next_deck := int(next["deck"])
	var changed := next_opponent != _opponent_card_size \
		or next_local != _local_card_size or next_deck != _draft_card_size
	_opponent_card_size = next_opponent
	_local_card_size = next_local
	_draft_card_size = next_deck
	return changed


func _fit_reveal_layout() -> bool:
	var next_size := LayoutModel.reveal_size(_scroll.size,
		reveal_panel.get_combined_minimum_size().y, deck_grid.size.x, _final_card_size)
	if next_size == _final_card_size:
		return false
	_final_card_size = next_size
	return true
