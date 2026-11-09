## CampaignSectionArt.gd
## Dessin procédural du fond de section de la carte de campagne. Aucune texture
## et aucun Control supplémentaire : les bandes, l'emblème central et les motifs
## de bord sont tracés dans le repère logique de la carte, puis projetés par la
## transformation du canevas. Seules les sections proches du viewport sont
## parcourues, donc le coût ne dépend pas de la longueur totale de la carte.
class_name CampaignSectionArt
extends RefCounted

const SectionTheme := preload("res://scripts/ui/campaign/CampaignSectionTheme.gd")

## Budget de lisibilité : les teintes restent des aplats très sombres, les
## motifs de bord et l'emblème central ne doivent jamais concurrencer les nœuds,
## les courbes ni les labels de chapitre.
const TINT_ALPHA := 0.46
const EDGE_ALPHA := 0.13
const CENTER_ALPHA := 0.055

## Le fondu est centré sur la frontière : la section entrante commence à
## recouvrir la précédente un peu avant la limite, puis devient pleine.
const BAND_FADE := 240.0
const BAND_STRIPS := 12

## Les filets néon partagés restent aux deux bords de l'écran : la teinte de
## section s'arrête avant eux et s'efface horizontalement pour ne pas les
## recolorer ni créer de bord franc. Le retrait reste faible car la vue de carte
## est déjà en marge des filets ; il garantit seulement qu'aucune teinte ne les
## atteint sur les écrans très larges. Le fondu latéral est volontairement moins
## fin que le fondu vertical : sur une teinte aussi sombre, six paliers suffisent
## et le coût de dessin reste faible pendant le défilement.
const BAND_LEFT := 16.0
const BAND_RIGHT := 1064.0
const BAND_EDGE_FADE := 64.0
const SIDE_STRIPS := 6

## Rythme des motifs de bord. Les emblèmes restent espacés pour ne pas créer de
## motif continu qui attirerait l'œil pendant le défilement.
const MOTIF_SPACING := 420.0
const MOTIF_MARGIN := 220.0
const EDGE_X_LEFT := 92.0
const EDGE_X_RIGHT := 988.0
const CENTER_X := 540.0
const EDGE_MOTIF_SIZE := 46.0
const CENTER_MOTIF_SIZE := 230.0
const CULL_MARGIN := 600.0


## Dessine le fond complet d'une carte. `visible_rect` est exprimé dans le
## repère logique (1080 unités de large), comme les positions des nœuds.
static func draw_backdrop(canvas: CanvasItem, sections: Array, scale: float,
		visible_rect: Rect2) -> void:
	if canvas == null or sections.is_empty() or scale <= 0.0:
		return
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale, scale))
	var cull := _cull_rect(sections, visible_rect)
	# Deux passes : toutes les bandes d'abord, puis les motifs, pour qu'un fondu
	# de frontière ne recouvre jamais l'emblème ou les motifs d'une section voisine.
	for index in range(sections.size()):
		var section: Dictionary = sections[index]
		if not _intersects(section, cull):
			continue
		_draw_band(canvas, section, index == 0, index == sections.size() - 1)
	for index in range(sections.size()):
		var section: Dictionary = sections[index]
		if not _intersects(section, cull):
			continue
		_draw_section_art(canvas, section, cull)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Sans viewport connu (première image), on couvre toute la carte pour ne pas
## laisser de trou avant le premier calcul de défilement.
static func _cull_rect(sections: Array, visible_rect: Rect2) -> Rect2:
	if visible_rect.size.y > 0.0:
		return visible_rect.grow(CULL_MARGIN)
	var last: Dictionary = sections[sections.size() - 1]
	return Rect2(0.0, 0.0, UITheme.CAMPAIGN_MAP_WIDTH,
		float(last.get("bottom", 0.0)) + CULL_MARGIN)


static func _intersects(section: Dictionary, cull: Rect2) -> bool:
	var top := float(section.get("top", 0.0)) - BAND_FADE
	var bottom := float(section.get("bottom", 0.0)) + BAND_FADE
	return bottom >= cull.position.y and top <= cull.end.y


