## Bouton d'action à deux lignes sans conteneur enfant. Le dessin direct évite
## les boucles de minimum-size provoquées par un VBox ancré dans un Button.
class_name UpgradePriceButton
extends "res://scripts/ui/input/TouchButton.gd"

const SoulIcon: Texture2D = preload("res://assets/ui/soul-placeholder.svg")

@export var title_font_size := 36
@export var price_font_size := 30
@export var soul_icon_size := 38.0

var _display_title := "UTILISER"
var _show_price := false
var _price := 0
var _content_color := UITheme.COL_INK


## Ce bouton valide toujours une action (utiliser, améliorer, confirmer) :
## il ne prend pas le clic de sélection générique.
func _ready() -> void:
	Audio.set_button_sfx(self, AudioCatalog.SFX_BUTTON_2)


func set_content(title: String, show_price: bool, price: int,
		content_color: Color) -> void:
	_display_title = title
	_show_price = show_price
	_price = price
	_content_color = content_color
	# Conservé pour l'accessibilité, tandis que les couleurs transparentes du
	# thème empêchent le libellé natif de se superposer au dessin.
	text = title
	update_minimum_size()
	queue_redraw()


## En disposition compacte, le libellé natif reste disponible pour
## l'accessibilité mais peut être rogné : seul le dessin personnalisé est
## visible et la largeur doit rester celle de la carte qui porte le tiroir.
func set_compact_layout(compact: bool) -> void:
	clip_text = compact
	update_minimum_size()
	queue_redraw()


## État sémantique exposé aux contrôleurs et aux tests sans révéler la
## composition graphique interne du bouton.
func is_price_visible() -> bool:
	return _show_price


func displayed_price() -> int:
	return _price


func soul_icon_texture() -> Texture2D:
	return SoulIcon


## La largeur vient de l'ancre du tiroir. Le texte natif, conservé pour
## l'accessibilité, ne doit pas imposer une largeur invisible supérieure.
func _get_minimum_size() -> Vector2:
	return Vector2.ZERO


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var alpha := 0.52 if disabled else 1.0
	var color := _content_color
	color.a *= alpha
	if not _show_price:
		_draw_centered(font, _display_title, title_font_size, size.y * 0.5, color)
		return
	var title_height := font.get_height(title_font_size)
	var price_height := maxf(soul_icon_size, font.get_height(price_font_size))
	var separation := 2.0
	var block_top := (size.y - title_height - separation - price_height) * 0.5
	_draw_centered(font, _display_title, title_font_size,
		block_top + title_height * 0.5, color)
	var amount := UIFormat.integer(_price)
	var amount_size := font.get_string_size(
		amount, HORIZONTAL_ALIGNMENT_LEFT, -1, price_font_size)
	var gap := 10.0
	var row_width := soul_icon_size + gap + amount_size.x
	var row_left := (size.x - row_width) * 0.5
	var row_top := block_top + title_height + separation
	draw_texture_rect(SoulIcon,
		Rect2(Vector2(row_left, row_top + (price_height - soul_icon_size) * 0.5),
			Vector2.ONE * soul_icon_size), false)
	var baseline := row_top + (price_height - font.get_height(price_font_size)) * 0.5 \
		+ font.get_ascent(price_font_size)
	draw_string(font, Vector2(row_left + soul_icon_size + gap, baseline), amount,
		HORIZONTAL_ALIGNMENT_LEFT, -1, price_font_size, color)


func _draw_centered(font: Font, value: String, font_size: int,
		center_y: float, color: Color) -> void:
	var extent := font.get_string_size(
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center_y - font.get_height(font_size) * 0.5 \
		+ font.get_ascent(font_size)
	draw_string(font, Vector2((size.x - extent.x) * 0.5, baseline), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()
