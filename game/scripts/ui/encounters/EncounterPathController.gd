## EncounterPathController.gd
## Choix du niveau d'une rencontre : chemin serpentin du dieu (ou de
## Pr.Stone), sélection d'un rond, puis lancement du combat. Les états
## viennent d'EncounterPath : une victoire débloque le niveau suivant.
extends Control

const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const EncounterPathModel := preload("res://scripts/domain/EncounterPath.gd")
const PathTrackView := preload("res://scripts/ui/encounters/PathTrack.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")


@onready var background: MenuBackground = $Background
@onready var back_button: Button = $Root/Header/BackButton
@onready var scroll: ScrollContainer = $Root/Scroll
@onready var track: PathTrackView = $Root/Scroll/Track
@onready var footer: PanelContainer = $Root/Footer
@onready var portrait: GodPortrait = $Root/Footer/Content/Identity/Portrait
@onready var god_name: Label = $Root/Footer/Content/Identity/Texts/GodName
@onready var god_family: Label = $Root/Footer/Content/Identity/Texts/GodFamily
@onready var level_label: Label = $Root/Footer/Content/Identity/Texts/LevelLabel
@onready var progress_label: Label = $Root/Footer/Content/Identity/Texts/ProgressLabel
@onready var fight_button: Button = $Root/Footer/Content/FightButton

var _source_id := ""
var _source: Dictionary = {}
var _path: Array = []
var _selected_index := 0


func _ready() -> void:
	back_button.pressed.connect(_go_back)
	fight_button.pressed.connect(_on_fight)
	track.level_selected.connect(_select_level)
	_source_id = BattleContext.navigation_source_id()
	_source = OpponentCatalogModel.source_for(_source_id)
	if _source.is_empty() or OpponentCatalogModel.levels_for(_source_id).is_empty():
		push_error("EncounterPath: source de rencontre inconnue '%s'." % _source_id)
		_return_to_select.call_deferred()
		return
	_apply_identity()
	_reload_path()
	_selected_index = EncounterPathModel.current_index(_path)
	_refresh()
	_center_selection.call_deferred()


func _apply_identity() -> void:
	background.set_god(_source)
	var color := Color(str(_source.get("color", UITheme.COL_NEON_PINK.to_html())))
	portrait.visible = str(_source.get("asset", "")) != ""
	portrait.setup(_source)
	god_name.text = str(_source.get("name", "Adversaire")).to_upper()
	god_name.add_theme_color_override("font_color", color)
	god_family.text = str(_source.get("family_name", ""))
	god_family.add_theme_color_override("font_color", color)
	footer.add_theme_stylebox_override("panel", _footer_style(color))


func _footer_style(color: Color) -> StyleBoxFlat:
	var style := UITheme.panel_style(UITheme.COL_PANEL_BG, color.darkened(0.10), 3, 18)
	style.content_margin_left = UITheme.GAP_MEDIUM
	style.content_margin_right = UITheme.GAP_MEDIUM
	style.content_margin_top = UITheme.GAP_SMALL
	style.content_margin_bottom = UITheme.GAP_SMALL
	return style


## Recalcule les états depuis les statistiques déjà sauvegardées : aucune
## nouvelle donnée n'est nécessaire pour savoir quels niveaux sont terminés.
func _reload_path() -> void:
	_path = EncounterPathModel.states(
		OpponentCatalogModel.levels_for(_source_id), PlayerData.is_npc_beaten)
	if track.node_count() == 0:
		track.setup(_path, _source)
	else:
		track.set_path(_path)


func _refresh() -> void:
	if _path.is_empty():
		return
	_selected_index = clampi(_selected_index, 0, _path.size() - 1)
	var level: Dictionary = _path[_selected_index]
	track.set_selected(_selected_index)
	level_label.text = "%s • %s %s" % [
		str(level.get("bracket_label", "")),
		OpponentCatalogModel.stars_text(int(level.get("stars", 0))),
		str(level.get("difficulty_label", "")),
	]
	progress_label.text = "%d / %d niveaux terminés" % [
		EncounterPathModel.completed_count(_path), _path.size(),
	]
	fight_button.disabled = not bool(level.get("playable", false))


func _select_level(index: int) -> void:
	if index < 0 or index >= _path.size():
		return
	if int(_path[index].get("state", EncounterPathModel.State.LOCKED)) \
			== EncounterPathModel.State.LOCKED:
		return
	if index == _selected_index:
		return
	_selected_index = index
	_refresh()


## L'adversaire correspond exactement au niveau sélectionné. Cette méthode
## reste séparée du changement de scène pour être vérifiée par les tests.
func _build_opponent() -> Dictionary:
	if _path.is_empty():
		return {}
	var level: Dictionary = _path[_selected_index]
	return OpponentCatalogModel.build_for_source(
		_source_id, str(level.get("bracket_id", "")), str(level.get("difficulty_id", "")))


func _on_fight() -> void:
	var opponent := _build_opponent()
	if opponent.is_empty():
		push_error("EncounterPath: adversaire impossible à générer.")
		return
	BattleContext.select_source(_source_id)
	BattleContext.select_opponent(opponent)
	BattleContext.forced_first_player = 0
	Routes.go(get_tree(), Routes.PRE_BATTLE)


func _center_selection() -> void:
	var node := track.node_for(_selected_index)
	if node != null:
		scroll.ensure_control_visible(node)


func _go_back() -> void:
	Routes.go(get_tree(), Routes.ENCOUNTER_SELECT)


func _return_to_select() -> void:
	Routes.go(get_tree(), Routes.ENCOUNTER_SELECT)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()
