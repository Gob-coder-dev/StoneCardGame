## CampaignLevelDialog.gd
## Fiche d'un niveau. Elle affiche la synthèse fournie par le service et émet
## seulement une demande de lancement : elle ne calcule ni déverrouillage ni
## adversaire et ne touche jamais à la progression.
##
## La fiche privilégie la rencontre : face-à-face des deux dieux, conditions
## expliquées et récompenses. Les valeurs techniques restent masquées tant
## qu'elles ne s'écartent pas des règles par défaut ou qu'elles n'annoncent pas
## une rencontre signée (boss et mini-boss).
class_name CampaignLevelDialog
extends Control

signal launch_requested(node_id: String)
signal replay_requested(sequence_ids: Array[String])
signal closed

const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")
const BotIdentityModel := preload("res://scripts/data/BotIdentity.gd")

@onready var backdrop: Button = $Backdrop
@onready var close_button: Button = $Panel/Margin/Content/Header/CloseButton
@onready var chapter_label: Label = $Panel/Margin/Content/Header/ChapterLabel
@onready var name_label: Label = $Panel/Margin/Content/NameLabel
@onready var type_row: HBoxContainer = $Panel/Margin/Content/Chips
@onready var type_label: Label = $Panel/Margin/Content/Chips/TypeLabel
@onready var mode_card: PanelContainer = $Panel/Margin/Content/InfoCards/ModeCard
@onready var mode_label: Label = \
	$Panel/Margin/Content/InfoCards/ModeCard/ModeBox/ModeLabel
@onready var mode_hint: Label = \
	$Panel/Margin/Content/InfoCards/ModeCard/ModeBox/ModeHint
@onready var difficulty_card: PanelContainer = \
	$Panel/Margin/Content/InfoCards/Row/DifficultyCard
@onready var stars_label: Label = \
	$Panel/Margin/Content/InfoCards/Row/DifficultyCard/DifficultyBox/DifficultyValue/Stars
@onready var stars_word: Label = \
	$Panel/Margin/Content/InfoCards/Row/DifficultyCard/DifficultyBox/DifficultyValue/StarsWord
@onready var stars_hint: Label = \
	$Panel/Margin/Content/InfoCards/Row/DifficultyCard/DifficultyBox/StarsHint
@onready var power_card: PanelContainer = \
	$Panel/Margin/Content/InfoCards/Row/PowerCard
@onready var power_label: Label = \
	$Panel/Margin/Content/InfoCards/Row/PowerCard/PowerBox/PowerRow/PowerLabel
@onready var pips: HBoxContainer = \
	$Panel/Margin/Content/InfoCards/Row/PowerCard/PowerBox/PowerRow/Pips
@onready var power_hint: Label = \
	$Panel/Margin/Content/InfoCards/Row/PowerCard/PowerBox/PowerHint
@onready var player_portrait: GodPortrait = \
	$Panel/Margin/Content/Duel/PlayerSide/PortraitSlot/Portrait
@onready var player_name_label: Label = $Panel/Margin/Content/Duel/PlayerSide/Name
@onready var opponent_portrait: GodPortrait = \
	$Panel/Margin/Content/Duel/OpponentSide/PortraitSlot/Portrait
@onready var opponent_unknown: PanelContainer = \
	$Panel/Margin/Content/Duel/OpponentSide/PortraitSlot/Unknown
@onready var opponent_name_label: Label = $Panel/Margin/Content/Duel/OpponentSide/Name
@onready var rewards_panel: PanelContainer = $Panel/Margin/Content/RewardsPanel
@onready var souls_row: HBoxContainer = \
	$Panel/Margin/Content/RewardsPanel/RewardsBox/RewardIcons/SoulsRow
@onready var soul_amount: Label = \
	$Panel/Margin/Content/RewardsPanel/RewardsBox/RewardIcons/SoulsRow/Amount
@onready var candle_row: HBoxContainer = \
	$Panel/Margin/Content/RewardsPanel/RewardsBox/RewardIcons/CandleRow
