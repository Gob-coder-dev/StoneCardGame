## SeriesResultCard.gd
## Cadre du score d'une série FT2/FT3, partagé par la campagne et le PVP. Il ne
## décide de rien : il affiche la vue préparée par SeriesResultPresenter.
class_name SeriesResultCard
extends PanelContainer


var _header_label: Label
var _score_label: Label
var _caption_label: Label
var _note_label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(0.075, 0.062, 0.086, 0.94), UITheme.COL_GOLD, 2, 18))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	_header_label = _make_label(20, UITheme.COL_TEXT_DIM)
	_header_label.text = "SÉRIE"
	_score_label = _make_label(38, UITheme.COL_TEXT)
	_caption_label = _make_label(24, UITheme.COL_TEXT_DIM)
	_note_label = _make_label(20, UITheme.COL_WARNING)
	column.add_child(_header_label)
	column.add_child(_score_label)
	column.add_child(_caption_label)
	column.add_child(_note_label)
	visible = false


static func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func show_view(view: Dictionary) -> void:
	_score_label.text = str(view.get("score", ""))
	_caption_label.text = str(view.get("caption", ""))
	_note_label.text = str(view.get("note", ""))
	_note_label.visible = _note_label.text != ""
	visible = true


func hide_view() -> void:
	visible = false
