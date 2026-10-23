## StoneCard.gd
## Composant carte réutilisable de SamStone.
## Dessine entièrement une carte par code (_draw) à partir des données d'une pierre :
##   - cadre à la couleur de la famille
##   - lames triangulaires sur les 4 côtés (le nombre = la valeur du côté)
##   - bordure colorée selon le propriétaire (joueur / IA / neutre)
##   - silhouette placeholder + arme (dessins génériques originaux)
##   - bandeau de nom
##
## Si la pierre a un champ "asset" non vide pointant vers une image existante,
## cette image est affichée à la place du dessin procédural.
##
## Utilisé partout : collection, main, plateau.
@tool
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
const COL_FRAME_LIGHT := Color("#f0d88a")
const COL_FRAME_DARK := Color("#8a6a28")
const COL_FRAME_EDGE := Color("#5a4418")
const COL_BLADE_LIGHT := Color("#ffe9a8")
const COL_BLADE_DARK := Color("#b8902f")
const COL_RANDOM_BLADE := Symbols.FORTUNE
const COL_LONG_BLADE := Color("#4fa9ff")
const COL_SWARM_BLADE := Color("#83d85d")
const COL_SHIELD := Color("#92e7f2")
const COL_ART_BG := Color("#d8c8a8")
const COL_NAME_BG := Color("#2a1a0e")
const COL_NAME_TEXT := Color("#f0e0c0")
const COL_BORDER_HUMAN := Color("#3a7ad0")
const COL_BORDER_AI := Color("#d04040")
const COL_BORDER_NONE := Color("#9a8a6a")

## ─── Données de la pierre ─────────────────────────────────────────────────────
var _stone: Dictionary = {}
var _owner: int = OWNER_NONE
var _selected: bool = false
var _texture: Texture2D = null  ## illustration si disponible
var _show_cost: bool = false
var _battle_stone: BattleStoneModel = null
var _combat_preview: BattleStoneModel = null
var _attacking_faces: Dictionary = {}
var _marker_growth: Dictionary = {}
var _visual_weakness_override: int = -1
var attack_regrowth: float = 1.0:
	set(value):
		attack_regrowth = clampf(value, 0.0, 1.15)
		queue_redraw()
const Gesture := preload("res://scripts/ui/input/TapGesture.gd")
var _tap := Gesture.new()

## ─── Dimensions internes (ratio carte) ───────────────────────────────────────
## La carte occupe tout le rect du Control. On réserve une marge pour les lames.
const BLADE_MARGIN: float = 0.12  ## proportion réservée aux lames sur les bords

## ─── API publique ─────────────────────────────────────────────────────────────

## Configure la carte avec une pierre et un propriétaire.
func _init() -> void:
	# Les cartes restent interactives et laissent les gestes atteindre
	# le ScrollContainer parent, y compris lorsqu'ils débutent sur l'image.
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(stone: Dictionary, owner: int = OWNER_NONE, battle_stone = null) -> void:
	_stone = stone
	_owner = owner
	_battle_stone = battle_stone if battle_stone is BattleStoneModel else null
	_load_texture_if_any()
	queue_redraw()


func set_owner_color(owner: int) -> void:
	_owner = owner
	queue_redraw()


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
	var kinds := ["normal", "random", "swarm", "long", "shield"]
	var maps := [_battle_stone.base_blades, _battle_stone.random_blades,
		_battle_stone.swarm_blades, _battle_stone.long_blades, _battle_stone.shields]
	var index := 0
	for group in range(kinds.size()):
		for _marker in range(int(maps[group].get(side, 0))):
			markers.append({"kind": kinds[group], "index": index,
				"position": marker_position(side, index)})
			index += 1
	return markers


func set_marker_growth(side: String, index: int, growth: float) -> void:
	_marker_growth["%s:%d" % [side, index]] = clampf(growth, 0.0, 1.15)
	queue_redraw()


func clear_marker_growth() -> void:
	_marker_growth.clear()
	queue_redraw()


func _animated_marker_growth(side: String, index: int) -> float:
	return float(_marker_growth.get("%s:%d" % [side, index], 1.0))


func face_center(side: String) -> Vector2:
	var count := _battle_stone.marker_count(side) if _battle_stone != null else 1
	return (marker_position(side, 0) + marker_position(side, maxi(0, count - 1))) * 0.5


func set_battle_stone(value) -> void:
	_battle_stone = value if value is BattleStoneModel else null
	queue_redraw()


## Aperçu visuel seulement : le moteur a déjà calculé le résultat.
func set_combat_preview(value: BattleStoneModel) -> void:
	_combat_preview = value
	queue_redraw()


func get_battle_stone() -> BattleStoneModel:
	return _battle_stone


## La logique est déjà résolue quand l'aura commence. Cette valeur permet à la
## vue de conserver l'ancien aspect jusqu'à l'impact, sans toucher au modèle.
func set_visual_weakness(value: int) -> void:
	_visual_weakness_override = maxi(0, value)
	queue_redraw()


func clear_visual_weakness() -> void:
	_visual_weakness_override = -1
	queue_redraw()


func displayed_weakness() -> int:
	if _visual_weakness_override >= 0:
		return _visual_weakness_override
	return _battle_stone.weakness() if _battle_stone != null else 0


func broken_blade_count(side: String) -> int:
	var displayed := _display_stone()
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
		preview.swap_faces("left" if axis == "horizontal" else "top", "right" if axis == "horizontal" else "bottom")
	set_combat_preview(preview)


func _display_stone() -> BattleStoneModel:
	return _combat_preview if _combat_preview != null else _battle_stone


