## BattleHUD.gd
## Barre d'information du combat : deux plaques fixes (toi / adversaire) avec
## nom + score, un "VS" central, et un surlignage doré sur le joueur actif.
##
## Principe anti-débordement : chaque plaque a une TAILLE FIXE et son texte est
## centré + clippé. Changer un texte (score, tour) ne décale donc jamais rien.
class_name BattleHUD
extends PanelContainer

const COL_PLATE_BG := Color("#1a120a")
const COL_HUMAN := Color("#3a7ad0")
const COL_AI := Color("#d04040")
const COL_IDLE := Color("#4a3a22")
const COL_ACTIVE := Color("#ffe060")   ## surlignage du joueur actif
const COL_NAME := Color("#e8dcc0")
const COL_SCORE := Color("#ffe9a8")

var _human_plate: PanelContainer
var _ai_plate: PanelContainer
var _human_name: Label
var _ai_name: Label
var _human_score: Label
var _ai_score: Label
var _center: Label        ## symbole central : flèche directionnelle ou "VS"
var _banner: Label        ## bandeau de tour sous les plaques
var _human_display_name: String = "TOI"
var _ai_display_name: String = "Adversaire"


func _ready() -> void:
	## Rendre le fond du conteneur HUD transparent : seules les plaques doivent
	## être visibles (sinon le panneau du thème s'afficherait derrière).
	var transparent := StyleBoxEmpty.new()
	add_theme_stylebox_override("panel", transparent)
	_build()


func _build() -> void:
	## Conteneur vertical : [ ligne des plaques ] au-dessus de [ bandeau de tour ]
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_SMALL)
	add_child(col)

	## Ligne horizontale : plaque gauche | flèche/VS | plaque droite
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_MEDIUM)
	col.add_child(row)

	var human := _make_plate(COL_HUMAN)
	_human_plate = human["plate"]
	_human_name = human["name"]
	_human_score = human["score"]
	row.add_child(_human_plate)

	## Symbole central, zone fixe. Affiche une flèche vers le joueur actif.
	_center = Label.new()
	_center.text = "VS"
	_center.custom_minimum_size = Vector2(90, 0)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center.add_theme_font_size_override("font_size", 56)
	_center.add_theme_color_override("font_color", Color("#c8a060"))
	row.add_child(_center)

	var ai := _make_plate(COL_AI)
	_ai_plate = ai["plate"]
	_ai_name = ai["name"]
	_ai_score = ai["score"]
	row.add_child(_ai_plate)

	## Bandeau de tour : un petit cadre à fond noir, centré, bien lisible.
	var banner_box := CenterContainer.new()
	col.add_child(banner_box)

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
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", UITheme.FONT_BANNER)
	_banner.add_theme_color_override("font_color", COL_ACTIVE)
	banner_panel.add_child(_banner)


## Crée une plaque (nom au-dessus, score en gros en dessous), de taille fixe.
## accent_color : la couleur du camp (bleu joueur / rouge IA).
func _make_plate(accent_color: Color) -> Dictionary:
	var plate := PanelContainer.new()
	plate.custom_minimum_size = Vector2(0, 150)
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.add_theme_stylebox_override("panel", _plate_style(accent_color, false))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	plate.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.clip_text = true
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	name_lbl.add_theme_color_override("font_color", COL_NAME)
	vbox.add_child(name_lbl)

	var score_lbl := Label.new()
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.add_theme_font_size_override("font_size", UITheme.FONT_SCORE)
	score_lbl.add_theme_color_override("font_color", COL_SCORE)
	score_lbl.text = "0"
	vbox.add_child(score_lbl)

	return { "plate": plate, "name": name_lbl, "score": score_lbl }


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

## Définit les noms affichés (le nom adverse sera clippé s'il est trop long).
func set_names(human_name: String, ai_name: String) -> void:
	_human_display_name = human_name
	_ai_display_name = ai_name
	_human_name.text = human_name
	_ai_name.text = ai_name


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
		_banner.text = "À toi de jouer"
	else:
		_banner.text = "Tour de %s" % _ai_display_name
