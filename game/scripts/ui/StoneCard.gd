## StoneCard.gd
## Composant carte réutilisable de SamStone.
## Dessine entièrement une carte par code (_draw) à partir des données d'une pierre :
##   - cadre minéral sombre à la couleur de la famille
##   - lames triangulaires sur les 4 côtés (le nombre = la valeur du côté)
##   - contour extérieur simple indiquant la rareté
##   - illustration PNG, ou indicateur neutre quand l'image manque
##   - bandeau de nom
##
## Si la pierre a un champ "asset" non vide pointant vers une image existante,
## cette image est affichée. Une ressource absente reste explicitement signalée.
##
## Utilisé partout : collection, main, plateau.
class_name StoneCard
extends Control

const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const Symbols := preload("res://scripts/ui/StoneSymbols.gd")

## ─── Signaux ──────────────────────────────────────────────────────────────────
signal card_pressed(stone_id: String)

## ─── Propriétaires (miroir de GameState pour éviter la dépendance dure) ───────
const OWNER_NONE: int = 0
const OWNER_HUMAN: int = 1
const OWNER_AI: int = 2

## ─── Palette ──────────────────────────────────────────────────────────────────
const COL_FRAME_LIGHT := Color("#b4aba0")
const COL_FRAME_EDGE := Color("#383b45")
const COL_BLADE_LIGHT := Color("#ffe9a8")
const COL_RANDOM_BLADE := Symbols.FORTUNE
const COL_LONG_BLADE := Color("#4fa9ff")
const COL_SWARM_BLADE := Color("#83d85d")
const COL_SHIELD := Color("#92e7f2")
const COL_ILLUSTRATION_BG := Color("#151319")
const COL_NAME_BG := Color("#202733")
const COL_NAME_TEXT := UITheme.COL_TEXT

## ─── Données de la pierre ─────────────────────────────────────────────────────
var _stone: Dictionary = {}
var _owner: int = OWNER_NONE
var _selected: bool = false
var _texture: Texture2D = null  ## illustration si disponible
var _asset_path := ""
var _show_cost: bool = false
var _battle_stone: BattleStoneModel = null
var _combat_preview: BattleStoneModel = null
## Pierre sans état de combat, construite une fois depuis le catalogue pour
## dessiner les cartes hors plateau (main, collection, fiches).
var _catalog_preview: BattleStoneModel = null
## Copie des valeurs dessinées de _battle_stone : le moteur modifie la pierre
## sur place, cette copie dit si un rafraîchissement doit la redessiner.
var _drawn_stone_state: Array = []
var _attacking_faces: Dictionary = {}
var _marker_growth: Dictionary = {}
var _visual_weakness_override: int = -1
## Les animations peuvent régler ces valeurs à chaque image : chaque réglage
## ne redessine la carte que si la valeur affichée change réellement.
var attack_regrowth: float = 1.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.15)
		if clamped == attack_regrowth:
			return
		attack_regrowth = clamped
		queue_redraw()
const Gesture := preload("res://scripts/ui/input/TapGesture.gd")
var _tap := Gesture.new()

## ─── Dimensions internes (ratio carte) ───────────────────────────────────────
## La carte occupe tout le rect du Control. On réserve une marge pour les lames.
const BLADE_MARGIN: float = 0.12  ## proportion réservée aux lames sur les bords
var _edge_margin_ratio: float = BLADE_MARGIN
var _marker_scale: float = 1.0
var _power_badge_scale: float = 1.0

## ─── API publique ─────────────────────────────────────────────────────────────

## Configure la carte avec une pierre et un propriétaire.
func _init() -> void:
	# Les cartes restent interactives et laissent les gestes atteindre
	# le ScrollContainer parent, y compris lorsqu'ils débutent sur l'image.
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	CardArtCache.texture_ready.connect(_on_texture_ready)


func setup(stone: Dictionary, owner: int = OWNER_NONE, battle_stone = null) -> void:
	_stone = stone
	_owner = owner
	_battle_stone = battle_stone if battle_stone is BattleStoneModel else null
	_drawn_stone_state = _stone_state(_battle_stone)
	_catalog_preview = null
	_load_texture_if_any()
	queue_redraw()


func set_combat_owner(owner: int) -> void:
	if owner == _owner:
		return
	_owner = owner


func get_combat_owner() -> int:
	return _owner


