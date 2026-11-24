## Livret de règles paginé. Les libellés de modes et de pouvoirs sont partagés avec le jeu.
extends Control

enum Tab { BASICS, MODES, POWERS, DECKS }

const Routes := preload("res://scripts/ui/GameRoutes.gd")
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")
const PowerHelp := preload("res://scripts/ui/PowerHelp.gd")
const TouchButton := preload("res://scripts/ui/input/TouchButton.gd")
const TAB_NAMES := ["Bases", "Modes", "Pouvoirs", "Decks"]
const DemoPlayback := preload("res://scripts/ui/RulesDemoPlayback.gd")
const CardGrid := preload("res://scripts/ui/collection/CardGridLayout.gd")

@onready var tabs: HBoxContainer = $Content/Tabs
@onready var god_tabs: GridContainer = $Content/GodTabs
@onready var scroll: ScrollContainer = $Content/Scroll
@onready var page: VBoxContainer = $Content/Scroll/ReadingMargin/Page
@onready var background: MenuBackground = $Background

var _active_tab := Tab.BASICS
var _god_id := ""
@onready var _demos := DemoPlayback.new()


func _ready() -> void:
	add_child(_demos)
	_demos.setup(scroll, page)
	background.set_god(GodIdentityModel.player(PlayerData.player_god_id))
	var tab_group := ButtonGroup.new()
	for index in range(TAB_NAMES.size()):
		var button := _tab_button(TAB_NAMES[index], tab_group)
		_style_main_tab(button)
		tabs.add_child(button)
		button.pressed.connect(_select_tab.bind(index))
	var god_group := ButtonGroup.new()
	if not MonsterLoader.get_god(PlayerData.player_god_id).is_empty():
		_god_id = PlayerData.player_god_id
	else:
		_god_id = MonsterLoader.default_god_id()
	for god in MonsterLoader.get_all_gods():
		var id := str(god["id"])
		var button := _tab_button(str(god["name"]), god_group)
		god_tabs.add_child(button)
		button.pressed.connect(_select_god.bind(id))
		if id == _god_id:
			button.set_pressed_no_signal(true)
	_select_tab(Tab.BASICS)


func menu_page_deactivated() -> void:
	_demos.suspend()


func menu_page_activated() -> void:
	_demos.resume()


func _select_tab(tab: Tab) -> void:
	_active_tab = tab
	for index in range(tabs.get_child_count()):
		tabs.get_child(index).set_pressed_no_signal(index == tab)
	god_tabs.visible = tab == Tab.POWERS
	_show_page()


func _select_god(god_id: String) -> void:
	_god_id = god_id
	_show_page()


func _show_page() -> void:
	_demos.clear()
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	scroll.scroll_vertical = 0
	match _active_tab:
		Tab.BASICS: _show_basics()
		Tab.MODES: _show_modes()
		Tab.POWERS: _show_powers()
		Tab.DECKS: _show_decks()


func _show_basics() -> void:
	_add_rule("Pose un monstre",
		"À ton tour, choisis une carte de ta main et pose-la sur une case libre. Le premier joueur est tiré au sort.")
	_demos.add_clip("basics_place")
	_add_rule("Compare les faces",
		"Seule la carte posée attaque. Au contact, compare son attaque à la défense de l’ennemi sur les faces "
		+ "qui se touchent. Une attaque supérieure capture la cible, "
		+ "qui rejoint ton camp. À égalité, le défenseur tient.")
	_demos.add_clip("basics_compare")
	_add_rule("Lis le plateau",
		"Le plateau fait généralement %d × %d. Une croix marque une case bloquée. "
		% [GameState.BOARD_SIZE, GameState.BOARD_SIZE]
		+ "Les cases bleues sont à toi, les rouges sont à l’adversaire. "
		+ "Les lames servent à attaquer et à défendre. Les boucliers servent à défendre.")
	_demos.add_clip("basics_board")
	_add_rule("Fin de manche",
		"Quand toutes les cases jouables sont pleines, le camp qui contrôle le plus de monstres gagne. "
		+ "Si les deux camps en contrôlent autant, la manche est nulle.")


func _show_modes() -> void:
	for mode in GameModeRules.MODES:
		_add_rule(GameModeRules.mode_label(mode), GameModeRules.mode_description(mode))
	_add_rule("Campagne et duel local",
		"En campagne, tu affrontes l’IA. En duel local, deux appareils jouent sur le même réseau Wi-Fi.")
	_add_rule("Format et puissance",
		"FT1 se joue en une manche. En FT2 ou FT3, le premier à gagner 2 ou 3 manches remporte la série. "
		+ "Une manche nulle rapporte 0 victoire.\n\n"
		+ "Le palier de puissance limite les cartes disponibles en Decks aléatoires, Même deck et Choix de cartes.")


func _show_powers() -> void:
	var god := MonsterLoader.get_god(_god_id)
	if god.is_empty():
		return
	var tint := Color(str(god["color"]))
	var heading := Label.new()
	heading.text = str(god["family_name"])
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_font_size_override("font_size", UITheme.FONT_SUBTITLE)
	heading.add_theme_color_override("font_color", tint.lightened(0.2))
	page.add_child(heading)
	for kind in PowerHelp.BY_GOD.get(_god_id, []):
		var badge := PowerHelp.make_badge(kind, tint, 0, 76.0)
		_add_rule(PowerHelp.title(kind), PowerHelp.description(kind), badge)
		_demos.add_clip("horizon" if kind == "long" else kind)


