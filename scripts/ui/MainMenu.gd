## Accueil principal : pseudo, identité du jeu et lancement d'un combat.
extends Control

@onready var profile_button: Button = $Content/Header/ProfileButton
@onready var play_button: Button = $Content/Hero/PlayButton
@onready var deck_status: Label = $Content/Hero/DeckStatus
@onready var god_portrait: TextureRect = $Content/Hero/Emblem/GodPortrait
@onready var god_name: Label = $Content/Hero/GodName
@onready var god_title: Label = $Content/Hero/GodTitle
@onready var god_family: Label = $Content/Hero/GodFamily


func _ready() -> void:
	profile_button.pressed.connect(_on_profile_pressed)
	play_button.pressed.connect(_on_play_pressed)
	resized.connect(_fit_portrait)
	_fit_portrait.call_deferred()
	_refresh()


func _fit_portrait() -> void:
	# Réserve les commandes et la navigation sur les écrans moins hauts.
	$Content/Hero/Emblem.custom_minimum_size.y = clampf(size.y - UITheme.HOME_RESERVED_HEIGHT,
		UITheme.HOME_PORTRAIT_MIN_HEIGHT, UITheme.HOME_PORTRAIT_MAX_HEIGHT)


func _refresh() -> void:
	profile_button.text = "%s\nProfil & statistiques" % PlayerData.player_name
	var deck := PlayerData.get_active_deck()
	var count := deck.size()
	var cost := DeckRules.deck_cost(deck)
	var god := StoneLoader.get_god(PlayerData.player_god_id)
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


func _on_play_pressed() -> void:
	if DeckRules.is_deck_valid(PlayerData.get_active_deck(), PlayerData.player_god_id):
		get_tree().change_scene_to_file("res://scenes/menus/LevelSelect.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/menus/CollectionScreen.tscn")


func _on_profile_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/Stats.tscn")