func start_attack_animation(attacks: Array) -> void:
	_attacking_faces.clear()
	for attack in attacks:
		_attacking_faces[str(attack["direction"])] = bool(attack["adjacent_enemy"])
	attack_regrowth = 1.0


func finish_attack_animation() -> void:
	_attacking_faces.clear()
	attack_regrowth = 1.0


## Géométrie des seules lames qui participent au tir. Les boucliers restent fixes.
func attack_markers(side: String, include_normal: bool) -> Array:
	var markers: Array = []
	for marker in face_markers(side):
		if marker["kind"] != "shield" and (include_normal or marker["kind"] == "long"):
			markers.append(marker)
	return markers


## Tous les symboles physiques d'une face, dans le même ordre que le dessin.
## L'indice stable permet de masquer un symbole sans changer ses statistiques.
func face_markers(side: String) -> Array:
	var markers: Array = []
	if _battle_stone == null:
		return markers
	for marker in _battle_stone.markers_for_side(side):
		marker["position"] = marker_position(side, int(marker["index"]))
		markers.append(marker)
	return markers


func set_marker_growth(side: String, index: int, growth: float) -> void:
	var key := "%s:%d" % [side, index]
	var clamped := clampf(growth, 0.0, 1.15)
	if float(_marker_growth.get(key, 1.0)) == clamped:
		return
	_marker_growth[key] = clamped
	queue_redraw()


func clear_marker_growth() -> void:
	if _marker_growth.is_empty():
		return
	_marker_growth.clear()
	queue_redraw()


func _animated_marker_growth(side: String, index: int) -> float:
	# Hors animation, aucune clé n'est construite pour chaque symbole dessiné.
	if _marker_growth.is_empty():
		return 1.0
	return float(_marker_growth.get("%s:%d" % [side, index], 1.0))


func face_center(side: String) -> Vector2:
	var count := _battle_stone.marker_count(side) if _battle_stone != null else 1
	return (marker_position(side, 0) + marker_position(side, maxi(0, count - 1))) * 0.5


## Appelé à chaque rafraîchissement du plateau : la carte n'est redessinée que si
## la pierre ou l'une de ses valeurs dessinées a changé depuis le dernier appel.
func set_battle_stone(value) -> void:
	var stone: BattleStoneModel = value if value is BattleStoneModel else null
	var state := _stone_state(stone)
	if stone == _battle_stone and state == _drawn_stone_state:
		return
	_battle_stone = stone
	_drawn_stone_state = state
	queue_redraw()


static func _stone_state(stone: BattleStoneModel) -> Array:
	if stone == null:
		return []
	return [stone.base_blades.duplicate(), stone.random_blades.duplicate(),
		stone.swarm_blades.duplicate(), stone.long_blades.duplicate(),
		stone.shields.duplicate(), stone.weakness()]


## Aperçu visuel seulement : le moteur a déjà calculé le résultat.
func set_combat_preview(value: BattleStoneModel) -> void:
	if value == _combat_preview:
		return
	_combat_preview = value
	queue_redraw()


func get_battle_stone() -> BattleStoneModel:
	return _battle_stone


## La logique est déjà résolue quand l'aura commence. Cette valeur permet à la
## vue de conserver l'ancien aspect jusqu'à l'impact, sans toucher au modèle.
func set_visual_weakness(value: int) -> void:
	var weakness := maxi(0, value)
	if weakness == _visual_weakness_override:
		return
	_visual_weakness_override = weakness
	queue_redraw()


func clear_visual_weakness() -> void:
	if _visual_weakness_override < 0:
		return
	_visual_weakness_override = -1
	queue_redraw()


func displayed_weakness() -> int:
	if _visual_weakness_override >= 0:
		return _visual_weakness_override
	return _battle_stone.weakness() if _battle_stone != null else 0


func broken_blade_count(side: String) -> int:
	var displayed := displayed_stone()
	if displayed == null:
		return 0
	var blade_count := displayed.normal_blades(side) + int(displayed.long_blades.get(side, 0))
	return mini(displayed_weakness(), blade_count)


## La pose précède la révélation Fortune : aucune face tirée au sort ne doit
## apparaître pendant le rebond initial. Seule une copie visuelle est masquée.
func hide_placement_power() -> void:
	if _battle_stone == null:
		return
	var random_count := int(_stone.get("random_blades", 0))
	var axis := str(_stone.get("coin_flip", ""))
	if random_count == 0 and axis == "":
		return
	var preview: BattleStoneModel = _battle_stone.clone()
	for side in BattleStoneModel.SIDES:
		preview.random_blades[side] = 0
	if preview.coin_flipped:
		var faces := StoneSide.coin_faces(axis)
		preview.swap_faces(faces[0], faces[1])
	set_combat_preview(preview)