@onready var candle_amount: Label = \
	$Panel/Margin/Content/RewardsPanel/RewardsBox/RewardIcons/CandleRow/Amount
@onready var cards_title: Label = \
	$Panel/Margin/Content/RewardsPanel/RewardsBox/CardsTitle
@onready var reward_cards: HBoxContainer = \
	$Panel/Margin/Content/RewardsPanel/RewardsBox/RewardCards
@onready var technical_panel: PanelContainer = $Panel/Margin/Content/TechnicalPanel
@onready var technical_box: VBoxContainer = \
	$Panel/Margin/Content/TechnicalPanel/TechnicalBox
@onready var replay_button: Button = $Panel/Margin/Content/ReplayButton
@onready var error_label: Label = $Panel/Margin/Content/ErrorLabel
@onready var launch_button: Button = $Panel/Margin/Content/LaunchButton

var _node_id: String = ""
var _state: int = 0
var _replay_sequence_ids: Array[String] = []
var _pips: Array[PanelContainer] = []
var _focus := preload("res://scripts/ui/input/FocusScope.gd").new()


func _ready() -> void:
	Audio.set_button_sfx(launch_button, AudioCatalog.SFX_BUTTON_2)
	Audio.set_button_sfx(replay_button, AudioCatalog.SFX_BUTTON_2)
	backdrop.pressed.connect(close)
	close_button.pressed.connect(close)
	launch_button.pressed.connect(_on_launch)
	replay_button.pressed.connect(_on_replay)
	_apply_chip(type_label, UITheme.COL_TEXT_DIM)
	_style_info_card(mode_card, UITheme.COL_ACCENT_LIGHT)
	_style_info_card(difficulty_card, UITheme.COL_WARNING)
	_style_info_card(power_card, UITheme.COL_NEON_PINK)
	_build_pips()
	opponent_unknown.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.COL_BG.darkened(0.18), UITheme.COL_BORDER, 3, 14))
	var rewards_style := UITheme.panel_style(UITheme.COL_TAB_IDLE, UITheme.COL_BORDER, 2, 12)
	rewards_style.content_margin_left = 18
	rewards_style.content_margin_right = 18
	rewards_style.content_margin_top = 10
	rewards_style.content_margin_bottom = 12
	rewards_panel.add_theme_stylebox_override("panel", rewards_style)
	var technical_style := UITheme.panel_style(Color.TRANSPARENT,
		UITheme.COL_BORDER.darkened(0.25), 1, 10)
	technical_style.content_margin_left = 14
	technical_style.content_margin_right = 14
	technical_style.content_margin_top = 8
	technical_style.content_margin_bottom = 8
	technical_style.shadow_size = 0
	technical_style.shadow_offset = Vector2.ZERO
	technical_panel.add_theme_stylebox_override("panel", technical_style)


func open(summary: Dictionary, state: int, opener: Control = null) -> void:
	if summary.is_empty():
		return
	_focus.capture(self, opener)
	_node_id = str(summary.get("id", ""))
	_state = state
	var accent := Color(str(summary.get("accent", UITheme.COL_NEON_PINK.to_html())))
	name_label.text = str(summary.get("name", "")).to_upper()
	name_label.add_theme_color_override("font_color", accent)
	chapter_label.text = str(summary.get("chapter", "")).to_upper()
	chapter_label.visible = chapter_label.text != ""
	var node_type := str(summary.get("type", CampaignNode.TYPE_NORMAL))
	var type_text := str(summary.get("type_label", "")).to_upper()
	type_label.text = type_text
	type_label.visible = node_type != CampaignNode.TYPE_NORMAL and type_text != ""
	type_row.visible = type_label.visible
	_apply_chip(type_label, _type_color(node_type))
	mode_label.text = str(summary.get("mode_label", ""))
	mode_label.visible = mode_label.text != ""
	mode_hint.text = str(summary.get("mode_description", ""))
	mode_hint.visible = mode_hint.text != ""
	var tier := int(summary.get("tier", CardPowerTierRules.MIN_TIER))
	power_label.text = str(summary.get("power_label", CardPowerTierRules.short_label(tier)))
	power_hint.text = str(summary.get("power_description", CardPowerTierRules.description(tier)))
	power_hint.visible = power_hint.text != ""
	_refresh_pips(tier)
	_setup_gods(summary)
	stars_label.text = BotIdentityModel.stars_text(int(summary.get("stars", 1)))
	stars_word.text = str(summary.get("stars_word", "")).to_lower()
	stars_word.visible = stars_word.text != ""
	stars_hint.text = str(summary.get("stars_hint", ""))
	stars_hint.visible = stars_hint.text != ""
	_refresh_rewards(summary)
	_refresh_technical(summary.get("technical_lines", []))
	_refresh_replay()
	launch_button.disabled = state == 0
	launch_button.text = "REJOUER" if state == 2 else "AFFRONTER"
	error_label.visible = false
	visible = true
	if launch_button.disabled:
		close_button.grab_focus()
	else:
		launch_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	_focus.restore()
	closed.emit()