## Une bande est un aplat sombre avec un fondu entrant et sortant. Deux bandes
## voisines se croisent donc sur `BAND_FADE` unités : la précédente s'efface
## pendant que la suivante apparaît, sans marche visible à la frontière.
static func _draw_band(canvas: CanvasItem, section: Dictionary, first: bool,
		last: bool) -> void:
	var top := float(section.get("top", 0.0))
	var bottom := float(section.get("bottom", 0.0))
	if bottom <= top:
		return
	var tint: Color = section.get("tint", Color.TRANSPARENT)
	var half_fade := BAND_FADE * 0.5
	var solid_top := top if first else top + half_fade
	var solid_bottom := bottom if last else bottom - half_fade
	if solid_bottom > solid_top:
		_fill_band(canvas, tint, solid_top, solid_bottom - solid_top, TINT_ALPHA)
	if not first:
		_draw_fade(canvas, tint, top - half_fade, top + half_fade,
			0.0, TINT_ALPHA)
	if not last:
		_draw_fade(canvas, tint, bottom - half_fade, bottom + half_fade,
			TINT_ALPHA, 0.0)


static func _draw_fade(canvas: CanvasItem, tint: Color, start_y: float,
		end_y: float, from_alpha: float, to_alpha: float) -> void:
	var strip_height := (end_y - start_y) / float(BAND_STRIPS)
	for step in range(BAND_STRIPS):
		var weight := (float(step) + 0.5) / float(BAND_STRIPS)
		var alpha := lerpf(from_alpha, to_alpha, weight)
		if alpha <= 0.0:
			continue
		_fill_band(canvas, tint, start_y + strip_height * float(step),
			strip_height + 0.5, alpha)


## Remplit une tranche verticale en effaçant la teinte sur les deux bords : les
## filets néon partagés restent ainsi à leur couleur d'origine, et la transition
## vers le fond charbon ne forme pas de bord franc.
static func _fill_band(canvas: CanvasItem, tint: Color, y: float, height: float,
		alpha: float) -> void:
	if alpha <= 0.0 or height <= 0.0:
		return
	var inner_left := BAND_LEFT + BAND_EDGE_FADE
	var inner_right := BAND_RIGHT - BAND_EDGE_FADE
	if inner_right > inner_left:
		var ink := tint
		ink.a = alpha
		canvas.draw_rect(Rect2(inner_left, y, inner_right - inner_left, height),
			ink)
	_draw_side_fade(canvas, tint, BAND_LEFT, inner_left, y, height, 0.0, alpha)
	_draw_side_fade(canvas, tint, inner_right, BAND_RIGHT, y, height, alpha, 0.0)


static func _draw_side_fade(canvas: CanvasItem, tint: Color, start_x: float,
		end_x: float, y: float, height: float, from_alpha: float,
		to_alpha: float) -> void:
	var strip_width := (end_x - start_x) / float(SIDE_STRIPS)
	for step in range(SIDE_STRIPS):
		var weight := (float(step) + 0.5) / float(SIDE_STRIPS)
		var alpha := lerpf(from_alpha, to_alpha, weight)
		if alpha <= 0.0:
			continue
		var ink := tint
		ink.a = alpha
		canvas.draw_rect(Rect2(start_x + strip_width * float(step), y,
			strip_width + 0.5, height), ink)


## Un grand emblème en contour à la médiane des nœuds, puis de petits motifs
## répétés dans les marges. Les deux restent très pâles et uniquement linéaires.
static func _draw_section_art(canvas: CanvasItem, section: Dictionary,
		cull: Rect2) -> void:
	var accent: Color = section.get("accent", Color.WHITE)
	var motif := str(section.get("motif", SectionTheme.MOTIF_SIGIL))
	var median_y := float(section.get("median_y", 0.0))
	if median_y >= cull.position.y - CENTER_MOTIF_SIZE \
			and median_y <= cull.end.y + CENTER_MOTIF_SIZE:
		var center_ink := accent
		center_ink.a = CENTER_ALPHA
		_draw_motif(canvas, motif, Vector2(CENTER_X, median_y),
			CENTER_MOTIF_SIZE, center_ink, false)
	var edge_ink := accent
	edge_ink.a = EDGE_ALPHA
	var top := float(section.get("top", 0.0)) + MOTIF_MARGIN
	var bottom := float(section.get("bottom", 0.0)) - MOTIF_MARGIN
	var y := top
	while y < bottom:
		if y >= cull.position.y - EDGE_MOTIF_SIZE \
				and y <= cull.end.y + EDGE_MOTIF_SIZE:
			_draw_motif(canvas, motif, Vector2(EDGE_X_LEFT, y),
				EDGE_MOTIF_SIZE, edge_ink, false)
			_draw_motif(canvas, motif, Vector2(EDGE_X_RIGHT, y),
				EDGE_MOTIF_SIZE, edge_ink, true)
		y += MOTIF_SPACING


