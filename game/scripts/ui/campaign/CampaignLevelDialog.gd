## CampaignLevelDialog.gd
## Fiche d'un niveau. Elle affiche la synthèse fournie par le service et émet
## seulement une demande de lancement : elle ne calcule ni déverrouillage ni
## adversaire et ne touche jamais à la progression.
class_name CampaignLevelDialog
extends Control

signal launch_requested(node_id: String)
signal replay_requested(sequence_id: String)
signal closed

@onready var backdrop: Button = $Backdrop
@onready var close_button: Button = $Panel/Margin/Content/Header/CloseButton
@onready var name_label: Label = $Panel/Margin/Content/NameLabel
@onready var type_label: Label = $Panel/Margin/Content/TypeLabel
@onready var chapter_label: Label = $Panel/Margin/Content/ChapterLabel
@onready var opponent_label: Label = $Panel/Margin/Content/Details/OpponentLabel
@onready var mode_label: Label = $Panel/Margin/Content/Details/ModeLabel
@onready var tier_label: Label = $Panel/Margin/Content/Details/TierLabel
@onready var ai_label: Label = $Panel/Margin/Content/Details/AiLabel
@onready var deck_label: Label = $Panel/Margin/Content/Details/DeckLabel
@onready var series_label: Label = $Panel/Margin/Content/Details/SeriesLabel
@onready var tutorial_label: Label = $Panel/Margin/Content/TutorialLabel
@onready var replay_button: Button = $Panel/Margin/Content/ReplayButton
@onready var error_label: Label = $Panel/Margin/Content/ErrorLabel
@onready var launch_button: Button = $Panel/Margin/Content/LaunchButton

var _node_id: String = ""
var _state: int = 0
var _replay_sequence_id: String = ""


func _ready() -> void:
	backdrop.pressed.connect(close)
	close_button.pressed.connect(close)
	launch_button.pressed.connect(_on_launch)
	replay_button.pressed.connect(_on_replay)


func open(summary: Dictionary, state: int) -> void:
	if summary.is_empty():
		return
	_node_id = str(summary.get("id", ""))
	_state = state
	name_label.text = str(summary.get("name", "")).to_upper()
	type_label.text = str(summary.get("type_label", ""))
	chapter_label.text = str(summary.get("chapter", "")).to_upper()
	opponent_label.text = "Adversaire : %s" % str(summary.get("opponent_label", ""))
	mode_label.text = "Mode : %s" % str(summary.get("mode_label", ""))
	tier_label.text = str(summary.get("tier_label", ""))
	ai_label.text = "IA : %s" % str(summary.get("ai_label", ""))
	deck_label.text = str(summary.get("deck_label", ""))
	series_label.text = str(summary.get("series_label", ""))
	var tutorial_id := str(summary.get("tutorial_id", ""))
	tutorial_label.visible = tutorial_id != ""
	tutorial_label.text = "Tutoriel prévu : %s" % tutorial_id
	_refresh_replay()
	var accent := Color(str(summary.get("accent", UITheme.COL_NEON_PINK.to_html())))
	name_label.add_theme_color_override("font_color", accent)
	launch_button.disabled = state == 0
	launch_button.text = "REJOUER" if state == 2 else "AFFRONTER"
	error_label.visible = false
	visible = true
	launch_button.grab_focus()


func close() -> void:
	if not visible:
		return
	# Le bouton qui a ouvert le dialogue ne doit pas recevoir le relâchement du
	# dernier geste de lecture, sinon il peut relancer le niveau.
	launch_button.release_focus()
	replay_button.release_focus()
	visible = false
	closed.emit()


## Une séquence déjà vue reste accessible depuis la fiche, sans relancer le
## niveau ni consommer l'état « vu » une seconde fois.
func _refresh_replay() -> void:
	_replay_sequence_id = ""
	var replayable := StoryService.replayable_sequences_for_node(_node_id)
	replay_button.visible = not replayable.is_empty()
	if not replay_button.visible:
		return
	var entry: Dictionary = replayable[0]
	_replay_sequence_id = str(entry.get("id", ""))
	replay_button.text = "REVOIR : %s" % str(entry.get("title", "")).to_upper()


func _on_replay() -> void:
	if _replay_sequence_id != "":
		launch_button.release_focus()
		replay_button.release_focus()
		replay_requested.emit(_replay_sequence_id)


func show_error(message: String) -> void:
	error_label.text = message
	error_label.visible = message != ""


func _on_launch() -> void:
	if launch_button.disabled or _node_id == "":
		return
	launch_requested.emit(_node_id)
