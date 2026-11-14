## CampaignNodeView.gd
## Rond d'un nœud de campagne. Il reçoit un nœud déjà résolu et un état de
## progression : aucune règle de déblocage, aucun accès au profil. La forme du
## symbole distingue tutoriel, mini-boss et boss en plus de la couleur.
class_name CampaignNodeView
extends "res://scripts/ui/encounters/PathNodeButton.gd"

const NodeModel := preload("res://scripts/domain/campaign/CampaignNode.gd")
const UnlockRulesModel := preload("res://scripts/domain/campaign/CampaignUnlockRules.gd")

var node_id: String = ""
var state: int = UnlockRulesModel.State.LOCKED
var chosen: bool = false
var node_type: String = NodeModel.TYPE_NORMAL

var _accent := UITheme.COL_NEON_PINK
var _style_key: String = ""


func _ready() -> void:
	text = ""
	clip_text = true
	set_process(false)
	resized.connect(_on_resized)
	# Le parent appelle configure() juste après l'ajout : inutile de construire
	# des styles verrouillés pour les remplacer dans la même frame.


func configure(node: CampaignNode, node_state: int, accent: Color,
		is_chosen: bool = false) -> void:
	visible = true
	node_id = node.id if node != null else ""
	node_type = node.type if node != null else NodeModel.TYPE_NORMAL
	_accent = accent
	chosen = is_chosen
	state = node_state
	tooltip_text = "%s • %s" % [node.name if node != null else "", node.type_label()
		if node != null else ""]
	disabled = state == UnlockRulesModel.State.LOCKED
	_set_pulse(state == UnlockRulesModel.State.AVAILABLE)
	_refresh()


## Prépare le bouton pour le pool de la carte. Aucune animation ni aucun
## traitement ne doit continuer tant que le Control est détaché de la scène.
func recycle() -> void:
	_set_pulse(false)
	node_id = ""
	state = UnlockRulesModel.State.LOCKED
	chosen = false
	disabled = true
	tooltip_text = ""
	_style_key = ""
	visible = false


func set_chosen(value: bool) -> void:
	if chosen == value:
		return
	chosen = value
	_refresh()


func _on_resized() -> void:
	_refresh()


func _refresh() -> void:
	if node_id == "":
		return
	var diameter := maxf(minf(size.x, size.y), float(UITheme.CAMPAIGN_NODE_SIZE) * 0.4)
	var radius := int(diameter * 0.5)
	var key := "%d|%d|%s|%s|%s" % [state, radius, node_type,
		_accent.to_html(), str(chosen)]
	if key == _style_key:
		return
	_style_key = key
	var fill := UITheme.COL_NODE_LOCKED_BG
	var border := UITheme.COL_NODE_LOCKED_BORDER
	var border_width := 3
	match state:
		UnlockRulesModel.State.COMPLETED:
			fill = _accent.darkened(0.55)
			border = _accent
			border_width = 5
		UnlockRulesModel.State.AVAILABLE:
			fill = UITheme.COL_SELECTED
			border = _type_color().lightened(0.12)
			border_width = 4
	if chosen:
		border = UITheme.COL_ACCENT_LIGHT
		border_width += 3
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.06, 0.02, 0.07, 0.55)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 6.0)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = fill.lightened(0.07)
	var pressed_style := style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = fill.darkened(0.12)
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_stylebox_override("hover_pressed", pressed_style)
	add_theme_stylebox_override("disabled", style)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	queue_redraw()


func _type_color() -> Color:
	match node_type:
		NodeModel.TYPE_TUTORIAL:
			return UITheme.COL_CAMPAIGN_TUTORIAL
		NodeModel.TYPE_MINI_BOSS:
			return UITheme.COL_CAMPAIGN_MINIBOSS
		NodeModel.TYPE_BOSS:
			return UITheme.COL_CAMPAIGN_BOSS
	return _accent


## Dessine les symboles sans dépendre d'une police : anneau du niveau ouvert,
## cadenas, coche, livre, losange ou couronne.
func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	var ink := _type_color()
	match state:
		UnlockRulesModel.State.LOCKED:
			_draw_lock(center, radius)
			return
		UnlockRulesModel.State.AVAILABLE:
			var ring := ink
			ring.a = 0.16 + 0.22 * (1.0 - _pulse)
			draw_arc(center, radius + 7.0 + 12.0 * _pulse, 0.0, TAU, 56, ring, 3.0, true)
		UnlockRulesModel.State.COMPLETED:
			_draw_check(center, radius, ink)
			_draw_type_badge(center + Vector2(radius * 0.62, -radius * 0.62), radius, ink)
			return
	_draw_type_glyph(center, radius, ink)


func _draw_type_glyph(center: Vector2, radius: float, ink: Color) -> void:
	match node_type:
		NodeModel.TYPE_TUTORIAL:
			_draw_book(center, radius, ink)
		NodeModel.TYPE_MINI_BOSS:
			_draw_diamond(center, radius * 0.30, ink)
		NodeModel.TYPE_BOSS:
			_draw_crown(center, radius * 0.34, ink)
		_:
			draw_circle(center, radius * 0.11, ink)
			draw_arc(center, radius * 0.24, 0.0, TAU, 24, ink, 2.0, true)


func _draw_type_badge(center: Vector2, radius: float, ink: Color) -> void:
	match node_type:
		NodeModel.TYPE_MINI_BOSS:
			_draw_diamond(center, radius * 0.14, ink)
		NodeModel.TYPE_BOSS:
			_draw_crown(center, radius * 0.16, ink)
		NodeModel.TYPE_TUTORIAL:
			draw_circle(center, radius * 0.07, ink)


func _draw_check(center: Vector2, radius: float, ink: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(-radius * 0.28, radius * 0.02),
		center + Vector2(-radius * 0.08, radius * 0.24),
		center + Vector2(radius * 0.32, -radius * 0.24),
	])
	draw_polyline(points, ink, maxf(4.0, radius * 0.09), true)


func _draw_diamond(center: Vector2, extent: float, ink: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -extent),
		center + Vector2(extent * 0.72, 0.0),
		center + Vector2(0.0, extent),
		center + Vector2(-extent * 0.72, 0.0),
		center + Vector2(0.0, -extent),
	])
	draw_polyline(points, ink, maxf(3.0, extent * 0.22), true)


func _draw_crown(center: Vector2, extent: float, ink: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(-extent, extent * 0.55),
		center + Vector2(-extent * 0.72, -extent * 0.30),
		center + Vector2(-extent * 0.20, extent * 0.10),
		center + Vector2(0.0, -extent * 0.62),
		center + Vector2(extent * 0.20, extent * 0.10),
		center + Vector2(extent * 0.72, -extent * 0.30),
		center + Vector2(extent, extent * 0.55),
		center + Vector2(-extent, extent * 0.55),
	])
	draw_polyline(points, ink, maxf(3.0, extent * 0.18), true)


func _draw_book(center: Vector2, radius: float, ink: Color) -> void:
	var half := radius * 0.28
	var top := center + Vector2(0.0, -radius * 0.22)
	var bottom := center + Vector2(0.0, radius * 0.24)
	draw_line(top, bottom, ink, 3.0, true)
	draw_polyline(PackedVector2Array([
		top + Vector2(-half, radius * 0.04),
		top + Vector2(0.0, -radius * 0.02),
		top + Vector2(half, radius * 0.04),
		bottom + Vector2(half, radius * 0.02),
		bottom,
		bottom + Vector2(-half, radius * 0.02),
		top + Vector2(-half, radius * 0.04),
	]), ink, 3.0, true)