## Coordonnée locale d'un symbole dans la disposition finale de la face.
func marker_position(side: String, index: int = -1) -> Vector2:
	var square := minf(size.x, size.y)
	var margin := square * BLADE_MARGIN
	var frame := Rect2((size - Vector2.ONE * square) * 0.5 + Vector2.ONE * margin,
		Vector2.ONE * (square - margin * 2.0))
	var count := _battle_stone.marker_count(side) if _battle_stone != null else 1
	var slot_index := count - 1 if index < 0 else index
	var along := frame.size.x * 0.14 + frame.size.x * 0.72 * (slot_index + 0.5) / float(maxi(1, count))
	match side:
		"top": return frame.position + Vector2(along, -margin * 0.3)
		"bottom": return Vector2(frame.position.x + along, frame.end.y + margin * 0.3)
		"left": return frame.position + Vector2(-margin * 0.3, along)
		_: return Vector2(frame.end.x + margin * 0.3, frame.position.y + along)


func set_selected(value: bool) -> void:
	_selected = value
	queue_redraw()


func set_show_cost(value: bool) -> void:
	_show_cost = value
	queue_redraw()


func get_stone_id() -> String:
	return _stone.get("id", _stone.get("stone_id", ""))


## ─── Chargement texture optionnelle ───────────────────────────────────────────

func _load_texture_if_any() -> void:
	_texture = null
	var path: String = _stone.get("asset", "")
	if path != "" and ResourceLoader.exists(path):
		_texture = load(path)


## ─── Entrée tactile / clic ────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if _tap.update(event, self) == Gesture.Result.TAP:
		card_pressed.emit(get_stone_id())


## ─── Dessin ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _stone.is_empty():
		return

	## La carte se dessine TOUJOURS dans un CARRÉ centré, quel que soit l'espace
	## reçu. Ainsi elle reste 1:1 et n'est jamais écrasée, même si le conteneur
	## est rectangulaire. Le reste de l'espace reste transparent.
	var square_side: float = min(size.x, size.y)
	var origin := Vector2(
		(size.x - square_side) * 0.5,
		(size.y - square_side) * 0.5
	)
	var margin: float = square_side * BLADE_MARGIN

	# Rectangle intérieur (cadre) une fois les lames retirées sur les bords,
	# positionné dans le carré centré.
	var frame_rect := Rect2(
		origin.x + margin,
		origin.y + margin,
		square_side - 2.0 * margin,
		square_side - 2.0 * margin
	)

	# 1. Lames, lames spéciales et boucliers (derrière le cadre).
	_draw_combat_edges(frame_rect, margin)

	## Épaisseurs proportionnelles au côté du carré (rendu correct à toute taille).
	var w_thin: float = max(1.0, square_side * 0.012)
	var w_edge: float = max(1.0, square_side * 0.009)
	var w_border: float = max(2.0, square_side * 0.022)
	var art_margin: float = square_side * 0.035

	# 2. Le minerai du cadre reprend la couleur de la famille du dieu.
	var family_color := _family_color()
	var frame_dark := family_color.darkened(0.46)
	var frame_light := family_color.lightened(0.20)
	var frame_edge := family_color.darkened(0.68)
	draw_rect(frame_rect, frame_dark, true)
	var inner_frame := frame_rect.grow(-w_thin)
	draw_rect(inner_frame, frame_light, true)
	draw_rect(frame_rect, frame_edge, false, w_edge)

	# 3. Bordure propriétaire
	var border_col := _owner_color()
	var border_rect := frame_rect.grow(-w_border * 0.75)
	draw_rect(border_rect, border_col, false, w_border)

	# 4. Zone illustration
	var name_h := frame_rect.size.y * 0.16
	var art_rect := Rect2(
		border_rect.position.x + art_margin,
		border_rect.position.y + art_margin,
		border_rect.size.x - 2.0 * art_margin,
		border_rect.size.y - 2.0 * art_margin - name_h
	)

	if _texture != null:
		draw_texture_rect(_texture, art_rect, false)
	else:
		draw_rect(art_rect, COL_ART_BG, true)
		_draw_character(art_rect)
	_draw_power_badges(art_rect, square_side, family_color)

	# 5. Bandeau de nom
	var name_rect := Rect2(
		art_rect.position.x,
		art_rect.position.y + art_rect.size.y + 2.0,
		art_rect.size.x,
		name_h - 2.0
	)
	draw_rect(name_rect, COL_NAME_BG, true)
	_draw_name(name_rect)

	# 6. Surbrillance si sélectionnée
	if _selected:
		draw_rect(frame_rect, Color("#ffe060"), false, w_border)

	# 7. Coût du deck, affiché uniquement dans l'écran Cartes.
	if _show_cost:
		_draw_cost_badge(frame_rect, square_side)
	if displayed_weakness() > 0:
		_draw_weakness_badge(frame_rect, square_side)


