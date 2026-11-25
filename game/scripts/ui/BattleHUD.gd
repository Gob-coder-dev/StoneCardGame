## BattleHUD.gd
## Barre du combat : identité, aide divine, score et indication du tour.
##
## Les noms restent centrés et clippés pour garder des plaques de même largeur.
class_name BattleHUD
extends PanelContainer

signal god_help_requested(god_id: String, anchor: Button)

const PowerHelp := preload("res://scripts/ui/PowerHelp.gd")
const PowerHelpPopover := preload("res://scripts/ui/PowerHelpPopover.gd")
const TouchButtonModel := preload("res://scripts/ui/input/TouchButton.gd")
const COL_PLATE_BG := Color("#1a120a")
const COL_HUMAN := Color("#3a7ad0")
const COL_AI := Color("#d04040")
const COL_ACTIVE := Color("#ffe060")   ## surlignage du joueur actif
const COL_NAME := Color("#e8dcc0")
const COL_SCORE := Color("#ffe9a8")

var _human_plate: PanelContainer
var _ai_plate: PanelContainer
var _human_name: Button
var _ai_name: Button
var _name_dialog: AcceptDialog
var _name_opener: Button
var _human_god: Label
var _ai_god: Label
var _human_portrait: GodPortrait
var _ai_portrait: GodPortrait
var _human_help: Button
var _ai_help: Button
var _human_god_id := ""
var _ai_god_id := ""
var _human_score: Label
var _ai_score: Label
var _center: Label        ## symbole central : flèche directionnelle ou "VS"
var _banner: Label        ## bandeau de tour sous les plaques
var _ai_display_name: String = "Adversaire"
var _turn_message := ""


func _ready() -> void:
	## Rendre le fond du conteneur HUD transparent : seules les plaques doivent
	## être visibles (sinon le panneau du thème s'afficherait derrière).
	var transparent := StyleBoxEmpty.new()
	add_theme_stylebox_override("panel", transparent)
	_build()
	_name_dialog = AcceptDialog.new()
	_name_dialog.title = "Combattant"
	_name_dialog.ok_button_text = "Fermer"
	_name_dialog.dialog_autowrap = true
	_name_dialog.visibility_changed.connect(_restore_name_focus)
	add_child(_name_dialog)


func _build() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_SMALL)
	add_child(col)
	col.add_child(_build_plate_row())
	col.add_child(_build_banner())


func _build_plate_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_MEDIUM)
	var human := _make_plate(COL_HUMAN, false)
	_assign_plate(human, true)
	row.add_child(_human_plate)
	row.add_child(_build_center_label())
	var ai := _make_plate(COL_AI, true)
	_assign_plate(ai, false)
	row.add_child(_ai_plate)
	return row


func _assign_plate(parts: Dictionary, human: bool) -> void:
	if human:
		_human_plate = parts["plate"]
		_human_name = parts["name"]
		_human_god = parts["god"]
		_human_portrait = parts["portrait"]
		_human_score = parts["score"]
		_human_help = parts["help"]
		_human_help.pressed.connect(func(): god_help_requested.emit(_human_god_id, _human_help))
	else:
		_ai_plate = parts["plate"]
		_ai_name = parts["name"]
		_ai_god = parts["god"]
		_ai_portrait = parts["portrait"]
		_ai_score = parts["score"]
		_ai_help = parts["help"]
		_ai_help.pressed.connect(func(): god_help_requested.emit(_ai_god_id, _ai_help))


func _build_center_label() -> Label:
	_center = Label.new()
	_center.text = "VS"
	_center.custom_minimum_size = Vector2(UITheme.HUD_CENTER_WIDTH, 0)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center.add_theme_font_size_override("font_size", UITheme.FONT_HUD_CENTER)
	_center.add_theme_color_override("font_color", Color("#c8a060"))
	return _center


func _build_banner() -> CenterContainer:
	var banner_box := CenterContainer.new()
	var banner_panel := PanelContainer.new()
	var banner_sb := StyleBoxFlat.new()
	banner_sb.bg_color = Color("#0a0603")
	banner_sb.border_color = COL_ACTIVE
	banner_sb.set_border_width_all(2)
	banner_sb.set_corner_radius_all(10)
	banner_sb.content_margin_left = 32.0
	banner_sb.content_margin_right = 32.0
	banner_sb.content_margin_top = 10.0
	banner_sb.content_margin_bottom = 10.0
	banner_panel.add_theme_stylebox_override("panel", banner_sb)
	banner_box.add_child(banner_panel)

	_banner = Label.new()
	_banner.clip_text = true
	_banner.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_banner.custom_minimum_size.x = UITheme.HUD_BANNER_WIDTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", UITheme.FONT_BANNER)
	_banner.add_theme_color_override("font_color", COL_ACTIVE)
	banner_panel.add_child(_banner)
	return banner_box