## Version de la pierre visible à l'écran : l'aperçu d'une animation en cours,
## sinon l'état du moteur.
func displayed_stone() -> BattleStoneModel:
	return _combat_preview if _combat_preview != null else _battle_stone


## Coordonnée locale d'un symbole dans la disposition finale de la face.
func marker_position(side: String, index: int = -1) -> Vector2:
	return _marker_position_in(_battle_stone, side, index)


## Coordonnée locale d'un symbole tel qu'il est dessiné maintenant, aperçu compris.
func displayed_marker_position(side: String, index: int = -1) -> Vector2:
	return _marker_position_in(displayed_stone(), side, index)


func _marker_position_in(stone: BattleStoneModel, side: String, index: int) -> Vector2:
	var square := minf(size.x, size.y)
	var margin := square * _edge_margin_ratio
	var marker_margin := margin * _marker_scale
	var frame := Rect2((size - Vector2.ONE * square) * 0.5 + Vector2.ONE * margin,
		Vector2.ONE * (square - margin * 2.0))
	var count := stone.marker_count(side) if stone != null else 1
	var slot_index := count - 1 if index < 0 else index
	var along := frame.size.x * 0.14 + frame.size.x * 0.72 * (slot_index + 0.5) / float(maxi(1, count))
	match side:
		"top": return frame.position + Vector2(along, -marker_margin * 0.3)
		"bottom": return Vector2(frame.position.x + along, frame.end.y + marker_margin * 0.3)
		"left": return frame.position + Vector2(-marker_margin * 0.3, along)
		_: return Vector2(frame.end.x + marker_margin * 0.3, frame.position.y + along)


func set_selected(value: bool) -> void:
	if value == _selected:
		return
	_selected = value
	queue_redraw()


func set_show_cost(value: bool) -> void:
	if value == _show_cost:
		return
	_show_cost = value
	queue_redraw()


## Les grands aperçus peuvent privilégier l'illustration ; le combat garde 12 %.
func set_edge_margin_ratio(value: float) -> void:
	var ratio := clampf(value, 0.04, BLADE_MARGIN)
	if is_equal_approx(ratio, _edge_margin_ratio):
		return
	_edge_margin_ratio = ratio
	queue_redraw()


## Rend les symboles lisibles indépendamment de la marge réservée au cadre.
func set_marker_scale(value: float) -> void:
	var scale_value := clampf(value, 1.0, 3.0)
	if is_equal_approx(scale_value, _marker_scale):
		return
	_marker_scale = scale_value
	queue_redraw()


## Agrandit les logos de pouvoir dans les aperçus qui disposent de plus de place.
func set_power_badge_scale(value: float) -> void:
	var scale_value := clampf(value, 1.0, 2.5)
	if is_equal_approx(scale_value, _power_badge_scale):
		return
	_power_badge_scale = scale_value
	queue_redraw()


func get_stone_id() -> String:
	return _stone.get("id", _stone.get("stone_id", ""))


## Limite basse réellement dessinée dans le repère local. Contrairement au
## bord du Control, elle ne réserve pas de vide lorsqu'aucun symbole inférieur
## n'existe, tout en tenant compte des lames et boucliers présents.
func visual_content_bottom() -> float:
	var square_side := minf(size.x, size.y)
	var origin := (size - Vector2.ONE * square_side) * 0.5
	var margin := square_side * _edge_margin_ratio
	var frame_bottom := origin.y + square_side - margin
	var displayed := displayed_stone()
	if displayed == null:
		displayed = _catalog_stone()
	var depth_factor := 0.0
	for marker in displayed.markers_for_side("bottom"):
		match str(marker.get("kind", "")):
			"long": depth_factor = maxf(depth_factor, 1.28)
			"shield": depth_factor = maxf(depth_factor, 0.75)
			_: depth_factor = maxf(depth_factor, 1.0)
	return frame_bottom + margin * _marker_scale * 0.85 * depth_factor


## ─── Chargement texture optionnelle ───────────────────────────────────────────

func _load_texture_if_any() -> void:
	_texture = null
	_asset_path = str(_stone.get("asset", ""))
	if not _asset_path.is_empty():
		_texture = CardArtCache.texture(_asset_path)