func handle_navigation(event: InputEvent) -> void:
	_focus.handle(event, [close_button, launch_button, replay_button], get_viewport())


## Le joueur voit toujours son dieu. En face, un dieu imposé ou miroir garde son
## portrait ; un mode généré sans dieu montre « ? » jusqu'au lancement.
func _setup_gods(summary: Dictionary) -> void:
	var player := GodIdentityModel.player(str(summary.get("player_god_id", "")))
	player_portrait.setup(player)
	player_name_label.text = str(player.get("name", "Sans dieu")).to_upper()
	var unknown := bool(summary.get("opponent_god_unknown", false))
	opponent_portrait.visible = not unknown
	opponent_unknown.visible = unknown
	if unknown:
		opponent_name_label.text = str(
			summary.get("opponent_god_label", "Adversaire")).to_upper()
		return
	var opponent := GodIdentityModel.bot(str(summary.get("opponent_god_id", "")))
	opponent_portrait.setup(opponent)
	opponent_name_label.text = str(summary.get("opponent_god_label",
		opponent.get("name", "Adversaire"))).to_upper()


## Les récompenses reprennent les visuels de l'écran de victoire : icône d'âme,
## icône de bougie et mini-cartes. Les cartes ne sont annoncées qu'à la
## première victoire, sinon elles laisseraient croire à un second gain.
func _refresh_rewards(summary: Dictionary) -> void:
	var value: Variant = summary.get("rewards", {})
	var rewards: Dictionary = value if value is Dictionary else {}
	var minimum := maxi(0, int(rewards.get("souls_min", 0)))
	var maximum := maxi(minimum, int(rewards.get("souls_max", minimum)))
	var candles := maxi(0, int(rewards.get("candles", 0)))
	var cards: Array = rewards.get("cards", [])
	_clear_reward_cards()
	souls_row.visible = maximum > 0
	candle_row.visible = candles > 0
	var show_cards := not cards.is_empty() and _state != 2
	cards_title.visible = show_cards
	reward_cards.visible = show_cards
	rewards_panel.visible = souls_row.visible or candle_row.visible or show_cards
	if not rewards_panel.visible:
		return
	soul_amount.text = ("%s – %s" % [UIFormat.integer(minimum),
		UIFormat.integer(maximum)]) if maximum != minimum \
		else ("×%s" % UIFormat.integer(maximum))
	candle_amount.text = "×%d" % candles
	if not show_cards:
		return
	for card in cards:
		if not card is Dictionary:
			continue
		var monster_id := str((card as Dictionary).get("monster_id", ""))
		if monster_id == "":
			continue
		reward_cards.add_child(_reward_card(monster_id,
			int((card as Dictionary).get("copies", 1))))


func _clear_reward_cards() -> void:
	for child in reward_cards.get_children():
		reward_cards.remove_child(child)
		child.queue_free()