func _owner_color() -> Color:
	match _owner:
		OWNER_HUMAN: return COL_BORDER_HUMAN
		OWNER_AI:    return COL_BORDER_AI
		_:           return COL_BORDER_NONE


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
	draw_circle(center, radius, Color("#6f1717"))
	draw_arc(center, radius, 0, TAU, 24, COL_FRAME_LIGHT, max(2.0, square_side * 0.012))
	var font := ThemeDB.fallback_font
	var font_size := clampi(int(radius * 1.15), 12, 30)
	var value := StoneLoader.format_cost(cost)
	var text_size := font.get_string_size(value, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, center + Vector2(-text_size.x * 0.5, text_size.y * 0.32), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


## ─── Dessin des lames ─────────────────────────────────────────────────────────

func _draw_combat_edges(frame_rect: Rect2, margin: float) -> void:
	var base: Dictionary = _stone.get("blades", {})
	# Les lames Fortune inconnues ne sont plus inventées sur l'aperçu : leur
	# badge annonce le pouvoir, puis leurs vraies faces apparaissent à la pose.
	var random_map: Dictionary = {}
	var long_map: Dictionary = _stone.get("long_blades", {})
	var shield_map: Dictionary = _stone.get("shields", {})
	var swarm_map: Dictionary = {}
	var displayed := _display_stone()
	if displayed != null:
		base = displayed.base_blades
		random_map = displayed.random_blades
		long_map = displayed.long_blades
		shield_map = displayed.shields
		swarm_map = displayed.swarm_blades
	for side in BattleStoneModel.SIDES:
		var entries: Array = []
		for i in range(int(base.get(side, 0))):
			entries.append("normal")
		for i in range(int(random_map.get(side, 0))):
			entries.append("random")
		for i in range(int(swarm_map.get(side, 0))):
			entries.append("swarm")
		for i in range(int(long_map.get(side, 0))):
			entries.append("long")
		for i in range(int(shield_map.get(side, 0))):
			entries.append("shield")
		var blade_count := entries.size() - int(shield_map.get(side, 0))
		var broken_count := broken_blade_count(side)
		_draw_blade_row(frame_rect, side, entries, margin, broken_count, blade_count)


func _draw_blade_row(frame_rect: Rect2, side: String, entries: Array, margin: float,
	broken_count: int, blade_count: int) -> void:
	var count := entries.size()
	if count == 0:
		return

	var is_horizontal := side == "top" or side == "bottom"
	# Longueur disponible le long du côté (on réserve un peu aux coins)
	var along_length: float = (frame_rect.size.x if is_horizontal else frame_rect.size.y) * 0.72
	var along_start: float = (frame_rect.position.x if is_horizontal else frame_rect.position.y) \
		+ ((frame_rect.size.x if is_horizontal else frame_rect.size.y) - along_length) * 0.5

	var blade_w: float = min(along_length / float(max(count, 1)) * 0.6, margin * 1.1)
	var spacing: float = along_length / float(count)
	var depth: float = margin * 0.85  # hauteur du triangle vers l'extérieur

	for i in range(count):
		var center_along: float = along_start + spacing * (i + 0.5)
		var kind: String = entries[i]
		var marker_growth := _animated_marker_growth(side, i)
		if kind == "shield":
			if marker_growth <= 0.01:
				continue
			var base_point := Vector2.ZERO
			var outward := Vector2.ZERO
			match side:
				"top":
					base_point = Vector2(center_along, frame_rect.position.y)
					outward = Vector2.UP
				"bottom":
					base_point = Vector2(center_along, frame_rect.end.y)
					outward = Vector2.DOWN
				"left":
					base_point = Vector2(frame_rect.position.x, center_along)
					outward = Vector2.LEFT
				"right":
					base_point = Vector2(frame_rect.end.x, center_along)
					outward = Vector2.RIGHT
			Symbols.draw_shield(self, base_point, blade_w * 1.14 * marker_growth,
				depth * 0.75 * marker_growth, outward, COL_SHIELD)
			continue
		var is_long := kind == "long"
		var growth := 1.0
		if _attacking_faces.has(side) and (is_long or bool(_attacking_faces[side])):
			growth = attack_regrowth
		growth *= marker_growth
		if growth <= 0.01:
			continue
		var blade_depth := depth * (1.28 if is_long else 1.0)
		var pts := PackedVector2Array()
		match side:
			"top":
				var y_base := frame_rect.position.y
				pts.append(Vector2(center_along - blade_w * 0.5, y_base))
				pts.append(Vector2(center_along + blade_w * 0.5, y_base))
				pts.append(Vector2(center_along, y_base - blade_depth))
			"bottom":
				var yb := frame_rect.position.y + frame_rect.size.y
				pts.append(Vector2(center_along - blade_w * 0.5, yb))
				pts.append(Vector2(center_along + blade_w * 0.5, yb))
				pts.append(Vector2(center_along, yb + blade_depth))
			"left":
				var xl := frame_rect.position.x
				pts.append(Vector2(xl, center_along - blade_w * 0.5))
				pts.append(Vector2(xl, center_along + blade_w * 0.5))
				pts.append(Vector2(xl - blade_depth, center_along))
			"right":
				var xr := frame_rect.position.x + frame_rect.size.x
				pts.append(Vector2(xr, center_along - blade_w * 0.5))
				pts.append(Vector2(xr, center_along + blade_w * 0.5))
				pts.append(Vector2(xr + blade_depth, center_along))
		var base_center := (pts[0] + pts[1]) * 0.5
		for point_index in range(pts.size()):
			pts[point_index] = base_center + (pts[point_index] - base_center) * growth
		var color := COL_BLADE_LIGHT
		if kind == "random":
			color = COL_RANDOM_BLADE
		elif kind == "swarm":
			color = COL_SWARM_BLADE
		elif kind == "long":
			color = COL_LONG_BLADE
		var broken := i < blade_count and i >= blade_count - broken_count
		if broken:
			_draw_broken_blade(pts, color)
			continue
		draw_colored_polygon(pts, color)
		draw_polyline(_closed(pts), COL_FRAME_EDGE, 1.5)
		if is_long:
			var inner := PackedVector2Array()
			for point in pts:
				inner.append(point.lerp(frame_rect.get_center(), 0.28))
			draw_colored_polygon(inner, COL_BLADE_LIGHT)


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
	var radius := clampf(square_side * 0.064, 7.0, 24.0)
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


## ─── Dessin du personnage placeholder + arme ─────────────────────────────────

func _draw_character(art_rect: Rect2) -> void:
	var kind: String = _stone.get("kind", "human")
	var body_color := Color(_stone.get("body_color", "#7a6a4a"))
	var cx := art_rect.position.x + art_rect.size.x * 0.5
	var base_y := art_rect.position.y + art_rect.size.y * 0.52
	var unit: float = min(art_rect.size.x, art_rect.size.y)

	## Sol / ombre portée sous le personnage pour l'ancrer
	_draw_ground_shadow(cx, art_rect.position.y + art_rect.size.y * 0.9, unit)

	match kind:
		"dragon":
			_draw_dragon(cx, base_y, unit, body_color)
		"creature":
			_draw_creature(cx, base_y, unit, body_color)
		"oni":
			_draw_weapon(art_rect, unit)
			_draw_humanoid(cx, base_y, unit, body_color, "oni")
		"deity":
			_draw_aura(cx, base_y - unit * 0.1, unit)
			_draw_weapon(art_rect, unit)
			_draw_humanoid(cx, base_y, unit, body_color, "deity")
		_:  # human
			_draw_weapon(art_rect, unit)
			_draw_humanoid(cx, base_y, unit, body_color, "human")


func _draw_ground_shadow(cx: float, y: float, unit: float) -> void:
	## Ellipse sombre semi-transparente
	var pts := PackedVector2Array()
	var rx := unit * 0.30
	var ry := unit * 0.055
	for i in range(20):
		var a := TAU * float(i) / 20.0
		pts.append(Vector2(cx + cos(a) * rx, y + sin(a) * ry))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.18))