func _on_texture_ready(path: String, loaded: Texture2D) -> void:
	if path != _asset_path:
		return
	_texture = loaded
	queue_redraw()


## ─── Entrée tactile / clic ────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if _tap.update(event, self) == Gesture.Result.TAP:
		card_pressed.emit(get_stone_id())


## ─── Dessin ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _stone.is_empty():
		return
	var square_side: float = min(size.x, size.y)
	var origin := (size - Vector2.ONE * square_side) * 0.5
	var margin: float = square_side * _edge_margin_ratio
	var frame_rect := Rect2(origin + Vector2.ONE * margin,
		Vector2.ONE * (square_side - 2.0 * margin))
	_draw_combat_edges(frame_rect, margin * _marker_scale)
	var layout := _draw_frame(frame_rect, square_side)
	var art_rect: Rect2 = layout["art_rect"]
	_draw_artwork(art_rect, square_side, layout["family_color"])
	_draw_name_panel(art_rect, float(layout["name_height"]))
	_draw_card_overlays(frame_rect, square_side, float(layout["border_width"]))


## Dessine la matière de famille et le contour de rareté, puis retourne les
## mesures communes dont les autres couches ont besoin.
func _draw_frame(frame_rect: Rect2, square_side: float) -> Dictionary:
	var thin_width: float = maxf(1.0, square_side * 0.012)
	var edge_width: float = maxf(1.0, square_side * 0.009)
	var border_width: float = maxf(2.0, square_side * 0.022)
	var family_color := _family_color()
	draw_rect(frame_rect, UITheme.COL_BG.lerp(family_color, 0.30), true)
	draw_rect(frame_rect.grow(-thin_width), UITheme.COL_SURFACE.lerp(family_color, 0.43), true)
	draw_rect(frame_rect, family_color.darkened(0.66), false, edge_width)
	var rarity_width := clampf(square_side * 0.016, 2.0, maxf(2.0, border_width * 0.8))
	_draw_rarity_outer(frame_rect, rarity_width)
	var inner := frame_rect.grow(-rarity_width * 0.6)
	var art_margin := square_side * 0.035
	var name_height := inner.size.y * 0.16
	var art_rect := Rect2(inner.position + Vector2.ONE * art_margin,
		Vector2(inner.size.x - 2.0 * art_margin,
			inner.size.y - 2.0 * art_margin - name_height))
	return {"art_rect": art_rect, "name_height": name_height,
		"family_color": family_color, "border_width": border_width}


func _draw_artwork(art_rect: Rect2, square_side: float, family_color: Color) -> void:
	if _texture != null:
		draw_rect(art_rect, COL_ILLUSTRATION_BG, true)
		draw_texture_rect(_texture, _illustration_rect(art_rect), false)
	else:
		_draw_missing_artwork(art_rect)
	_draw_power_badges(art_rect, square_side, family_color)
	if int(_stone.get("max_level", 1)) > 1:
		_draw_level_badge(art_rect, square_side)