func _reward_card(monster_id: String, copies: int) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size.x = 84
	wrapper.add_theme_constant_override("separation", 2)
	var view := MonsterCard.new()
	view.custom_minimum_size = Vector2(84, 84)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_show_cost(false)
	view.setup(MonsterLoader.get_monster(monster_id), MonsterCard.OWNER_NONE)
	wrapper.add_child(view)
	var quantity := Label.new()
	quantity.text = "×%d" % copies
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity.add_theme_font_size_override("font_size", 20)
	quantity.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	wrapper.add_child(quantity)
	return wrapper


func _refresh_technical(lines: Array) -> void:
	for child in technical_box.get_children():
		technical_box.remove_child(child)
		child.queue_free()
	for line in lines:
		var text := str(line)
		if text == "":
			continue
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
		technical_box.add_child(label)
	technical_panel.visible = technical_box.get_child_count() > 0


## Quatre repères fixes permettent de lire l'échelle d'un coup d'œil, sans
## ajouter de texte à la phrase d'explication.
func _build_pips() -> void:
	_pips.clear()
	for index in range(CardPowerTierRules.MAX_TIER):
		var pip := PanelContainer.new()
		pip.name = "Pip%d" % (index + 1)
		pip.custom_minimum_size = Vector2(16, 16)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
		_pips.append(pip)


func _refresh_pips(tier: int) -> void:
	for index in range(_pips.size()):
		_pips[index].add_theme_stylebox_override("panel", _pip_style(index < tier))


## Toutes les séquences déjà vues du niveau restent accessibles : un niveau
## peut avoir une présentation au lancement et une conclusion à la victoire.
## Sans relancer le combat, la relecture ne consomme pas l'état « vu ».
func _refresh_replay() -> void:
	_replay_sequence_ids.clear()
	var replayable := StoryService.replayable_sequences_for_node(_node_id)
	replay_button.visible = not replayable.is_empty()
	if not replay_button.visible:
		return
	for value in replayable:
		if value is Dictionary:
			_replay_sequence_ids.append(str((value as Dictionary).get("id", "")))
	if _replay_sequence_ids.size() == 1:
		replay_button.text = "REVOIR : %s" % str(
			(replayable[0] as Dictionary).get("title", "")).to_upper()
	else:
		replay_button.text = "REVOIR LE SCÉNARIO"


func _on_replay() -> void:
	if _replay_sequence_ids.is_empty():
		return
	launch_button.release_focus()
	replay_button.release_focus()
	replay_requested.emit(_replay_sequence_ids.duplicate())


func show_error(message: String) -> void:
	error_label.text = message
	error_label.visible = message != ""


func _on_launch() -> void:
	if launch_button.disabled or _node_id == "":
		return
	launch_requested.emit(_node_id)


static func _type_color(node_type: String) -> Color:
	match node_type:
		CampaignNode.TYPE_TUTORIAL:
			return UITheme.COL_CAMPAIGN_TUTORIAL
		CampaignNode.TYPE_MINI_BOSS:
			return UITheme.COL_CAMPAIGN_MINIBOSS
		CampaignNode.TYPE_BOSS:
			return UITheme.COL_CAMPAIGN_BOSS
	return UITheme.COL_TEXT_DIM


func _apply_chip(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_stylebox_override("normal", _chip_style(color))


static func _chip_style(color: Color) -> StyleBoxFlat:
	var style := UITheme.panel_style(UITheme.COL_TAB_IDLE, color.darkened(0.35), 2, 10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	return style


## Chaque bloc reçoit son propre contour et une barre latérale colorée : les
## trois informations ne se lisent plus comme une seule liste de texte.
func _style_info_card(panel: PanelContainer, accent: Color) -> void:
	var style := UITheme.panel_style(UITheme.COL_TAB_IDLE, accent.darkened(0.3), 2, 12)
	style.border_width_left = 5
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	style.shadow_size = 3
	panel.add_theme_stylebox_override("panel", style)


static func _pip_style(filled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	if filled:
		style.bg_color = UITheme.COL_ACCENT_LIGHT
	else:
		style.bg_color = Color.TRANSPARENT
		style.border_color = UITheme.COL_BORDER
		style.set_border_width_all(2)
	return style