func _show_decks() -> void:
	_add_rule("Compose ton deck",
		"Choisis %d cartes neutres ou de la famille de ton dieu, pour %d points maximum. "
		% [DeckRules.DECK_SIZE, DeckRules.DECK_BUDGET]
		+ "Chaque lignée occupe une seule place, même si tu possèdes plusieurs formes. "
		+ "Chaque dieu a trois decks sauvegardés automatiquement.")
	_add_rule("Lis une carte",
		"Le cadre indique la famille. Le liseré indique la rareté. Chaque face accueille jusqu’à %d symboles. "
		% BattleMonster.MAX_MARKERS_PER_SIDE
		+ "Les pictogrammes en haut de la carte signalent ses pouvoirs.", null,
		_card_examples("RarityExamples",
			["avortons_des_caves_n1", "charognard_courbe_n1", "mille_gueules_n1", "le_voyeur_n1"],
			["Commune", "Rare", "Épique", "Légendaire"], true))
	_add_rule("Débloque les formes",
		"La première copie débloque le niveau 1. Améliore la carte avec des copies supplémentaires et des âmes. "
		+ "Une commune peut atteindre le niveau 4, une rare le niveau 3 et une épique le niveau 2. "
		+ "Une légendaire a une seule forme.", null,
		_card_examples("LevelExamples",
			["charognard_courbe_n1", "charognard_courbe_n2", "charognard_courbe_n3"],
			["Niveau 1", "Niveau 2", "Niveau 3"]))
	_add_rule("Choisis la forme jouée",
		"Le filtre de niveau change l’aperçu de la collection. Dans la fiche, consulte les formes avec les boutons "
		+ "numérotés. « Utiliser » équipe la forme affichée si tu l’as débloquée et que ton deck respecte le budget.")


func _card_examples(group_name: String, ids: Array[String], captions: Array[String],
		show_rarity_colors: bool = false) -> HBoxContainer:
	var row := CardGrid.make_card_row()
	row.name = group_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(ids.size()):
		var monster := MonsterLoader.get_monster(ids[index])
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(column)
		var card := MonsterCard.new()
		card.setup(monster)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.resized.connect(func(): card.custom_minimum_size.y = card.size.x)
		column.add_child(card)
		var caption := Label.new()
		caption.text = captions[index]
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.clip_text = true
		caption.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		if show_rarity_colors:
			caption.add_theme_color_override("font_color", UITheme.rarity_color(str(monster["rarity"])))
		column.add_child(caption)
	return row


func _add_rule(title: String, description: String, badge: Control = null, examples: Control = null) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UITheme.GAP_SMALL)
	panel.add_child(row)
	if badge != null:
		row.add_child(badge)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	row.add_child(content)
	var heading := Label.new()
	heading.text = title
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_color_override("font_color", UITheme.COL_ACCENT_LIGHT)
	heading.add_theme_font_size_override("font_size", UITheme.FONT_SUBTITLE)
	content.add_child(heading)
	var body := RichTextLabel.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.fit_content = true
	body.scroll_active = false
	body.bbcode_enabled = true
	body.add_theme_font_size_override("normal_font_size", UITheme.FONT_BODY)
	body.add_theme_font_size_override("bold_font_size", UITheme.FONT_BODY)
	body.text = description
	content.add_child(body)
	if examples != null:
		content.add_child(examples)
	page.add_child(panel)


func _tab_button(caption: String, group: ButtonGroup) -> Button:
	var button := TouchButton.new()
	button.text = caption
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 96.0
	button.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	button.add_theme_stylebox_override("normal", UITheme.nav_tab_style(false))
	button.add_theme_stylebox_override("hover", UITheme.nav_tab_style(false, true))
	button.add_theme_stylebox_override("pressed", UITheme.nav_tab_style(true))
	button.add_theme_stylebox_override("hover_pressed", UITheme.nav_tab_style(true, true))
	button.add_theme_color_override("font_pressed_color", UITheme.COL_ACCENT_LIGHT)
	return button


func _style_main_tab(button: Button) -> void:
	button.custom_minimum_size.y = 112.0
	button.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	button.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	button.add_theme_color_override("font_pressed_color", UITheme.COL_TEXT)
	button.add_theme_color_override("font_hover_pressed_color", UITheme.COL_TEXT)
	var idle := StyleBoxFlat.new()
	idle.bg_color = UITheme.COL_TAB_IDLE
	idle.set_content_margin_all(4.0)
	var selected := idle.duplicate() as StyleBoxFlat
	selected.bg_color = UITheme.COL_SELECTED.lightened(0.13)
	selected.border_color = UITheme.COL_ACCENT_LIGHT
	selected.border_width_bottom = 6
	var hover := idle.duplicate() as StyleBoxFlat
	hover.bg_color = UITheme.COL_SURFACE
	button.add_theme_stylebox_override("normal", idle)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", selected)
	button.add_theme_stylebox_override("hover_pressed", selected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not get_meta("menu_preview", false):
		if MenuNavigation.cancel_for_back():
			return
		_go_back()


func _go_back() -> void:
	Routes.go(get_tree(), Routes.MAIN_MENU)
