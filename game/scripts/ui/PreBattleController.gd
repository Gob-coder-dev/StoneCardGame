## PreBattleController.gd
## Écran de transition avant le combat.
## Affiche "Duel contre X" et anime un tirage pile/face qui décide du premier joueur.
extends Control

@onready var npc_label: Label = $VBoxCenter/NPCLabel
@onready var difficulty_label: Label = $VBoxCenter/DifficultyLabel
@onready var player_god_portrait: GodPortrait = $VBoxCenter/GodDuel/PlayerGod/Portrait
@onready var player_god_name: Label = $VBoxCenter/GodDuel/PlayerGod/Name
@onready var player_god_family: Label = $VBoxCenter/GodDuel/PlayerGod/Family
@onready var opponent_god_portrait: GodPortrait = $VBoxCenter/GodDuel/OpponentGod/Portrait
@onready var opponent_god_name: Label = $VBoxCenter/GodDuel/OpponentGod/Name
@onready var opponent_god_family: Label = $VBoxCenter/GodDuel/OpponentGod/Family
@onready var coin: Panel = $VBoxCenter/GodDuel/Coin
@onready var coin_label: Label = $VBoxCenter/GodDuel/Coin/CoinLabel
@onready var coin_flip_label: Label = $VBoxCenter/CoinFlipLabel
@onready var start_button: Button = $VBoxCenter/StartButton

const FACE_PLAYER := "TOI"
const FACE_NPC := "LUI"


func _ready() -> void:
	start_button.pressed.connect(_on_start)

	var npc := BattleContext.current_opponent()
	npc_label.text = npc.get("name", "???")
	difficulty_label.text = _opponent_subtitle(npc)
	var human_god := StoneLoader.get_god(PlayerData.player_god_id)
	var npc_god := StoneLoader.get_god(str(npc.get("god_id", "")))
	_setup_god_identity(player_god_portrait, player_god_name, player_god_family,
		human_god, "TOI • %s" % str(human_god.get("name", "?")))
	_setup_god_identity(opponent_god_portrait, opponent_god_name, opponent_god_family,
		npc_god, "LUI • %s" % str(npc_god.get("name", "?")))

	coin_flip_label.text = ""
	start_button.disabled = true
	## Styliser la pièce une fois sa taille connue (pour un cercle exact).
	coin.resized.connect(_style_coin)
	_style_coin.call_deferred()

	## Lancer l'animation de pièce
	_animate_coin_flip()


func _setup_god_identity(portrait: GodPortrait, name_label: Label, family_label: Label,
		god: Dictionary, display_name: String) -> void:
	portrait.setup(god)
	name_label.text = display_name
	family_label.text = str(god.get("family_name", ""))
	family_label.add_theme_color_override(
		"font_color", Color(str(god.get("color", UITheme.COL_TEXT.to_html())))
	)


## Les adversaires générés précisent leur palier et leur difficulté ; les
## adversaires historiques de npcs.json n'ont pas ces champs.
func _opponent_subtitle(npc: Dictionary) -> String:
	var bracket_label := str(npc.get("bracket_label", ""))
	var difficulty_label := str(npc.get("difficulty_label", ""))
	var stars := str(npc.get("difficulty_stars_text", ""))
	if bracket_label == "" and difficulty_label == "":
		return ""
	var level_text := difficulty_label
	if stars != "" and difficulty_label != "":
		level_text = "%s %s" % [stars, difficulty_label]
	if bracket_label == "":
		return level_text
	if level_text == "":
		return bracket_label
	return "%s • %s" % [bracket_label, level_text]


## Donne à la pièce une forme de cercle parfait : le rayon de coin = la moitié
## du plus petit côté. Ainsi la pièce reste ronde quelle que soit sa taille.
func _style_coin() -> void:
	var radius: int = int(min(coin.size.x, coin.size.y) * 0.5)
	if radius <= 0:
		radius = 120  ## valeur de repli si la taille n'est pas encore connue
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.COL_ACCENT
	sb.border_color = UITheme.COL_ACCENT_LIGHT
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(radius)
	coin.add_theme_stylebox_override("panel", sb)
	coin_label.add_theme_color_override("font_color", UITheme.COL_INK)


## Animation : la pièce "tourne" (écrase/étire horizontalement) plusieurs fois,
## alterne les faces, puis s'arrête sur le résultat tiré par le moteur.
func _animate_coin_flip() -> void:
	var player_starts := BoardSetupGenerator.draw_first_player() == GameState.PLAYER_HUMAN

	coin.pivot_offset = coin.size * 0.5

	var tween := create_tween()
	var flips := 8
	for i in range(flips):
		## Alterner l'affichage de face à chaque demi-tour
		var show_player := (i % 2 == 0)
		tween.tween_callback(_show_coin_face.bind(show_player))
		## Écraser puis réétirer pour simuler la rotation
		tween.tween_property(coin, "scale:x", 0.1, 0.09)
		tween.tween_property(coin, "scale:x", 1.0, 0.09)

	## Résultat final
	tween.tween_callback(func(): _finish_flip(player_starts))


func _finish_flip(player_starts: bool) -> void:
	_show_coin_face(player_starts)
	var npc := BattleContext.current_opponent()
	var npc_name: String = npc.get("name", "L'adversaire")
	coin_flip_label.text = "Tu commences !" if player_starts else "%s commence !" % npc_name
	## Mémoriser qui commence pour que la partie respecte ce tirage
	BattleContext.forced_first_player = GameState.PLAYER_HUMAN if player_starts else GameState.PLAYER_AI
	start_button.disabled = false


func _show_coin_face(show_player: bool) -> void:
	coin_label.text = FACE_PLAYER if show_player else FACE_NPC
	player_god_portrait.set_emphasized(show_player)
	opponent_god_portrait.set_emphasized(not show_player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _go_back() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/LevelSelect.tscn")


func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/game/Board.tscn")