## Crée une plaque (nom au-dessus, score en gros en dessous), de taille fixe.
## accent_color : la couleur du camp (bleu joueur / rouge IA).
func _make_plate(accent_color: Color, portrait_on_right: bool) -> Dictionary:
	var plate := PanelContainer.new()
	plate.custom_minimum_size = Vector2(0, UITheme.HUD_PLATE_HEIGHT)
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.add_theme_stylebox_override("panel", _plate_style(accent_color, false))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	plate.add_child(row)

	var portrait := GodPortrait.new()
	portrait.custom_minimum_size = UITheme.GOD_HUD_PORTRAIT_SIZE
	var help := PowerHelpPopover.make_button()
	help.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	help.hide()
	var god_column := VBoxContainer.new()
	god_column.alignment = BoxContainer.ALIGNMENT_CENTER
	god_column.add_theme_constant_override("separation", 4)
	god_column.add_child(portrait)
	god_column.add_child(help)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 0)
	if portrait_on_right:
		row.add_child(vbox)
		row.add_child(god_column)
	else:
		row.add_child(god_column)
		row.add_child(vbox)

	var name_button: Button = TouchButtonModel.new()
	name_button.clip_text = true
	name_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_button.custom_minimum_size.y = 38
	name_button.add_theme_font_size_override("font_size", 25)
	name_button.add_theme_color_override("font_color", COL_NAME)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		name_button.add_theme_stylebox_override(state, empty)
	name_button.pressed.connect(_show_name.bind(name_button))
	vbox.add_child(name_button)

	var god_lbl := Label.new()
	god_lbl.clip_text = true
	god_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	god_lbl.add_theme_font_size_override("font_size", 25)
	vbox.add_child(god_lbl)

	var score_lbl := Label.new()
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.add_theme_font_size_override("font_size", 50)
	score_lbl.add_theme_color_override("font_color", COL_SCORE)
	score_lbl.text = "0"
	vbox.add_child(score_lbl)

	return {"plate": plate, "name": name_button, "god": god_lbl,
		"portrait": portrait, "score": score_lbl, "help": help}


func _plate_style(accent_color: Color, active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PLATE_BG
	sb.border_color = COL_ACTIVE if active else accent_color
	sb.set_border_width_all(8 if active else 3)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb


## ─── API publique ─────────────────────────────────────────────────────────────

## Les plaques affichent un nom compact et conservent l'identité complète.
func set_names(human_name: String, ai_name: String) -> void:
	_set_name(_human_name, human_name)
	_set_name(_ai_name, ai_name)
	_ai_display_name = _ai_name.text


func _set_name(button: Button, combatant: String) -> void:
	var full_name := combatant.strip_edges()
	if full_name.is_empty():
		full_name = "Adversaire"
	button.text = UIFormat.truncate(full_name, 18)
	button.tooltip_text = full_name
	button.accessibility_name = full_name


func _show_name(button: Button) -> void:
	_name_opener = button
	_name_dialog.dialog_text = button.accessibility_name
	_name_dialog.popup_centered(Vector2i(500, 160))


func _restore_name_focus() -> void:
	if not _name_dialog.visible and is_instance_valid(_name_opener):
		_name_opener.grab_focus.call_deferred()
		_name_opener = null


## Les portraits et noms de dieux sont séparés des noms des combattants : les
## plaques restent lisibles même lorsque l'adversaire possède un long nom.
func set_gods(human_god: Dictionary, ai_god: Dictionary) -> void:
	_human_god_id = str(human_god.get("id", ""))
	_ai_god_id = str(ai_god.get("id", ""))
	_human_help.visible = PowerHelp.BY_GOD.has(_human_god_id)
	_ai_help.visible = PowerHelp.BY_GOD.has(_ai_god_id)
	_human_portrait.setup(human_god)
	_ai_portrait.setup(ai_god)
	_human_god.text = str(human_god.get("name", "Dieu"))
	_ai_god.text = str(ai_god.get("name", "Sans dieu"))
	_human_god.add_theme_color_override(
		"font_color", Color(str(human_god.get("color", UITheme.COL_TEXT.to_html())))
	)
	_ai_god.add_theme_color_override(
		"font_color", Color(str(ai_god.get("color", UITheme.COL_TEXT.to_html())))
	)


func set_scores(human_score: int, ai_score: int) -> void:
	_human_score.text = str(human_score)
	_ai_score.text = str(ai_score)


## Illumine la plaque du joueur actif, oriente la flèche centrale vers lui,
## et met à jour le bandeau de tour.
func set_active_player(player: int) -> void:
	var human_active := player == GameState.PLAYER_HUMAN
	## Plaques : bordure dorée sur l'actif.
	_human_plate.add_theme_stylebox_override("panel", _plate_style(COL_HUMAN, human_active))
	_ai_plate.add_theme_stylebox_override("panel", _plate_style(COL_AI, not human_active))
	## Flèche centrale : pointe vers la plaque active (◄ gauche / ► droite).
	_center.text = "◄" if human_active else "►"
	## Bandeau de tour : texte court centré.
	if human_active:
		_turn_message = "À toi de jouer"
	else:
		_turn_message = "Tour de %s" % _ai_display_name
	clear_move_feedback()


func show_move_feedback(message: String) -> void:
	_banner.text = message
	_banner.add_theme_font_size_override("font_size", 28)
	_banner.add_theme_color_override("font_color", UITheme.COL_ERROR)


func clear_move_feedback() -> void:
	_banner.text = _turn_message
	_banner.add_theme_font_size_override("font_size", UITheme.FONT_BANNER)
	_banner.add_theme_color_override("font_color", COL_ACTIVE)


## Fin de partie : plus aucun joueur n'est actif pendant le passage au résultat.
func set_game_over() -> void:
	_human_plate.add_theme_stylebox_override("panel", _plate_style(COL_HUMAN, false))
	_ai_plate.add_theme_stylebox_override("panel", _plate_style(COL_AI, false))
	_center.text = "VS"
	_turn_message = "Partie terminée"
	clear_move_feedback()