static func _draw_motif(canvas: CanvasItem, motif: String, center: Vector2,
		size: float, ink: Color, mirror: bool) -> void:
	match motif:
		SectionTheme.MOTIF_GATE:
			_gate(canvas, center, size, ink)
		SectionTheme.MOTIF_SIGIL:
			_sigil(canvas, center, size, ink)
		SectionTheme.MOTIF_FORK:
			_fork(canvas, center, size, ink, mirror)
		SectionTheme.MOTIF_REEDS:
			_reeds(canvas, center, size, ink, mirror)
		SectionTheme.MOTIF_STRATA:
			_strata(canvas, center, size, ink)
		SectionTheme.MOTIF_SHELVES:
			_shelves(canvas, center, size, ink)
		SectionTheme.MOTIF_LANTERNS:
			_lanterns(canvas, center, size, ink, mirror)
		SectionTheme.MOTIF_LEAVES:
			_leaves(canvas, center, size, ink, mirror)
		SectionTheme.MOTIF_BATTLEMENTS:
			_battlements(canvas, center, size, ink)
		SectionTheme.MOTIF_ECHOES:
			_echoes(canvas, center, size, ink)
		SectionTheme.MOTIF_MASKS:
			_masks(canvas, center, size, ink)
		SectionTheme.MOTIF_ASH:
			_ash(canvas, center, size, ink, mirror)
		SectionTheme.MOTIF_PEAKS:
			_peaks(canvas, center, size, ink)
		_:
			_sigil(canvas, center, size, ink)


static func _point(center: Vector2, x: float, y: float, mirror: bool) -> Vector2:
	return center + Vector2(-x if mirror else x, y)


static func _diamond(canvas: CanvasItem, center: Vector2, radius: float,
		ink: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
		center + Vector2(0.0, -radius),
	])
	canvas.draw_polyline(points, ink, 1.6, true)


## Arche du Seuil : ouverture, montants et marches.
static func _gate(canvas: CanvasItem, center: Vector2, size: float,
		ink: Color) -> void:
	var half := size * 0.42
	var spring := -size * 0.15
	var foot := size * 0.45
	canvas.draw_arc(center + Vector2(0.0, spring), half, PI, TAU, 18, ink, 2.0, true)
	canvas.draw_line(center + Vector2(-half, spring),
		center + Vector2(-half, foot), ink, 2.0, true)
	canvas.draw_line(center + Vector2(half, spring),
		center + Vector2(half, foot), ink, 2.0, true)
	for step in range(3):
		var y := foot + size * 0.12 * float(step)
		var width := half * (1.25 - 0.18 * float(step))
		canvas.draw_line(center + Vector2(-width, y),
			center + Vector2(width, y), ink, 1.6, true)


## Sigil brisé des Initiations : six rayons et un anneau interrompu.
static func _sigil(canvas: CanvasItem, center: Vector2, size: float,
		ink: Color) -> void:
	for index in range(6):
		var angle := TAU * float(index) / 6.0 - PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		canvas.draw_line(center + direction * size * 0.28,
			center + direction * size * 0.62, ink, 1.8, true)
	for index in range(6):
		var start := TAU * float(index) / 6.0 - PI * 0.5 + 0.18
		var finish := TAU * float(index + 1) / 6.0 - PI * 0.5 - 0.18
		canvas.draw_arc(center, size * 0.62, start, finish, 6, ink, 1.6, true)


