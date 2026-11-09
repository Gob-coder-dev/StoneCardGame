## PreBattleController.gd
## Écran de transition avant le combat.
## Affiche "Duel contre X" et anime un tirage pile/face qui décide du premier
## joueur. En PVP local, le tirage a déjà été fait par l'hôte : l'écran le
## révèle sans consommer de hasard, pour que les deux appareils annoncent le
## même premier joueur.
extends Control

const SessionLink := preload("res://scripts/network/LanSessionLink.gd")
const CoordinatorModel := preload("res://scripts/network/LanMatchCoordinator.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")

@onready var duel_label: Label = $VBoxCenter/DuelLabel
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
@onready var status_label: Label = $VBoxCenter/StatusLabel
@onready var start_button: Button = $VBoxCenter/StartButton
@onready var background: MenuBackground = $Background

const FACE_PLAYER := "TOI"
const FACE_NPC := "LUI"

var _link: LanSessionLink = null
## En PVP, le plateau ne s'ouvre qu'une fois les deux téléphones d'accord.
var _start_link: LanMatchCoordinator = null
var _remote_ready := false
var _leaving := false
var _start_timeout: Timer = null


func _ready() -> void:
	start_button.pressed.connect(_on_start)
	if _is_pvp():
		_setup_pvp()
	else:
		_setup_campaign()

	coin_flip_label.text = ""
	status_label.text = ""
	start_button.disabled = true
	if _is_pvp():
		_open_start_link()
		_start_timeout = Timer.new()
		_start_timeout.name = "StartAgreementTimeout"
		_start_timeout.one_shot = true
		_start_timeout.timeout.connect(_on_start_timeout)
		add_child(_start_timeout)
	## Garder le cadre de la pièce rond, quelle que soit sa taille.
	coin.resized.connect(_style_coin)
	_style_coin.call_deferred()

	## Lancer l'animation de pièce
	_animate_coin_flip()


func _is_pvp() -> bool:
	return PvpMatchContext.is_active()


## ─── Campagne ────────────────────────────────────────────────────────────────

func _setup_campaign() -> void:
	var npc := BattleContext.current_opponent()
	npc_label.text = UIFormat.combatant_name(str(
		npc.get("combatant_name", npc.get("name", "Adversaire"))), 24)
	difficulty_label.visible = true
	difficulty_label.text = _opponent_subtitle(npc)
	var human_id := BattleContext.effective_player_god_id()
	var npc_id := BattleContext.effective_opponent_god_id()
	var human_identity := GodIdentityModel.player(human_id)
	var npc_identity := GodIdentityModel.bot(npc_id)
	var npc_is_godless := StoneLoader.get_god(npc_id).is_empty()
	background.set_gods(human_identity, npc_identity)
	_setup_god_identity(player_god_portrait, player_god_name, player_god_family,
		human_identity, "TOI • %s" % str(human_identity.get("name", "Sans dieu")))
	var npc_god_label := "Sans dieu" if npc_is_godless else str(npc_identity.get("name", "?"))
	_setup_god_identity(opponent_god_portrait, opponent_god_name, opponent_god_family,
		npc_identity, "LUI • %s" % npc_god_label)


## ─── PVP local ───────────────────────────────────────────────────────────────

## Les deux camps viennent du salon : mêmes pseudos et mêmes dieux que sur le
## téléphone d'en face, et surtout le même premier joueur tiré par l'hôte.
func _setup_pvp() -> void:
	duel_label.text = "Duel local contre"
	npc_label.text = PvpMatchContext.remote_name if PvpMatchContext.remote_name != "" \
		else "Adversaire"
	difficulty_label.text = "PVP"
	difficulty_label.visible = true
	var local_identity := GodIdentityModel.player(PvpMatchContext.local_god_id)
	var remote_identity := GodIdentityModel.player(PvpMatchContext.remote_god_id)
	background.set_gods(local_identity, remote_identity)
	_setup_god_identity(player_god_portrait, player_god_name, player_god_family,
		local_identity, "TOI • %s" % str(local_identity.get("name", "Sans dieu")))
	_setup_god_identity(opponent_god_portrait, opponent_god_name, opponent_god_family,
		remote_identity, "LUI • %s" % str(remote_identity.get("name", "Sans dieu")))


func _setup_god_identity(portrait: GodPortrait, name_label: Label, family_label: Label,
		god: Dictionary, display_name: String, family_name_override: String = "") -> void:
	portrait.setup(god)
	name_label.text = display_name
	family_label.text = family_name_override if family_name_override != "" \
		else str(god.get("family_name", ""))
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
	sb.bg_color = Color("#35282b")
	sb.border_color = Color("#b77451")
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(radius)
	coin.add_theme_stylebox_override("panel", sb)
	coin_label.add_theme_color_override("font_color", Color("#f1d8c4"))


## Le premier joueur ne change qu'ici : la campagne tire au sort, le PVP lit le
## tirage déjà transmis par l'hôte et le mémorise pour le moteur.
func _starting_player() -> int:
	if _is_pvp():
		return PvpMatchContext.starting_player
	var drawn := BoardSetupGenerator.draw_first_player()
	BattleContext.forced_first_player = drawn
	return drawn


