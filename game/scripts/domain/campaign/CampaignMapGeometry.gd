## Convention de géométrie logique commune au contenu et à son rendu.
## Les positions stockées sont les centres des nœuds, jamais leur coin haut-gauche.
class_name CampaignMapGeometry
extends RefCounted

const NODE_DIAMETER: int = 150
const NODE_VISUAL_PADDING: float = 25.0
const NODE_SAFE_INSET: float = NODE_DIAMETER * 0.5 + NODE_VISUAL_PADDING


## Zone dans laquelle le centre d'un nœud peut être placé sans que son
## cercle, ses effets et son interaction tactile ne soient coupés par la carte.
static func node_center_bounds(map_size: Vector2) -> Rect2:
	var horizontal_margin := minf(NODE_SAFE_INSET, map_size.x * 0.5)
	var vertical_margin := minf(NODE_SAFE_INSET, map_size.y * 0.5)
	return Rect2(Vector2(horizontal_margin, vertical_margin),
		Vector2(maxf(0.0, map_size.x - horizontal_margin * 2.0),
			maxf(0.0, map_size.y - vertical_margin * 2.0)))


static func contains_node_center(map_size: Vector2, point: Vector2) -> bool:
	var bounds := node_center_bounds(map_size)
	return point.x >= bounds.position.x and point.x <= bounds.end.x \
		and point.y >= bounds.position.y and point.y <= bounds.end.y
