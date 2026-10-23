## Accueil principal : pseudo, identité du jeu et lancement d'un combat.
extends Control

@onready var profile_button: Button = $Content/Header/ProfileButton
@onready var play_button: Button = $Content/Hero/PlayButton
@onready var deck_status: Label = $Content/Hero/DeckStatus


func _ready() -> void:
	profile_button.pressed.connect(_on_profile_pressed)
	play_button.pressed.connect(_on_play_pressed)
	_refresh()


func _refresh() -> void:
	profile_button.text = "PROFIL  •  %s" % PlayerData.player_name
	var count := PlayerData.player_deck.size()
	var cost := DeckRules.deck_cost(PlayerData.player_deck)
	var god := StoneLoader.get_god(PlayerData.player_god_id)
	deck_status.text = "%s • %d/%d pierres • %s/%d points" % [
		god.get("name", "Dieu"), count, DeckRules.DECK_SIZE,
		UIFormat.cost(cost), DeckRules.DECK_BUDGET
	]
	if DeckRules.is_deck_valid(PlayerData.player_deck, PlayerData.player_god_id):
		play_button.text = "⚔  JOUER"
		deck_status.add_theme_color_override("font_color", Color("#b9dc82"))
	else:
		play_button.text = "COMPLÉTER MON DECK"
		deck_status.add_theme_color_override("font_color", Color("#f0b060"))


func _on_play_pressed() -> void:
	if DeckRules.is_deck_valid(PlayerData.player_deck, PlayerData.player_god_id):
		get_tree().change_scene_to_file("res://scenes/menus/LevelSelect.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/menus/CollectionScreen.tscn")


func _on_profile_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/Stats.tscn")