func _draw_level_badge(art_rect: Rect2, square_side: float) -> void:
	var font := ThemeDB.fallback_font
	var font_size := maxi(12, int(square_side * 0.07))
	var text := "N%d" % int(_stone.get("level", 1))
	var badge := _level_badge_rect(art_rect, square_side)
	var padding := maxf(2.0, square_side * 0.008)
	draw_rect(badge, COL_NAME_BG)
	draw_string(font, badge.position + Vector2(padding, padding + font.get_ascent(font_size)),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _draw_name_panel(art_rect: Rect2, name_height: float) -> void:
	var name_rect := Rect2(art_rect.position.x, art_rect.end.y + 2.0,
		art_rect.size.x, name_height - 2.0)
	draw_rect(name_rect, COL_NAME_BG, true)
	_draw_name(name_rect)


func _draw_card_overlays(frame_rect: Rect2, square_side: float, border_width: float) -> void:
	if _selected:
		var selection_rect := frame_rect.grow(border_width * 0.48)
		draw_rect(selection_rect, Color("#ffe060", 0.24), false, border_width * 1.65)
		draw_rect(selection_rect, Color("#ffe060"), false, maxf(1.5, border_width * 0.62))
	if _show_cost:
		_draw_cost_badge(frame_rect, square_side)
	if displayed_weakness() > 0:
		_draw_weakness_badge(frame_rect, square_side)


## Largeur du texte et padding réel : aucun emplacement vide à droite de « N1 ».
func _level_badge_rect(art_rect: Rect2, square_side: float) -> Rect2:
	var font := ThemeDB.fallback_font
	var font_size := maxi(12, int(square_side * 0.07))
	var text := "N%d" % int(_stone.get("level", 1))
	var padding := maxf(2.0, square_side * 0.008)
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var extent := Vector2(text_width, font.get_height(font_size)) + Vector2.ONE * padding * 2.0
	return Rect2(art_rect.end - extent, extent)


## La texture reste partagée par ResourceLoader ; seules ses dimensions dessinées
## changent entre la fiche, la collection et le plateau.
func _illustration_rect(bounds: Rect2) -> Rect2:
	var image_size := _texture.get_size()
	var ratio := minf(bounds.size.x / image_size.x, bounds.size.y / image_size.y)
	var drawn_size := image_size * ratio
	return Rect2(bounds.get_center() - drawn_size * 0.5, drawn_size)


## Contour simple de la rareté, placé à l'extérieur du cadre famille.
func _draw_rarity_outer(bounds: Rect2, width: float) -> void:
	var rarity := str(_stone.get("rarity", "common")).to_lower()
	var color := UITheme.rarity_color(rarity)
	var outer := bounds.grow(width * 0.5)
	draw_rect(outer, color, false, width)


func _family_color() -> Color:
	var god_id := str(_stone.get("god_id", "neutral"))
	if god_id == "neutral":
		return COL_FRAME_LIGHT
	var god := StoneLoader.get_god(god_id)
	if god.is_empty():
		return COL_FRAME_LIGHT
	return Color(str(god.get("color", COL_FRAME_LIGHT.to_html())))


func _draw_cost_badge(frame_rect: Rect2, square_side: float) -> void:
	var cost := StoneLoader.stone_cost(get_stone_id())
	var radius := square_side * 0.085
	var center := frame_rect.position + Vector2(radius * 0.35, radius * 0.35)
	var font := ThemeDB.fallback_font
	var font_size := clampi(int(radius * 1.15), 12, UITheme.CARD_COST_MAX_FONT_SIZE)
	var value := UIFormat.cost(cost)
	var text_size := font.get_string_size(value, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	# Les grandes fiches agrandissent aussi les chiffres. Un coût long reste
	# compact pour ne pas masquer les premières lames du bord supérieur.
	var text_limit := maxf(radius * 1.9,
		font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x)
	if text_size.x > text_limit:
		font_size = maxi(12, int(float(font_size) * text_limit / text_size.x))
		text_size = font.get_string_size(value, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var badge := Rect2(center - Vector2.ONE * radius,
		Vector2(maxf(radius * 2.0, text_size.x + radius * 0.7), radius * 2.0))
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COL_DANGER
	style.border_color = COL_FRAME_LIGHT
	style.set_border_width_all(maxi(2, int(square_side * 0.012)))
	style.set_corner_radius_all(int(radius))
	draw_style_box(style, badge)
	draw_string(font, badge.get_center() + Vector2(-text_size.x * 0.5, text_size.y * 0.32), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


## ─── Dessin des lames ─────────────────────────────────────────────────────────

func _draw_combat_edges(frame_rect: Rect2, margin: float) -> void:
	var displayed := displayed_stone()
	if displayed == null:
		# Hors plateau, les lames Fortune inconnues ne sont pas inventées : leur
		# badge annonce le pouvoir, puis leurs vraies faces apparaissent à la pose.
		displayed = _catalog_stone()
	for side in BattleStoneModel.SIDES:
		var entries: Array = []
		for marker in displayed.markers_for_side(side):
			entries.append(marker["kind"])
		var blade_count := entries.size() - displayed.marker_count_of("shield", side)
		var broken_count := broken_blade_count(side)
		_draw_blade_row(frame_rect, side, entries, margin, broken_count, blade_count)


func _catalog_stone() -> BattleStoneModel:
	if _catalog_preview == null:
		_catalog_preview = BattleStoneModel.new()
		_catalog_preview.configure(get_stone_id(), _stone)
	return _catalog_preview


func _draw_blade_row(frame_rect: Rect2, side: String, entries: Array, margin: float,
	broken_count: int, blade_count: int) -> void:
	var count := entries.size()
	if count == 0:
		return
	var is_horizontal := side == "top" or side == "bottom"
	var along_length: float = (frame_rect.size.x if is_horizontal else frame_rect.size.y) * 0.72
	var along_start: float = (frame_rect.position.x if is_horizontal else frame_rect.position.y) \
		+ ((frame_rect.size.x if is_horizontal else frame_rect.size.y) - along_length) * 0.5
	var blade_w: float = min(along_length / float(max(count, 1)) * 0.6, margin * 1.1)
	var spacing: float = along_length / float(count)
	var depth: float = margin * 0.85
	for i in range(count):
		var center_along: float = along_start + spacing * (i + 0.5)
		var kind: String = entries[i]
		var marker_growth := _animated_marker_growth(side, i)
		if kind == "shield":
			_draw_shield_marker(frame_rect, side, center_along, blade_w, depth, marker_growth)
			continue
		_draw_blade_marker(frame_rect, side, center_along, blade_w, depth, kind,
			marker_growth, i < blade_count and i >= blade_count - broken_count)


func _draw_shield_marker(frame_rect: Rect2, side: String, center: float,
	width: float, depth: float, growth: float) -> void:
	if growth <= 0.01:
		return
	var anchor := _marker_anchor(frame_rect, side, center)
	Symbols.draw_shield(self, anchor["point"], width * 1.14 * growth,
		depth * 0.75 * growth, anchor["outward"], COL_SHIELD)


func _marker_anchor(frame_rect: Rect2, side: String, center: float) -> Dictionary:
	match side:
		"top": return {"point": Vector2(center, frame_rect.position.y), "outward": Vector2.UP}
		"bottom": return {"point": Vector2(center, frame_rect.end.y), "outward": Vector2.DOWN}
		"left": return {"point": Vector2(frame_rect.position.x, center), "outward": Vector2.LEFT}
		_: return {"point": Vector2(frame_rect.end.x, center), "outward": Vector2.RIGHT}


func _draw_blade_marker(frame_rect: Rect2, side: String, center: float,
	width: float, depth: float, kind: String, marker_growth: float, broken: bool) -> void:
	var is_long := kind == "long"
	var growth := marker_growth
	if _attacking_faces.has(side) and (is_long or bool(_attacking_faces[side])):
		growth *= attack_regrowth
	if growth <= 0.01:
		return
	var points := _blade_points(frame_rect, side, center, width,
		depth * (1.28 if is_long else 1.0))
	points = _scaled_marker(points, growth)
	var color := _blade_color(kind)
	if broken:
		_draw_broken_blade(points, color)
		return
	draw_colored_polygon(points, color)
	draw_polyline(_closed(points), COL_FRAME_EDGE, 1.5)
	if is_long:
		var inner := PackedVector2Array()
		for point in points:
			inner.append(point.lerp(frame_rect.get_center(), 0.28))
		draw_colored_polygon(inner, COL_BLADE_LIGHT)


func _blade_points(frame_rect: Rect2, side: String, center: float,
	width: float, depth: float) -> PackedVector2Array:
	var anchor := _marker_anchor(frame_rect, side, center)
	var base: Vector2 = anchor["point"]
	var outward: Vector2 = anchor["outward"]
	var tangent := Vector2(-outward.y, outward.x)
	return PackedVector2Array([base - tangent * width * 0.5,
		base + tangent * width * 0.5, base + outward * depth])


func _scaled_marker(points: PackedVector2Array, growth: float) -> PackedVector2Array:
	var scaled := points.duplicate()
	var base_center := (points[0] + points[1]) * 0.5
	for index in range(scaled.size()):
		scaled[index] = base_center + (scaled[index] - base_center) * growth
	return scaled


func _blade_color(kind: String) -> Color:
	match kind:
		"random": return COL_RANDOM_BLADE
		"swarm": return COL_SWARM_BLADE
		"long": return COL_LONG_BLADE
		_: return COL_BLADE_LIGHT


func _draw_broken_blade(points: PackedVector2Array, original_color: Color) -> void:
	var base_center := (points[0] + points[1]) * 0.5
	var axis := points[2] - base_center
	var tangent := (points[1] - points[0]).normalized()
	var left_break := points[0].lerp(points[2], 0.58)
	var right_break := points[1].lerp(points[2], 0.58)
	var crack_mid := (left_break + right_break) * 0.5 + axis.normalized() * axis.length() * 0.055
	var offset := axis.normalized() * axis.length() * 0.13 + tangent * axis.length() * 0.045
	var broken_color := original_color.lerp(Color("#644577"), 0.72)
	var base_piece := PackedVector2Array([points[0], points[1], right_break, crack_mid, left_break])
	var tip_piece := PackedVector2Array([left_break + offset, crack_mid + offset,
		right_break + offset, points[2] + offset])
	draw_colored_polygon(base_piece, broken_color)
	draw_polyline(_closed(base_piece), Color("#35243d"), 1.5, true)
	draw_colored_polygon(tip_piece, broken_color.darkened(0.08))
	draw_polyline(_closed(tip_piece), Color("#35243d"), 1.5, true)
	var crack := PackedVector2Array([left_break, crack_mid, right_break])
	draw_polyline(crack, Color("#e889d4"), maxf(1.2, axis.length() * 0.10), true)
	draw_circle(crack_mid + axis.normalized() * axis.length() * 0.12,
		maxf(1.2, axis.length() * 0.08), Color(0.58, 0.26, 0.70, 0.45))


func _draw_power_badges(art_rect: Rect2, square_side: float, family_color: Color) -> void:
	var radius := clampf(square_side * 0.064, 7.0, 24.0) * _power_badge_scale
	var gap := radius * 0.28
	var right := art_rect.end.x - gap
	for badge in Symbols.badges_for(_stone):
		var count := int(badge.get("count", 0))
		var width := Symbols.badge_width(radius, count)
		var center := Vector2(right - width + radius, art_rect.position.y + radius + gap)
		Symbols.draw_badge(self, center, radius, str(badge["kind"]), family_color, count)
		right -= width + gap


func _draw_weakness_badge(frame_rect: Rect2, square_side: float) -> void:
	var radius := square_side * 0.075
	var center := Vector2(frame_rect.end.x - radius * 0.35, frame_rect.position.y + radius * 0.35)
	draw_circle(center, radius, Color("#6d245d"))
	var font := ThemeDB.fallback_font
	var font_size := clampi(int(radius), 12, 28)
	var value := "-%d" % displayed_weakness()
	var text_size := font.get_string_size(value, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, center + Vector2(-text_size.x * 0.5, text_size.y * 0.32), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var c := pts.duplicate()
	c.append(pts[0])
	return c


## ─── Illustration absente ────────────────────────────────────────────────────

## Repli volontairement neutre : aucune illustration procédurale ne remplace les
## assets du bestiaire. Une ressource manquante reste donc visible et détectable.
func _draw_missing_artwork(art_rect: Rect2) -> void:
	draw_rect(art_rect, COL_ILLUSTRATION_BG, true)
	var unit := minf(art_rect.size.x, art_rect.size.y)
	var icon_size := unit * 0.24
	var icon := Rect2(art_rect.get_center() - Vector2.ONE * icon_size * 0.5,
		Vector2.ONE * icon_size)
	var line_width := maxf(2.0, unit * 0.012)
	var color := UITheme.COL_TEXT_DIM
	draw_rect(icon, color, false, line_width)
	draw_line(icon.position, icon.end, color, line_width, true)
	draw_line(Vector2(icon.end.x, icon.position.y), Vector2(icon.position.x, icon.end.y),
		color, line_width, true)
	var font := ThemeDB.fallback_font
	var font_size := maxi(10, int(unit * 0.045))
	var label := "ILLUSTRATION INDISPONIBLE"
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1,
		font_size).x
	draw_string(font, Vector2(art_rect.get_center().x - label_width * 0.5,
		icon.end.y + unit * 0.09), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, color)


## ─── Dessin du nom ────────────────────────────────────────────────────────────

func _draw_name(name_rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var fsize := int(name_rect.size.y * 0.55)
	fsize = clampi(fsize, 8, UITheme.CARD_NAME_MAX_FONT_SIZE)
	var text: String = _stone.get("name", "")
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
	# Réduire la taille si le texte dépasse
	while text_size.x > name_rect.size.x - 6.0 and fsize > 8:
		fsize -= 1
		text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
	var pos := Vector2(
		name_rect.position.x + (name_rect.size.x - text_size.x) * 0.5,
		name_rect.position.y + (name_rect.size.y + text_size.y) * 0.5 - fsize * 0.25
	)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, COL_NAME_TEXT)


## Redessine quand la taille change
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == Control.NOTIFICATION_SCROLL_BEGIN:
		_tap.cancel()
	elif what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_tap.reset()
