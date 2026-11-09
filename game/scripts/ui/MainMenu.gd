## Accueil principal : pseudo, identité du jeu et accès aux deux modes.
extends Control

const Routes := preload("res://scripts/ui/GameRoutes.gd")

## Destination de chaque mode, après validation du deck.
const MODE_SCENES: Dictionary = {
	"campaign": Routes.CAMPAIGN_MAP,
	"pvp": Routes.PVP_LOBBY,
}
const DECK_WARNING: String = "VEUILLEZ COMPLÉTER VOTRE DECK"

@onready var profile_button: Button = $Content/Header/ProfileButton
@onready var mode_buttons: HBoxContainer = $Content/Hero/Identity/ModeButtons
@onready var campaign_button: Button = $Content/Hero/Identity/ModeButtons/CampaignButton
@onready var pvp_button: Button = $Content/Hero/Identity/ModeButtons/PvpButton
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
@onready var deck_warning_overlay: Control = $DeckWarningOverlay
@onready var deck_warning_message: Label = \
	$DeckWarningOverlay/Center/Panel/Content/Message
@onready var complete_deck_button: Button = \
	$DeckWarningOverlay/Center/Panel/Content/Actions/CompleteDeckButton
@onready var close_warning_button: Button = \
	$DeckWarningOverlay/Center/Panel/Content/Actions/CloseButton

## Navigation injectable : les tests vérifient la destination réelle sans
## changer de scène. Vide en jeu, la scène est alors ouverte normalement.
var scene_changer: Callable = Callable()


func _ready() -> void:
	profile_button.pressed.connect(_on_profile_pressed)
	campaign_button.pressed.connect(_on_mode_pressed.bind("campaign"))
	pvp_button.pressed.connect(_on_mode_pressed.bind("pvp"))
	complete_deck_button.pressed.connect(_open_collection)
	close_warning_button.pressed.connect(_close_deck_warning)
	CardArtCache.warmup_progress.connect(_on_art_warmup_progress)
	CardArtCache.warmup_finished.connect(_on_art_warmup_finished)
	portrait_area.offset_bottom = -UITheme.HOME_IDENTITY_HEIGHT
	identity_panel.offset_top = -UITheme.HOME_IDENTITY_HEIGHT - UITheme.HOME_IDENTITY_LIFT
	identity_panel.offset_bottom = -UITheme.HOME_IDENTITY_LIFT
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
	var god := StoneLoader.get_god(PlayerData.player_god_id)
	background.set_god(god)
	var portrait_path := str(god.get("asset", ""))
	god_portrait.texture = load(portrait_path) as Texture2D if portrait_path != "" else null
	god_name.text = (str(god.get("name", "Dieu")) if not god.is_empty() else "Sans dieu").to_upper()
	god_title.text = str(god.get("title", "")).capitalize() if not god.is_empty() else "Deck neutre"
	god_family.text = str(god.get("family_name", "")) if not god.is_empty() else "Pierres neutres"
	god_family.add_theme_color_override("font_color", Color(str(god.get("color", "#e9e1d1"))))
	god_title.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	_restore_deck_status()
	var deck := PlayerData.get_active_deck()
	CardArtCache.activate_god(PlayerData.player_god_id, 1, deck)
	var progress := CardArtCache.progress_for_god(PlayerData.player_god_id)
	_on_art_warmup_progress(PlayerData.player_god_id, progress.x, progress.y)


## État normal du deck : texte recalculé depuis le profil, jamais depuis une
## chaîne mémorisée. Un ancien minuteur ne peut donc pas restaurer un texte
## obsolète après plusieurs clics rapides.
func _restore_deck_status() -> void:
	var deck := PlayerData.get_active_deck()
	deck_status.text = "Deck %d • %d/%d cartes • %s/%d points" % [
		PlayerData.get_selected_deck() + 1, deck.size(), DeckRules.DECK_SIZE,
		UIFormat.cost(DeckRules.deck_cost(deck)), DeckRules.DECK_BUDGET
	]
	deck_status.add_theme_color_override("font_color", UITheme.COL_TEXT)


## Condition unique, partagée par les deux modes.
func _deck_is_ready(mode: String = "") -> bool:
	var deck := PlayerData.get_active_deck()
	if DeckRules.is_deck_valid(deck, PlayerData.player_god_id):
		return true
	# Exception d'amorçage unique : le tout premier tutoriel est conçu pour les
	# cinq cartes du profil neuf. Le PVP et tous les autres niveaux restent à 8.
	if mode == "campaign" and PlayerData.player_god_id == "" and deck.size() >= 5:
		var service := CampaignContext.get_service()
		return service.is_ready() and not service.is_completed("tuto_01")
	return false


func _on_mode_pressed(mode: String) -> void:
	if not _deck_is_ready(mode):
		_show_deck_warning()
		return
	_go_to(str(MODE_SCENES[mode]))


func _show_deck_warning() -> void:
	var deck := PlayerData.get_active_deck()
	deck_warning_message.text = "%s\n\nVotre deck contient %d carte%s sur %d. Complétez-le avant de lancer une campagne ou une partie PVP." % [
		DECK_WARNING, deck.size(), "s" if deck.size() > 1 else "", DeckRules.DECK_SIZE
	]
	deck_warning_overlay.visible = true
	complete_deck_button.grab_focus()


func _close_deck_warning() -> void:
	deck_warning_overlay.visible = false
	campaign_button.grab_focus()


func _open_collection() -> void:
	deck_warning_overlay.visible = false
	_go_to(Routes.COLLECTION)


func _unhandled_input(event: InputEvent) -> void:
	if deck_warning_overlay.visible and event.is_action_pressed("ui_cancel"):
		_close_deck_warning()
		get_viewport().set_input_as_handled()


func _go_to(path: String) -> void:
	if scene_changer.is_valid():
		scene_changer.call(path)
		return
	Routes.go(get_tree(), path)


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


func _notification(what: int) -> void:
	# Le retour Android quitte l'application depuis l'accueil ; les autres
	# écrans l'interceptent avant d'arriver ici.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


func _on_profile_pressed() -> void:
	Routes.go(get_tree(), Routes.STATS)