## ─────────────────────────────────────────────────────────────────────────────
## Silhouette humanoïde détaillée : armure, casque à cimier, visage, bras.
## variant : "human" | "oni" | "deity". Designs 100% originaux.
## ─────────────────────────────────────────────────────────────────────────────
func _draw_humanoid(cx: float, cy: float, unit: float, body_color: Color, variant: String) -> void:
	var armor := body_color
	var armor_dark := body_color.darkened(0.3)
	var armor_light := body_color.lightened(0.22)
	var skin := Color("#e8c8a0") if variant != "oni" else body_color.lightened(0.3)
	var trim := Color("#d8b84a")  ## liserés dorés

	var head_r := unit * 0.13
	var head_y := cy - unit * 0.28

	## ── Jambes (deux segments) ──
	var leg_top := cy + unit * 0.18
	var leg_bot := cy + unit * 0.40
	_draw_line_w(Vector2(cx - unit * 0.09, leg_top), Vector2(cx - unit * 0.11, leg_bot), armor_dark, unit * 0.09)
	_draw_line_w(Vector2(cx + unit * 0.09, leg_top), Vector2(cx + unit * 0.11, leg_bot), armor_dark, unit * 0.09)
	## pieds
	draw_rect(Rect2(cx - unit * 0.17, leg_bot - unit * 0.02, unit * 0.12, unit * 0.04), armor_dark, true)
	draw_rect(Rect2(cx + unit * 0.05, leg_bot - unit * 0.02, unit * 0.12, unit * 0.04), armor_dark, true)

	## ── Torse (plastron trapézoïdal) ──
	var torso := PackedVector2Array([
		Vector2(cx - unit * 0.17, cy - unit * 0.12),
		Vector2(cx + unit * 0.17, cy - unit * 0.12),
		Vector2(cx + unit * 0.14, cy + unit * 0.20),
		Vector2(cx - unit * 0.14, cy + unit * 0.20)
	])
	draw_colored_polygon(torso, armor)
	## Lamelles d'armure (3 bandes horizontales)
	for i in range(3):
		var ly := cy - unit * 0.04 + i * unit * 0.08
		_draw_line_w(Vector2(cx - unit * 0.14, ly), Vector2(cx + unit * 0.14, ly), armor_dark, unit * 0.02)
	## Liseré doré central
	_draw_line_w(Vector2(cx, cy - unit * 0.12), Vector2(cx, cy + unit * 0.18), trim, unit * 0.02)

	## ── Épaulières ──
	_draw_shoulder(cx - unit * 0.17, cy - unit * 0.10, unit * 0.10, armor_light, armor_dark)
	_draw_shoulder(cx + unit * 0.17, cy - unit * 0.10, unit * 0.10, armor_light, armor_dark)

	## ── Bras ──
	_draw_line_w(Vector2(cx - unit * 0.18, cy - unit * 0.04), Vector2(cx - unit * 0.22, cy + unit * 0.12), armor, unit * 0.06)
	_draw_line_w(Vector2(cx + unit * 0.18, cy - unit * 0.04), Vector2(cx + unit * 0.22, cy + unit * 0.12), armor, unit * 0.06)

	## ── Cou + tête ──
	_draw_line_w(Vector2(cx, cy - unit * 0.12), Vector2(cx, head_y + head_r * 0.6), skin.darkened(0.15), unit * 0.05)
	draw_circle(Vector2(cx, head_y), head_r, skin)

	## Casque / coiffe selon variante
	match variant:
		"oni":
			## Cornes + crocs + regard féroce
			_draw_horns(cx, head_y, head_r, Color("#f0e8d8"))
			## sourcils agressifs
			_draw_line_w(Vector2(cx - head_r * 0.6, head_y - head_r * 0.1), Vector2(cx - head_r * 0.15, head_y + head_r * 0.1), armor_dark, 2.0)
			_draw_line_w(Vector2(cx + head_r * 0.15, head_y + head_r * 0.1), Vector2(cx + head_r * 0.6, head_y - head_r * 0.1), armor_dark, 2.0)
			## yeux
			draw_circle(Vector2(cx - head_r * 0.35, head_y + head_r * 0.15), head_r * 0.12, Color("#ffe040"))
			draw_circle(Vector2(cx + head_r * 0.35, head_y + head_r * 0.15), head_r * 0.12, Color("#ffe040"))
		"deity":
			## Couronne rayonnante + yeux calmes
			_draw_crown(cx, head_y - head_r * 0.7, head_r, trim)
			draw_circle(Vector2(cx - head_r * 0.3, head_y), head_r * 0.09, Color("#3a2a1a"))
			draw_circle(Vector2(cx + head_r * 0.3, head_y), head_r * 0.09, Color("#3a2a1a"))
		_:
			## Casque de samouraï : dôme + cimier en croissant
			var helm := PackedVector2Array([
				Vector2(cx - head_r * 1.15, head_y + head_r * 0.1),
				Vector2(cx - head_r * 0.9, head_y - head_r * 0.9),
				Vector2(cx + head_r * 0.9, head_y - head_r * 0.9),
				Vector2(cx + head_r * 1.15, head_y + head_r * 0.1)
			])
			draw_colored_polygon(helm, armor_dark)
			## cimier croissant doré
			draw_arc(Vector2(cx, head_y - head_r * 0.6), head_r * 1.1, PI * 1.15, PI * 1.85, 12, trim, 3.0)
			## yeux
			draw_circle(Vector2(cx - head_r * 0.3, head_y + head_r * 0.1), head_r * 0.09, Color("#3a2a1a"))
			draw_circle(Vector2(cx + head_r * 0.3, head_y + head_r * 0.1), head_r * 0.09, Color("#3a2a1a"))