## Bifurcations du Carrefour.
static func _fork(canvas: CanvasItem, center: Vector2, size: float, ink: Color,
		mirror: bool) -> void:
	var joint := _point(center, 0.0, -size * 0.05, mirror)
	canvas.draw_line(_point(center, 0.0, size * 0.65, mirror), joint, ink, 2.0, true)
	canvas.draw_line(joint, _point(center, -size * 0.5, -size * 0.6, mirror),
		ink, 2.0, true)
	canvas.draw_line(joint, _point(center, size * 0.5, -size * 0.6, mirror),
		ink, 2.0, true)
	_diamond(canvas, _point(center, 0.0, size * 0.65, mirror), size * 0.12, ink)
	_diamond(canvas, _point(center, -size * 0.5, -size * 0.6, mirror),
		size * 0.09, ink)
	_diamond(canvas, _point(center, size * 0.5, -size * 0.6, mirror),
		size * 0.09, ink)


## Roseaux du Marais des Serments.
static func _reeds(canvas: CanvasItem, center: Vector2, size: float, ink: Color,
		mirror: bool) -> void:
	for index in range(4):
		var offset := (float(index) - 1.5) * size * 0.22
		var base := _point(center, offset, size * 0.65, mirror)
		var tip := _point(center, offset * 1.35, -size * 0.65, mirror)
		canvas.draw_line(base, tip, ink, 1.8, true)
		var anchor := base.lerp(tip, 0.55)
		var side := 1.0 if index % 2 == 0 else -1.0
		if mirror:
			side = -side
		canvas.draw_line(anchor, anchor + Vector2(side * size * 0.18,
			-size * 0.22), ink, 1.6, true)


## Strates minérales des Forges Basses.
static func _strata(canvas: CanvasItem, center: Vector2, size: float,
		ink: Color) -> void:
	for index in range(4):
		var y := (float(index) - 1.5) * size * 0.3
		var width := size * (0.55 + 0.08 * float(index % 2))
		var points := PackedVector2Array([
			center + Vector2(-width, y),
			center + Vector2(-width * 0.35, y - size * 0.06),
			center + Vector2(width * 0.35, y + size * 0.06),
			center + Vector2(width, y),
		])
		canvas.draw_polyline(points, ink, 1.8, true)


## Rayonnages de la Bibliothèque des Os.
static func _shelves(canvas: CanvasItem, center: Vector2, size: float,
		ink: Color) -> void:
	for index in range(3):
		var radius := size * (0.26 + 0.18 * float(index))
		canvas.draw_arc(center + Vector2(0.0, size * 0.35), radius, PI, TAU,
			20, ink, 1.8, true)
	var foot := size * 0.35
	canvas.draw_line(center + Vector2(-size * 0.62, foot),
		center + Vector2(size * 0.62, foot), ink, 1.8, true)
	for x in [-0.62, -0.2, 0.2, 0.62]:
		canvas.draw_line(center + Vector2(size * x, foot),
			center + Vector2(size * x, size * 0.62), ink, 1.4, true)


## Lanternes du Marché Nocturne.
static func _lanterns(canvas: CanvasItem, center: Vector2, size: float,
		ink: Color, mirror: bool) -> void:
	for index in range(2):
		var x := (-0.3 if index == 0 else 0.32) * size
		var top := -size * 0.65 + float(index) * size * 0.18
		canvas.draw_line(_point(center, x, top, mirror),
			_point(center, x, top + size * 0.14, mirror), ink, 1.6, true)
		var body := _point(center, x, top + size * 0.32, mirror)
		_diamond(canvas, body, size * 0.14, ink)
		canvas.draw_circle(body, size * 0.035, ink)


## Feuilles géométriques des Serres de Verre.
static func _leaves(canvas: CanvasItem, center: Vector2, size: float, ink: Color,
		mirror: bool) -> void:
	for index in range(3):
		var angle := -0.9 + float(index) * 0.9
		var direction := Vector2(cos(angle), sin(angle))
		if mirror:
			direction.x = -direction.x
		var origin := center + Vector2(0.0, size * 0.45)
		var tip := origin + direction * size * 0.95
		var normal := Vector2(-direction.y, direction.x) * size * 0.22
		var middle := origin.lerp(tip, 0.5)
		var points := PackedVector2Array([
			origin,
			middle + normal,
			tip,
			middle - normal,
			origin,
		])
		canvas.draw_polyline(points, ink, 1.6, true)


