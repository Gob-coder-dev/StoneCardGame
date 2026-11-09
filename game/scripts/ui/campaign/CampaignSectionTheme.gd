## CampaignSectionTheme.gd
## Découpe visuelle de la carte de campagne. Les treize chapitres du graphe
## deviennent des bandes contiguës, avec une teinte et un motif propres. Les
## frontières suivent les médianes des nœuds : elles restent stables même quand
## les plages verticales de deux chapitres se chevauchent.
class_name CampaignSectionTheme
extends RefCounted

const MOTIF_GATE := "gate"
const MOTIF_SIGIL := "sigil"
const MOTIF_FORK := "fork"
const MOTIF_REEDS := "reeds"
const MOTIF_STRATA := "strata"
const MOTIF_SHELVES := "shelves"
const MOTIF_LANTERNS := "lanterns"
const MOTIF_LEAVES := "leaves"
const MOTIF_BATTLEMENTS := "battlements"
const MOTIF_ECHOES := "echoes"
const MOTIF_MASKS := "masks"
const MOTIF_ASH := "ash"
const MOTIF_PEAKS := "peaks"

## Les noms correspondent exactement au champ `chapter` de campaign_v2.json.
## Les teintes restent très sombres : CampaignSectionArt les applique avec un
## alpha partiel au-dessus du fond charbon partagé, pour ne jamais concurrencer
## les nœuds, les courbes et les labels.
const SECTIONS: Array[Dictionary] = [
	{"chapter": "Seuil", "tint": "#171a22", "accent": "#8f86b8", "motif": MOTIF_GATE},
	{"chapter": "Initiations", "tint": "#1a1622", "accent": "#a07ac4", "motif": MOTIF_SIGIL},
	{"chapter": "Carrefour", "tint": "#1e1a17", "accent": "#b07a55", "motif": MOTIF_FORK},
	{"chapter": "Le Marais des Serments", "tint": "#121d1b", "accent": "#5f9e8c", "motif": MOTIF_REEDS},
	{"chapter": "Les Forges Basses", "tint": "#201612", "accent": "#b06a45", "motif": MOTIF_STRATA},
	{"chapter": "La Bibliothèque des Os", "tint": "#1c1a17", "accent": "#b8a98c", "motif": MOTIF_SHELVES},
	{"chapter": "Le Marché Nocturne", "tint": "#1e151d", "accent": "#a56a8e", "motif": MOTIF_LANTERNS},
	{"chapter": "Les Serres de Verre", "tint": "#141d18", "accent": "#6fa88a", "motif": MOTIF_LEAVES},
	{"chapter": "Les Remparts Muets", "tint": "#151a20", "accent": "#7189a6", "motif": MOTIF_BATTLEMENTS},
	{"chapter": "Le Puits des Échos", "tint": "#141522", "accent": "#7a78b8", "motif": MOTIF_ECHOES},
	{"chapter": "La Cour des Masques", "tint": "#1f141a", "accent": "#b06a86", "motif": MOTIF_MASKS},
	{"chapter": "Les Jardins de Cendre", "tint": "#1b1816", "accent": "#9a8f80", "motif": MOTIF_ASH},
	{"chapter": "Cime", "tint": "#1d1a14", "accent": "#b8a06a", "motif": MOTIF_PEAKS},
]


## Construit les bandes visuelles dans l'ordre vertical du graphe. La première
## bande couvre le haut de la carte et la dernière va jusqu'à la marge basse.
static func build(graph: CampaignGraph) -> Array:
	var result: Array = []
	if graph == null or graph.node_count() == 0:
		return result
	var grouped: Dictionary = {}
	for node_variant in graph.nodes():
		var node := node_variant as CampaignNode
		if node == null:
			continue
		var chapter: String = node.chapter if node.chapter != "" else "Campagne"
		if not grouped.has(chapter):
			grouped[chapter] = {
				"chapter": chapter,
				"ys": [],
			}
		var entry: Dictionary = grouped[chapter]
		(entry["ys"] as Array).append(node.position.y)
	var chapters: Array = grouped.values()
	for entry in chapters:
		var ys: Array = entry["ys"]
		ys.sort()
		entry["median_y"] = float(ys[int(float(ys.size()) * 0.5)])
	chapters.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_y := float(first["median_y"])
		var second_y := float(second["median_y"])
		if is_equal_approx(first_y, second_y):
			return str(first["chapter"]) < str(second["chapter"])
		return first_y < second_y)
	var map_bottom := graph.map_size.y + UITheme.CAMPAIGN_BOTTOM_PAD
	var top := 0.0
	for index in range(chapters.size()):
		var entry: Dictionary = chapters[index]
		var bottom := map_bottom
		if index + 1 < chapters.size():
			bottom = (float(entry["median_y"])
				+ float(chapters[index + 1]["median_y"])) * 0.5
		var palette := _palette_for(str(entry["chapter"]), index)
		result.append({
			"chapter": str(entry["chapter"]),
			"top": top,
			"bottom": bottom,
			"median_y": float(entry["median_y"]),
			"tint": Color(str(palette["tint"])),
			"accent": Color(str(palette["accent"])),
			"motif": str(palette["motif"]),
		})
		top = bottom
	return result


## Une section renommée garde une palette de secours au lieu de disparaître.
static func _palette_for(chapter: String, index: int) -> Dictionary:
	for palette in SECTIONS:
		if str(palette["chapter"]) == chapter:
			return palette
	return SECTIONS[index % SECTIONS.size()]