func _draw_shoulder(x: float, y: float, r: float, light: Color, dark: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(8):
		var a := PI + PI * float(i) / 7.0
		pts.append(Vector2(x + cos(a) * r, y + sin(a) * r * 0.7))
	draw_colored_polygon(pts, light)
	draw_polyline(pts, dark, 1.5)


func _draw_horns(cx: float, head_y: float, head_r: float, col: Color) -> void:
	## Deux cornes incurvées
	var lh := PackedVector2Array([
		Vector2(cx - head_r * 0.7, head_y - head_r * 0.7),
		Vector2(cx - head_r * 0.4, head_y - head_r * 0.7),
		Vector2(cx - head_r * 0.9, head_y - head_r * 1.7)
	])
	var rh := PackedVector2Array([
		Vector2(cx + head_r * 0.4, head_y - head_r * 0.7),
		Vector2(cx + head_r * 0.7, head_y - head_r * 0.7),
		Vector2(cx + head_r * 0.9, head_y - head_r * 1.7)
	])
	draw_colored_polygon(lh, col)
	draw_colored_polygon(rh, col)


func _draw_crown(cx: float, y: float, head_r: float, col: Color) -> void:
	## Petite couronne à 3 pointes
	for off in [-0.6, 0.0, 0.6]:
		_tri(
			Vector2(cx + off * head_r - head_r * 0.2, y),
			Vector2(cx + off * head_r + head_r * 0.2, y),
			Vector2(cx + off * head_r, y - head_r * 0.6),
			col
		)
	_draw_line_w(Vector2(cx - head_r * 0.9, y), Vector2(cx + head_r * 0.9, y), col, 2.5)


## ─────────────────────────────────────────────────────────────────────────────
## Créatures (yokai) : forme spécifique selon l'id de la pierre.
## ─────────────────────────────────────────────────────────────────────────────
func _draw_creature(cx: float, cy: float, unit: float, body_color: Color) -> void:
	var id := get_stone_id()
	match id:
		"kitsune":   _draw_fox(cx, cy, unit, body_color)
		"kappa":     _draw_kappa(cx, cy, unit, body_color)
		"tanuki":    _draw_tanuki(cx, cy, unit, body_color)
		"jorogumo":  _draw_spider(cx, cy, unit, body_color)
		"tengu":     _draw_tengu(cx, cy, unit, body_color)
		_:           _draw_generic_beast(cx, cy, unit, body_color)


func _draw_fox(cx: float, cy: float, unit: float, col: Color) -> void:
	var light := col.lightened(0.2)
	## Corps assis
	draw_circle(Vector2(cx, cy + unit * 0.14), unit * 0.20, col)
	## Plusieurs queues (renard à queues multiples)
	for off in [-0.30, -0.18, 0.18, 0.30]:
		var tail := PackedVector2Array([
			Vector2(cx, cy + unit * 0.14),
			Vector2(cx + off * unit, cy - unit * 0.05),
			Vector2(cx + off * unit * 1.3, cy - unit * 0.28)
		])
		draw_colored_polygon(tail, light)
		## pointe blanche
		draw_circle(Vector2(cx + off * unit * 1.3, cy - unit * 0.28), unit * 0.03, Color("#f0ece0"))
	## Tête triangulaire
	var head := PackedVector2Array([
		Vector2(cx - unit * 0.14, cy - unit * 0.14),
		Vector2(cx + unit * 0.14, cy - unit * 0.14),
		Vector2(cx, cy + unit * 0.06)
	])
	draw_colored_polygon(head, col)
	## Oreilles
	_tri(Vector2(cx - unit * 0.14, cy - unit * 0.14), Vector2(cx - unit * 0.05, cy - unit * 0.14), Vector2(cx - unit * 0.13, cy - unit * 0.30), col)
	_tri(Vector2(cx + unit * 0.05, cy - unit * 0.14), Vector2(cx + unit * 0.14, cy - unit * 0.14), Vector2(cx + unit * 0.13, cy - unit * 0.30), col)
	## Yeux bridés
	_draw_line_w(Vector2(cx - unit * 0.08, cy - unit * 0.06), Vector2(cx - unit * 0.03, cy - unit * 0.04), Color("#ffe040"), 2.0)
	_draw_line_w(Vector2(cx + unit * 0.03, cy - unit * 0.04), Vector2(cx + unit * 0.08, cy - unit * 0.06), Color("#ffe040"), 2.0)


func _draw_kappa(cx: float, cy: float, unit: float, col: Color) -> void:
	## Carapace + tête avec "assiette" sur le crâne
	draw_circle(Vector2(cx, cy + unit * 0.12), unit * 0.22, col.darkened(0.15))  ## carapace
	draw_arc(Vector2(cx, cy + unit * 0.12), unit * 0.22, PI, TAU, 16, col.darkened(0.35), 2.0)
	## membres
	_draw_line_w(Vector2(cx - unit * 0.18, cy + unit * 0.10), Vector2(cx - unit * 0.28, cy + unit * 0.24), col, unit * 0.05)
	_draw_line_w(Vector2(cx + unit * 0.18, cy + unit * 0.10), Vector2(cx + unit * 0.28, cy + unit * 0.24), col, unit * 0.05)
	## tête
	draw_circle(Vector2(cx, cy - unit * 0.14), unit * 0.14, col.lightened(0.1))
	## assiette d'eau sur le crâne (anneau)
	draw_arc(Vector2(cx, cy - unit * 0.22), unit * 0.08, 0, TAU, 14, Color("#9ad0e0"), 2.5)
	## bec
	_tri(Vector2(cx - unit * 0.05, cy - unit * 0.12), Vector2(cx + unit * 0.05, cy - unit * 0.12), Vector2(cx, cy - unit * 0.05), Color("#d0a040"))
	## yeux
	draw_circle(Vector2(cx - unit * 0.05, cy - unit * 0.16), unit * 0.02, Color("#201810"))
	draw_circle(Vector2(cx + unit * 0.05, cy - unit * 0.16), unit * 0.02, Color("#201810"))


func _draw_tanuki(cx: float, cy: float, unit: float, col: Color) -> void:
	var light := col.lightened(0.25)
	## Corps rond et bedonnant
	draw_circle(Vector2(cx, cy + unit * 0.12), unit * 0.24, col)
	draw_circle(Vector2(cx, cy + unit * 0.16), unit * 0.15, light)  ## ventre clair
	## Tête
	draw_circle(Vector2(cx, cy - unit * 0.12), unit * 0.16, col)
	## Masque facial (bandeau sombre autour des yeux)
	draw_rect(Rect2(cx - unit * 0.14, cy - unit * 0.15, unit * 0.28, unit * 0.06), col.darkened(0.4), true)
	## Oreilles rondes
	draw_circle(Vector2(cx - unit * 0.13, cy - unit * 0.24), unit * 0.05, col)
	draw_circle(Vector2(cx + unit * 0.13, cy - unit * 0.24), unit * 0.05, col)
	## Yeux
	draw_circle(Vector2(cx - unit * 0.06, cy - unit * 0.13), unit * 0.02, Color("#f0f0e0"))
	draw_circle(Vector2(cx + unit * 0.06, cy - unit * 0.13), unit * 0.02, Color("#f0f0e0"))


func _draw_spider(cx: float, cy: float, unit: float, col: Color) -> void:
	## Jōrōgumo : corps + 8 pattes
	var dark := col.darkened(0.2)
	for side in [-1.0, 1.0]:
		for i in range(4):
			var ay := cy - unit * 0.06 + i * unit * 0.06
			var mid := Vector2(cx + side * unit * 0.22, ay - unit * 0.1)
			var tip := Vector2(cx + side * unit * 0.34, ay + unit * 0.06)
			_draw_line_w(Vector2(cx, ay), mid, dark, 2.5)
			_draw_line_w(mid, tip, dark, 2.5)
	## abdomen + céphalothorax
	draw_circle(Vector2(cx, cy + unit * 0.14), unit * 0.16, col)
	draw_circle(Vector2(cx, cy - unit * 0.08), unit * 0.11, col.lightened(0.15))
	## motif sur l'abdomen
	_tri(Vector2(cx - unit * 0.06, cy + unit * 0.10), Vector2(cx + unit * 0.06, cy + unit * 0.10), Vector2(cx, cy + unit * 0.22), Color("#e0b040"))
	## yeux multiples
	for ox in [-0.05, -0.02, 0.02, 0.05]:
		draw_circle(Vector2(cx + ox * unit, cy - unit * 0.10), unit * 0.012, Color("#ffe040"))


func _draw_tengu(cx: float, cy: float, unit: float, col: Color) -> void:
	## Corps ailé + long nez caractéristique
	## Ailes
	for side in [-1.0, 1.0]:
		var wing := PackedVector2Array([
			Vector2(cx, cy - unit * 0.05),
			Vector2(cx + side * unit * 0.34, cy - unit * 0.22),
			Vector2(cx + side * unit * 0.30, cy + unit * 0.06),
			Vector2(cx + side * unit * 0.12, cy + unit * 0.02)
		])
		draw_colored_polygon(wing, col.darkened(0.15))
	## corps
	draw_circle(Vector2(cx, cy + unit * 0.10), unit * 0.16, col)
	## tête rouge
	draw_circle(Vector2(cx, cy - unit * 0.16), unit * 0.12, Color("#b83a2a"))
	## long nez
	_tri(Vector2(cx - unit * 0.02, cy - unit * 0.18), Vector2(cx + unit * 0.02, cy - unit * 0.14), Vector2(cx + unit * 0.20, cy - unit * 0.16), Color("#c84a3a"))
	## yeux
	draw_circle(Vector2(cx - unit * 0.05, cy - unit * 0.18), unit * 0.02, Color("#201810"))


func _draw_generic_beast(cx: float, cy: float, unit: float, col: Color) -> void:
	draw_circle(Vector2(cx, cy + unit * 0.08), unit * 0.22, col)
	draw_circle(Vector2(cx, cy - unit * 0.16), unit * 0.14, col.lightened(0.1))
	_tri(Vector2(cx - unit * 0.14, cy - unit * 0.22), Vector2(cx - unit * 0.04, cy - unit * 0.22), Vector2(cx - unit * 0.12, cy - unit * 0.36), col)
	_tri(Vector2(cx + unit * 0.04, cy - unit * 0.22), Vector2(cx + unit * 0.14, cy - unit * 0.22), Vector2(cx + unit * 0.12, cy - unit * 0.36), col)


## ─────────────────────────────────────────────────────────────────────────────
## Dragon : corps serpentin ondulant + tête cornue + crinière.
## ─────────────────────────────────────────────────────────────────────────────
func _draw_dragon(cx: float, cy: float, unit: float, body_color: Color) -> void:
	var dark := body_color.darkened(0.2)
	var light := body_color.lightened(0.2)
	## Corps ondulant (segments décroissants)
	var segs := 8
	var last_pos := Vector2(cx, cy)
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var px := cx - unit * 0.30 + t * unit * 0.50
		var py := cy + unit * 0.20 - sin(t * PI * 1.8) * unit * 0.26
		var r := unit * 0.10 * (1.0 - t * 0.4)
		draw_circle(Vector2(px, py), r, body_color if i % 2 == 0 else dark)
		## épines dorsales
		if i < segs:
			_tri(Vector2(px - r * 0.4, py - r), Vector2(px + r * 0.4, py - r), Vector2(px, py - r * 2.0), light)
		last_pos = Vector2(px, py)
	## Tête (au sommet du dernier segment)
	var head := last_pos + Vector2(unit * 0.04, -unit * 0.04)
	draw_circle(head, unit * 0.11, light)
	## museau
	_tri(head + Vector2(-unit * 0.02, -unit * 0.02), head + Vector2(-unit * 0.02, unit * 0.04), head + Vector2(unit * 0.16, 0), light)
	## cornes
	_draw_line_w(head + Vector2(-unit * 0.04, -unit * 0.06), head + Vector2(-unit * 0.12, -unit * 0.18), dark, 2.5)
	_draw_line_w(head + Vector2(unit * 0.02, -unit * 0.07), head + Vector2(-unit * 0.02, -unit * 0.20), dark, 2.5)
	## œil
	draw_circle(head + Vector2(unit * 0.02, -unit * 0.01), unit * 0.02, Color("#ffe040"))
	## moustaches de dragon
	_draw_line_w(head + Vector2(unit * 0.12, 0), head + Vector2(unit * 0.26, unit * 0.06), light, 1.5)
	_draw_line_w(head + Vector2(unit * 0.12, unit * 0.02), head + Vector2(unit * 0.24, unit * 0.14), light, 1.5)


func _draw_aura(cx: float, cy: float, unit: float) -> void:
	## Halo doré rayonnant derrière le personnage
	var gold := Color("#ffdf7a", 0.45)
	var gold_soft := Color("#ffe9a8", 0.25)
	draw_circle(Vector2(cx, cy), unit * 0.40, gold_soft)
	for i in range(16):
		var a := TAU * float(i) / 16.0
		var inner := unit * 0.34
		var outer := unit * (0.44 if i % 2 == 0 else 0.40)
		draw_line(
			Vector2(cx + cos(a) * inner, cy + sin(a) * inner),
			Vector2(cx + cos(a) * outer, cy + sin(a) * outer),
			gold, 2.5
		)


## ─── Armes (dessins génériques originaux, plus détaillés) ─────────────────────

func _draw_weapon(art_rect: Rect2, unit: float) -> void:
	var weapon: String = _stone.get("weapon", "none")
	if weapon == "none":
		return

	## Position de l'arme : côté droit du personnage
	var hx := art_rect.position.x + art_rect.size.x * 0.74
	var hy := art_rect.position.y + art_rect.size.y * 0.52
	var steel := Color("#d2d6de")
	var steel_dark := Color("#8a909a")
	var wood := Color("#6a4a2a")
	var gold := Color("#e0c050")

	match weapon:
		"katana", "katana_legendary", "dual_swords":
			var blade_col := steel if weapon == "katana" else gold
			## lame (deux traits pour un biseau)
			_draw_line_w(Vector2(hx, hy + unit * 0.26), Vector2(hx + unit * 0.04, hy - unit * 0.34), blade_col, 4.0)
			_draw_line_w(Vector2(hx + unit * 0.015, hy + unit * 0.24), Vector2(hx + unit * 0.05, hy - unit * 0.32), steel_dark, 1.0)
			## garde (tsuba)
			draw_circle(Vector2(hx - unit * 0.005, hy + unit * 0.24), unit * 0.035, gold)
			## poignée tressée
			_draw_line_w(Vector2(hx - unit * 0.01, hy + unit * 0.24), Vector2(hx - unit * 0.03, hy + unit * 0.36), Color("#3a2a1a"), unit * 0.03)
			if weapon == "dual_swords":
				_draw_line_w(Vector2(hx - unit * 0.40, hy + unit * 0.26), Vector2(hx - unit * 0.44, hy - unit * 0.30), steel, 4.0)
				draw_circle(Vector2(hx - unit * 0.40, hy + unit * 0.24), unit * 0.03, gold)
		"yari", "naginata", "naginata_celestial", "bo":
			var shaft_top := Vector2(hx, hy - unit * 0.38)
			var shaft_bot := Vector2(hx, hy + unit * 0.34)
			_draw_line_w(shaft_top, shaft_bot, wood, 4.5)
			## reflets bois
			_draw_line_w(shaft_top, shaft_bot, wood.lightened(0.2), 1.0)
			if weapon != "bo":
				var tip := gold if weapon == "naginata_celestial" else steel
				if weapon == "naginata" or weapon == "naginata_celestial":
					## lame courbe de naginata
					var blade := PackedVector2Array([
						Vector2(hx, shaft_top.y),
						Vector2(hx + unit * 0.02, shaft_top.y - unit * 0.14),
						Vector2(hx + unit * 0.12, shaft_top.y - unit * 0.06),
						Vector2(hx + unit * 0.02, shaft_top.y + unit * 0.02)
					])
					draw_colored_polygon(blade, tip)
				else:
					## pointe droite de yari
					_tri(Vector2(hx - unit * 0.04, shaft_top.y), Vector2(hx + unit * 0.04, shaft_top.y), Vector2(hx, shaft_top.y - unit * 0.16), tip)
		"yumi":
			## grand arc asymétrique + corde + flèche
			draw_arc(Vector2(hx + unit * 0.14, hy), unit * 0.34, PI * 0.55, PI * 1.45, 20, wood, 3.5)
			_draw_line_w(Vector2(hx, hy - unit * 0.30), Vector2(hx, hy + unit * 0.30), Color("#e8dcc0"), 1.5)
			## flèche encochée
			_draw_line_w(Vector2(hx, hy), Vector2(hx - unit * 0.18, hy), Color("#c8a070"), 1.5)
			_tri(Vector2(hx - unit * 0.18, hy - unit * 0.02), Vector2(hx - unit * 0.18, hy + unit * 0.02), Vector2(hx - unit * 0.24, hy), steel)
		"kunai", "tanto":
			## lame courte losange + manche enveloppé
			var blade := PackedVector2Array([
				Vector2(hx - unit * 0.05, hy + unit * 0.08),
				Vector2(hx + unit * 0.05, hy + unit * 0.08),
				Vector2(hx, hy - unit * 0.22)
			])
			draw_colored_polygon(blade, steel)
			_draw_line_w(Vector2(hx, hy + unit * 0.08), Vector2(hx, hy + unit * 0.26), Color("#3a2a1a"), unit * 0.035)
			draw_circle(Vector2(hx, hy + unit * 0.26), unit * 0.02, gold)  ## anneau du kunai
		"kanabo", "kanabo_large":
			var scl := 1.0 if weapon == "kanabo" else 1.45
			var club_top := Vector2(hx, hy - unit * 0.30 * scl)
			var club_bot := Vector2(hx, hy + unit * 0.24)
			## manche
			_draw_line_w(club_bot, Vector2(hx, hy + unit * 0.02), wood, unit * 0.04)
			## tête de massue (rectangle épais)
			draw_rect(Rect2(hx - unit * 0.06 * scl, club_top.y, unit * 0.12 * scl, unit * 0.34 * scl), wood.darkened(0.1), true)
			## rangées de pointes métalliques
			for row in range(4):
				var py := club_top.y + unit * 0.06 * scl * row + unit * 0.03
				_tri(Vector2(hx + unit * 0.06 * scl, py), Vector2(hx + unit * 0.06 * scl, py + unit * 0.03), Vector2(hx + unit * 0.12 * scl, py + unit * 0.015), steel)
				_tri(Vector2(hx - unit * 0.06 * scl, py), Vector2(hx - unit * 0.06 * scl, py + unit * 0.03), Vector2(hx - unit * 0.12 * scl, py + unit * 0.015), steel)
		"tessen":
			## éventail de guerre déployé avec nervures
			var center := Vector2(hx, hy + unit * 0.20)
			var fan := PackedVector2Array()
			fan.append(center)
			for i in range(7):
				var a := -PI * 0.78 + (PI * 0.56) * float(i) / 6.0
				fan.append(center + Vector2(cos(a), sin(a)) * unit * 0.30)
			draw_colored_polygon(fan, gold)
			## nervures
			for i in range(7):
				var a := -PI * 0.78 + (PI * 0.56) * float(i) / 6.0
				_draw_line_w(center, center + Vector2(cos(a), sin(a)) * unit * 0.30, wood.darkened(0.2), 1.0)
		"drums":
			## tambours du tonnerre en arc
			for i in range(3):
				var a := -0.6 + i * 0.6
				var dp := Vector2(hx + sin(a) * unit * 0.22, hy - cos(a) * unit * 0.22)
				draw_circle(dp, unit * 0.07, Color("#9a2a2a"))
				draw_arc(dp, unit * 0.07, 0, TAU, 16, gold, 2.0)
		"windbag":
			## grand sac de vent noué
			draw_circle(Vector2(hx, hy + unit * 0.02), unit * 0.16, Color("#8a9aa0"))
			draw_circle(Vector2(hx, hy + unit * 0.02), unit * 0.16, Color("#6a7a80"))
			_draw_line_w(Vector2(hx - unit * 0.1, hy - unit * 0.12), Vector2(hx + unit * 0.1, hy - unit * 0.12), Color("#5a4a2a"), 2.0)
			## tourbillon de vent
			draw_arc(Vector2(hx - unit * 0.18, hy - unit * 0.04), unit * 0.08, 0, PI * 1.5, 12, Color("#c8d8e0"), 1.5)


## ─── Dessin du nom ────────────────────────────────────────────────────────────

func _draw_name(name_rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var fsize := int(name_rect.size.y * 0.55)
	fsize = clamp(fsize, 8, 22)
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


## ─── Helpers de dessin ────────────────────────────────────────────────────────

func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c]), col)


func _draw_line_w(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, col, w)


## Redessine quand la taille change
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == Control.NOTIFICATION_SCROLL_BEGIN:
		_tap.cancel()
	elif what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_tap.reset()