## Créneaux des Remparts Muets.
static func _battlements(canvas: CanvasItem, center: Vector2, size: float,
		ink: Color) -> void:
	var base := size * 0.45
	var height := size * 0.22
	var left := -size * 0.7
	var steps := 4
	var step_width := size * 1.4 / float(steps)
	var points := PackedVector2Array([center + Vector2(left, base)])
	for index in range(steps):
		var x := left + step_width * float(index)
		points.append(center + Vector2(x, base - height))
		points.append(center + Vector2(x + step_width * 0.55, base - height))
		points.append(center + Vector2(x + step_width * 0.55, base))
		points.append(center + Vector2(x + step_width, base))
	canvas.draw_polyline(points, ink, 1.8, true)
	canvas.draw_line(center + Vector2(-size * 0.75, size * 0.65),
		center + Vector2(size * 0.75, size * 0.65), ink, 1.4, true)


## Cercles incomplets du Puits des Échos.
static func _echoes(canvas: CanvasItem, center: Vector2, size: float,
		ink: Color) -> void:
	for index in range(3):
		var radius := size * (0.2 + 0.2 * float(index))
		var start := 0.35 + float(index) * 0.25
		canvas.draw_arc(center, radius, start, TAU - start * 0.6, 24, ink, 1.8, true)
	canvas.draw_circle(center, size * 0.035, ink)


## Masques de la Cour : ovale, yeux et bouche.
static func _masks(canvas: CanvasItem, center: Vector2, size: float,
		ink: Color) -> void:
	var outline := PackedVector2Array()
	var radius_x := size * 0.5
	var radius_y := size * 0.62
	for index in range(25):
		var angle := TAU * float(index) / 24.0
		outline.append(center + Vector2(cos(angle) * radius_x,
			sin(angle) * radius_y))
	canvas.draw_polyline(outline, ink, 1.8, true)
	canvas.draw_line(center + Vector2(-size * 0.22, -size * 0.12),
		center + Vector2(-size * 0.08, -size * 0.12), ink, 2.0, true)
	canvas.draw_line(center + Vector2(size * 0.08, -size * 0.12),
		center + Vector2(size * 0.22, -size * 0.12), ink, 2.0, true)
	canvas.draw_arc(center + Vector2(0.0, size * 0.18), size * 0.16, 0.25,
		PI - 0.25, 12, ink, 1.6, true)


## Branches nues des Jardins de Cendre.
static func _ash(canvas: CanvasItem, center: Vector2, size: float, ink: Color,
		mirror: bool) -> void:
	var base := _point(center, 0.0, size * 0.7, mirror)
	var tip := _point(center, 0.0, -size * 0.7, mirror)
	canvas.draw_line(base, tip, ink, 2.0, true)
	for index in range(3):
		var anchor := base.lerp(tip, 0.32 + 0.2 * float(index))
		var side := 1.0 if index % 2 == 0 else -1.0
		if mirror:
			side = -side
		var branch := anchor + Vector2(side * size * 0.38, -size * 0.28)
		canvas.draw_line(anchor, branch, ink, 1.6, true)
		canvas.draw_line(branch, branch + Vector2(side * size * 0.12,
			-size * 0.16), ink, 1.3, true)


## Pics de la Cime.
static func _peaks(canvas: CanvasItem, center: Vector2, size: float,
		ink: Color) -> void:
	var base := size * 0.55
	var peaks := [
		{"x": -0.45, "h": 0.55},
		{"x": 0.0, "h": 0.85},
		{"x": 0.42, "h": 0.62},
	]
	for peak in peaks:
		var x := float(peak["x"]) * size
		var height := float(peak["h"]) * size
		var points := PackedVector2Array([
			center + Vector2(x - size * 0.32, base),
			center + Vector2(x, base - height),
			center + Vector2(x + size * 0.32, base),
		])
		canvas.draw_polyline(points, ink, 1.8, true)
	canvas.draw_line(center + Vector2(-size * 0.75, base),
		center + Vector2(size * 0.75, base), ink, 1.4, true)
