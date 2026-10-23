## PreBattleController.gd
## Écran de transition avant le combat.
## Affiche "Duel contre X" et anime un tirage pile/face qui décide du premier joueur.
extends Control

@onready var npc_label: Label = $VBoxCenter/NPCLabel
@onready var gods_label: Label = $VBoxCenter/GodsLabel
@onready var coin: Panel = $VBoxCenter/Coin
@onready var coin_label: Label = $VBoxCenter/Coin/CoinLabel
@onready var coin_flip_label: Label = $VBoxCenter/CoinFlipLabel
@onready var start_button: Button = $VBoxCenter/StartButton

const FACE_PLAYER := "TOI"
const FACE_NPC := "LUI"


func _ready() -> void:
	start_button.pressed.connect(_on_start)

	var npc := StoneLoader.get_npc(BattleContext.selected_npc_id)
	npc_label.text = npc.get("name", "???")
	var human_god := StoneLoader.get_god(PlayerData.player_god_id)
	var npc_god := StoneLoader.get_god(str(npc.get("god_id", "")))
	gods_label.text = "%s • %s  VS  %s • %s" % [
		str(human_god.get("name", "?")).to_upper(), str(human_god.get("family_name", "")).to_upper(),
		str(npc_god.get("name", "?")).to_upper(), str(npc_god.get("family_name", "")).to_upper()
	]

	coin_flip_label.text = ""
	start_button.disabled = true
	## Styliser la pièce une fois sa taille connue (pour un cercle exact).
	coin.resized.connect(_style_coin)
	_style_coin.call_deferred()

	## Lancer l'animation de pièce
	_animate_coin_flip()


## Donne à la pièce une forme de cercle parfait : le rayon de coin = la moitié
## du plus petit côté. Ainsi la pièce reste ronde quelle que soit sa taille.
func _style_coin() -> void:
	var radius: int = int(min(coin.size.x, coin.size.y) * 0.5)
	if radius <= 0:
		radius = 120  ## valeur de repli si la taille n'est pas encore connue
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#c8a050")
	sb.border_color = Color("#f0d88a")
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(radius)
	coin.add_theme_stylebox_override("panel", sb)
	coin_label.add_theme_color_override("font_color", Color("#2a1a0e"))


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
		tween.tween_callback(func(): coin_label.text = FACE_PLAYER if show_player else FACE_NPC)
		## Écraser puis réétirer pour simuler la rotation
		tween.tween_property(coin, "scale:x", 0.1, 0.09)
		tween.tween_property(coin, "scale:x", 1.0, 0.09)

	## Résultat final
	tween.tween_callback(func(): _finish_flip(player_starts))


func _finish_flip(player_starts: bool) -> void:
	coin_label.text = FACE_PLAYER if player_starts else FACE_NPC
	var npc := StoneLoader.get_npc(BattleContext.selected_npc_id)
	var npc_name: String = npc.get("name", "L'adversaire")
	coin_flip_label.text = "Tu commences !" if player_starts else "%s commence !" % npc_name
	## Mémoriser qui commence pour que la partie respecte ce tirage
	BattleContext.forced_first_player = GameState.PLAYER_HUMAN if player_starts else GameState.PLAYER_AI
	start_button.disabled = false


func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/game/Board.tscn")
