## Barre de navigation persistante des cinq écrans principaux.
class_name BottomNav
extends PanelContainer

const Routes := preload("res://scripts/ui/GameRoutes.gd")
const QuestServiceModel := preload("res://scripts/application/quests/QuestService.gd")
const Calendar := preload("res://scripts/domain/quests/QuestCalendar.gd")

enum Tab { SHOP, CARDS, PLAY, QUESTS, RULES }

const QUESTS_TAB := 3
const RULES_TAB := 4

@export var current_tab: Tab = Tab.PLAY
var _read_day: Callable = Calendar.today
var _badge_day := -1
var _refreshing_badge := false

@onready var _buttons: Array[Button] = [
	$Tabs/ShopButton,
	$Tabs/CardsButton,
	$Tabs/PlayButton,
	$Tabs/QuestsButton,
	$Tabs/RulesButton
]

const SCENES: Array[String] = Routes.MAIN_MENUS

const ICONS: Array[Texture2D] = [preload("res://assets/ui/nav-shop.svg"),
	preload("res://assets/ui/nav-decks.svg"),
	preload("res://assets/ui/nav-play.svg"),
	preload("res://assets/ui/nav-quests.svg"),
	preload("res://assets/ui/nav-rules.svg")]


func _ready() -> void:
	for index in range(_buttons.size()):
		_add_tab_content(_buttons[index], index)
		_buttons[index].pressed.connect(_on_tab_pressed.bind(index))
		_apply_tab_style(_buttons[index], index == current_tab)
	if not get_parent().get_meta("menu_preview", false):
		register_story_anchors()
		_refresh_badge()
	PlayerData.quests_changed.connect(_refresh_badge)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_check_badge_day)
	add_child(timer)


func menu_page_activated() -> void:
	_refresh_badge()


func _notification(what: int) -> void:
	if (what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED) \
			and is_node_ready():
		_check_badge_day()


func _check_badge_day() -> void:
	if not get_parent().get_meta("menu_preview", false) and int(_read_day.call()) != _badge_day:
		_refresh_badge()


func register_story_anchors() -> void:
	StoryService.register_anchor("nav.shop", _buttons[0])
	StoryService.register_anchor("nav.deck", _buttons[1])
	StoryService.register_anchor("nav.home", _buttons[2])
	StoryService.register_anchor("nav.quests", _buttons[QUESTS_TAB])
	StoryService.register_anchor("nav.rules", _buttons[RULES_TAB])


func _add_tab_content(button: Button, index: int) -> void:
	var caption := button.text
	button.text = ""
	button.accessibility_name = caption
	button.tooltip_text = caption
	var content := VBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_top = 12
	content.offset_bottom = -10
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 4)
	var icon := TextureRect.new()
	icon.texture = ICONS[index]
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(0, 54)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(icon)
	var label := Label.new()
	label.name = "Caption"
	label.text = caption
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	content.add_child(label)
	if index == QUESTS_TAB:
		_add_badge(button)


## Pastille des récompenses prêtes à récolter. Elle compte les paliers, pas les
## quêtes : une quête à trois paliers peut donc en annoncer trois.
func _add_badge(button: Button) -> void:
	var badge := PanelContainer.new()
	badge.name = "Badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.COL_ACCENT, UITheme.COL_ACCENT_LIGHT, 2, 20))
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.offset_left = -62.0
	badge.offset_top = 4.0
	badge.offset_right = -4.0
	badge.offset_bottom = 46.0
	badge.visible = false
	var label := Label.new()
	label.name = "Count"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", UITheme.COL_INK)
	badge.add_child(label)
	button.add_child(badge)


func _refresh_badge() -> void:
	if _refreshing_badge or get_parent().get_meta("menu_preview", false):
		return
	var badge := _buttons[QUESTS_TAB].get_node_or_null("Badge") as PanelContainer
	if badge == null:
		return
	var day := int(_read_day.call())
	_refreshing_badge = true
	var view := QuestServiceModel.new().view(day)
	_refreshing_badge = false
	if bool(view["ok"]):
		_badge_day = day
	var count := int(view["claimable"])
	badge.visible = count > 0
	var label := badge.get_node_or_null("Count") as Label
	if label != null:
		label.text = "99+" if count > 99 else str(count)


func _apply_tab_style(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override("normal", UITheme.nav_tab_style(selected))
	button.add_theme_stylebox_override("hover", UITheme.nav_tab_style(selected, true))
	button.add_theme_stylebox_override("pressed", UITheme.nav_tab_style(true, true))
	button.add_theme_color_override("font_color", UITheme.COL_ACCENT_LIGHT if selected else UITheme.COL_TEXT_DIM)
	button.get_node("Content/Caption").add_theme_color_override("font_color",
		UITheme.COL_ACCENT_LIGHT if selected else UITheme.COL_TEXT_DIM)


func _on_tab_pressed(index: int) -> void:
	if index == current_tab:
		return
	Routes.go(get_tree(), SCENES[index])
