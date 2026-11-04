## Accueil principal : pseudo, identité du jeu et lancement d'un combat.
extends Control

@onready var profile_button: Button = $Content/Header/ProfileButton
@onready var play_button: Button = $Content/Hero/Identity/PlayButton
@onready var deck_status: Label = $Content/Hero/Identity/DeckStatus
@onready var background: MenuBackground = $Background
@onready var portrait_area: Control = $Content/Hero/PortraitArea
@onready var emblem: Control = $Content/Hero/PortraitArea/Emblem
@onready var identity_panel: Control = $Content/Hero/Identity
@onready var god_portrait: TextureRect = $Content/Hero/PortraitArea/Emblem/GodPortrait
@onready var god_name: Label = $Content/Hero/Identity/GodName
@onready var god_title: Label = $Content/Hero/Identity/GodTitle
@onready var god_family: Label = $Content/Hero/Identity/GodFamily
@onready var art_warmup: VBoxContainer = $Content/Hero/Identity/ArtWarmup
@onready var art_warmup_label: Label = $Content/Hero/Identity/ArtWarmup/Label
@onready var art_warmup_bar: ProgressBar = $Content/Hero/Identity/ArtWarmup/Progress


func _ready() -> void:
	profile_button.pressed.connect(_on_profile_pressed)
	play_button.pressed.connect(_on_play_pressed)
	CardArtCache.warmup_progress.connect(_on_art_warmup_progress)
	CardArtCache.warmup_finished.connect(_on_art_warmup_finished)
	portrait_area.offset_bottom = -UITheme.HOME_IDENTITY_HEIGHT
	identity_panel.offset_top = -UITheme.HOME_IDENTITY_HEIGHT
	portrait_area.resized.connect(_fit_portrait)
	_fit_portrait.call_deferred()
	_refresh()
	CardArtCache.preload_god_portraits()


func _fit_portrait() -> void:
	var portrait_height := clampf(portrait_area.size.y - 80.0,
		UITheme.HOME_PORTRAIT_MIN_HEIGHT, UITheme.HOME_PORTRAIT_MAX_HEIGHT)
	emblem.offset_top = -portrait_height * 0.5
	emblem.offset_bottom = portrait_height * 0.5


func _refresh() -> void:
	profile_button.text = "%s\nProfil & statistiques" % PlayerData.player_name
	var deck := PlayerData.get_active_deck()
	var count := deck.size()
	var cost := DeckRules.deck_cost(deck)
	var god := StoneLoader.get_god(PlayerData.player_god_id)
	background.set_god(god)
	var portrait_path := str(god.get("asset", ""))
	god_portrait.texture = load(portrait_path) as Texture2D if portrait_path != "" else null
	god_name.text = str(god.get("name", "Dieu")).to_upper()
	god_title.text = str(god.get("title", "")).capitalize()
	god_family.text = str(god.get("family_name", ""))
	god_family.add_theme_color_override("font_color", Color(str(god.get("color", "#e9e1d1"))))
	god_title.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	deck_status.text = "Deck %d • %d/%d cartes • %s/%d points" % [
		PlayerData.get_selected_deck() + 1, count, DeckRules.DECK_SIZE,
		UIFormat.cost(cost), DeckRules.DECK_BUDGET
	]
	if DeckRules.is_deck_valid(deck, PlayerData.player_god_id):
		play_button.text = "JOUER"
		deck_status.add_theme_color_override("font_color", UITheme.COL_TEXT)
	else:
		play_button.text = "COMPLÉTER MON DECK"
		deck_status.add_theme_color_override("font_color", UITheme.COL_WARNING)
	CardArtCache.activate_god(PlayerData.player_god_id, 1, deck)
	var progress := CardArtCache.progress_for_god(PlayerData.player_god_id)
	_on_art_warmup_progress(PlayerData.player_god_id, progress.x, progress.y)


func _on_art_warmup_progress(god_id: String, loaded: int, total: int) -> void:
	if god_id != PlayerData.player_god_id:
		return
	art_warmup.visible = total > 0 and loaded < total
	art_warmup_bar.max_value = maxi(1, total)
	art_warmup_bar.value = loaded
	art_warmup_label.text = "PRÉPARATION DES ILLUSTRATIONS  %d/%d" % [loaded, total]


func _on_art_warmup_finished(god_id: String) -> void:
	if god_id == PlayerData.player_god_id:
		art_warmup.visible = false


func _on_play_pressed() -> void:
	if DeckRules.is_deck_valid(PlayerData.get_active_deck(), PlayerData.player_god_id):
		get_tree().change_scene_to_file("res://scenes/menus/EncounterSelect.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/menus/CollectionScreen.tscn")


func _notification(what: int) -> void:
	# Le retour Android quitte l'application depuis l'accueil ; les autres
	# écrans l'interceptent avant d'arriver ici.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


func _on_profile_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/Stats.tscn")