## Le camp de cet appareil : l'hôte ou le client en PVP, l'humain en campagne.
## La pièce parle toujours au joueur local, jamais au camp de l'hôte : sinon
## les deux téléphones annoncent la même face et personne ne sait qui commence.
func _local_side() -> int:
	if _is_pvp():
		return PvpMatchContext.local_side
	return GameState.PLAYER_HUMAN


## Animation : la pièce "tourne" (écrase/étire horizontalement) plusieurs fois,
## alterne les faces, puis s'arrête sur le résultat tiré par le moteur.
func _animate_coin_flip() -> void:
	var player_starts := _starting_player() == _local_side()

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
	coin_flip_label.text = "Tu commences !" if player_starts \
		else "%s commence !" % _opponent_name()
	start_button.disabled = false
	if _remote_ready:
		status_label.text = "L'adversaire est prêt. Touchez COMMENCER."


func _opponent_name() -> String:
	if _is_pvp():
		return PvpMatchContext.remote_name if PvpMatchContext.remote_name != "" \
			else "L'adversaire"
	var opponent := BattleContext.current_opponent()
	return UIFormat.combatant_name(str(
		opponent.get("combatant_name", opponent.get("name", "L'adversaire"))), 18)


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


## Le retour retrouve le chemin du dieu affronté, pour choisir un autre niveau
## sans repasser par la grille. En PVP, il rend la main au salon en fermant la
## session réseau, sinon deux téléphones resteraient attachés à un match mort.
func _go_back() -> void:
	if _is_pvp():
		_leaving = true
		_close_start_link()
		PvpMatchContext.clear()
		LanSession.leave_with_notice("Partie annulée avant le premier coup.")
		Routes.go(get_tree(), Routes.PVP_LOBBY)
		return
	if BattleContext.has_campaign_node():
		BattleContext.clear_campaign_node()
		Routes.go(get_tree(), Routes.CAMPAIGN_MAP)
		return
	BattleContext.select_source(BattleContext.navigation_source_id())
	Routes.go(get_tree(), Routes.ENCOUNTER_PATH)


func _on_start() -> void:
	if _leaving:
		return
	if _is_pvp() and _start_link != null:
		_request_start()
		return
	_open_board()


## ─── Lancement négocié en PVP ────────────────────────────────────────────────

## Le coordinateur ne sert qu'à la poignée de main : après le feu vert de
## l'hôte, le plateau créera le sien, comme pour la revanche.
func _open_start_link() -> void:
	if not LanSession.is_online():
		set_status("Session locale : le plateau s'ouvre directement.")
		return
	var is_host := PvpMatchContext.local_side == GameState.PLAYER_ONE
	var client_peer := PvpMatchContext.peer_of_side(GameState.PLAYER_TWO) if is_host else 0
	_link = SessionLink.new()
	_link.attach(LanSession)
	_start_link = CoordinatorModel.new()
	_start_link.attach(_link, PvpMatchContext.match_id, is_host,
		PvpMatchContext.local_side, client_peer)
	_start_link.enable_start(PvpMatchContext.config())
	_start_link.start_pending.connect(_on_start_pending)
	_start_link.match_ready.connect(_on_match_ready)
	_start_link.aborted.connect(_on_start_aborted)


## Chacun doit toucher COMMENCER : le premier qui appuie attend l'autre, et
## c'est l'hôte qui donne le départ aux deux appareils en même temps.
func _request_start() -> void:
	if not _start_link.request_start():
		_open_board()
		return
	start_button.disabled = true
	status_label.text = "En attente de l'adversaire…"
	if _start_timeout != null:
		_start_timeout.start(LanProtocol.START_AGREEMENT_TIMEOUT_SECONDS)


func _on_start_pending() -> void:
	if start_button.disabled:
		## La pièce tourne encore : le message s'affichera à son atterrissage.
		_remote_ready = true
		return
	status_label.text = "L'adversaire est prêt. Touchez COMMENCER."


func _on_match_ready(_config: Dictionary) -> void:
	if _start_timeout != null:
		_start_timeout.stop()
	_open_board()


func _on_start_aborted(message: String) -> void:
	if _start_timeout != null:
		_start_timeout.stop()
	status_label.text = message
	start_button.disabled = true


func _on_start_timeout() -> void:
	if _leaving or _start_link == null:
		return
	status_label.text = "L'adversaire n'a pas confirmé le lancement. Revenez au salon."
	start_button.disabled = true
	_start_link.abort(status_label.text)


func set_status(message: String) -> void:
	status_label.text = message


func _open_board() -> void:
	if _leaving:
		return
	_leaving = true
	_close_start_link()
	if _is_pvp():
		PvpMatchContext.set_presence(LanPvpPresence.IN_MATCH)
	Routes.go(get_tree(), Routes.BOARD)


func _close_start_link() -> void:
	if _start_timeout != null:
		_start_timeout.stop()
	if _start_link != null:
		_start_link.close()
		_start_link = null
	if _link != null:
		_link.detach()
		_link = null


func _exit_tree() -> void:
	_close_start_link()
