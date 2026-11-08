## CampaignMapChunkManager.gd
## Décide quels secteurs spatiaux doivent être chargés. Il ne crée aucun
## Control : il traduit le rectangle visible en identifiants de nœuds, avec une
## marge de préchargement et une marge de conservation plus large (hystérésis).
class_name CampaignMapChunkManager
extends RefCounted

## Secteur logique : deux colonnes sur la largeur de référence et des tranches
## assez fines pour précharger une bande avant qu'elle devienne visible.
const CHUNK_SIZE := Vector2(540.0, 720.0)
const PRELOAD_AHEAD := 0.75
const RETAIN_AHEAD := 1.75

var _graph: CampaignGraph = null
var _node_chunks: Dictionary = {}
var _chunk_nodes: Dictionary = {}
var _active_chunks: Dictionary = {}
var _last_visible := Rect2()


func _init(graph: CampaignGraph = null) -> void:
	_graph = graph
	if _graph == null:
		return
	for node in _graph.nodes():
		var cell := chunk_for_point(node.position)
		_node_chunks[node.id] = cell
		if not _chunk_nodes.has(cell):
			_chunk_nodes[cell] = []
		(_chunk_nodes[cell] as Array).append(node.id)


func chunk_for_point(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CHUNK_SIZE.x), floori(point.y / CHUNK_SIZE.y))


func chunk_for_node(node_id: String) -> Vector2i:
	return _node_chunks.get(node_id, Vector2i(-1, -1))


func active_chunks() -> Array:
	return _active_chunks.keys()


func active_node_ids() -> Array:
	var result: Array = []
	for cell in _active_chunks:
		result.append_array(_chunk_nodes.get(cell, []))
	result.sort()
	return result


func chunk_node_ids(cell: Vector2i) -> Array:
	return (_chunk_nodes.get(cell, []) as Array).duplicate()


func load_rect_for(visible_rect: Rect2, viewport_logical: Vector2) -> Rect2:
	return _expanded(visible_rect, viewport_logical, PRELOAD_AHEAD)


func retain_rect_for(visible_rect: Rect2, viewport_logical: Vector2) -> Rect2:
	return _expanded(visible_rect, viewport_logical, RETAIN_AHEAD)


## Retourne les nœuds à instancier et à libérer. Un appel répété avec le même
## rectangle ne redemande rien : les demandes ne peuvent pas se dupliquer.
func update(visible_rect: Rect2, viewport_logical: Vector2) -> Dictionary:
	if _graph == null:
		return _empty_result(visible_rect)
	_last_visible = visible_rect
	var load_rect := load_rect_for(visible_rect, viewport_logical)
	var keep_rect := retain_rect_for(visible_rect, viewport_logical)
	var load_cells := _chunks_in(load_rect)
	var keep_cells := _chunks_in(keep_rect)
	var previous: Dictionary = _active_chunks.duplicate()
	var next_active: Dictionary = {}
	for cell in previous:
		if keep_cells.has(cell):
			next_active[cell] = true
	for cell in load_cells:
		next_active[cell] = true

	var add: Array = []
	var remove: Array = []
	for cell in load_cells:
		if not previous.has(cell):
			add.append_array(_chunk_nodes.get(cell, []))
	for cell in previous:
		if not next_active.has(cell):
			remove.append_array(_chunk_nodes.get(cell, []))
	_active_chunks = next_active
	add.sort()
	remove.sort()
	return {
		"add": add,
		"remove": remove,
		"load_rect": load_rect,
		"keep_rect": keep_rect,
		"active_chunks": active_chunks(),
	}


func _chunks_in(rect: Rect2) -> Dictionary:
	var result := {}
	for cell in _chunk_nodes:
		if _cell_rect(cell).intersects(rect):
			result[cell] = true
	return result


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * CHUNK_SIZE, CHUNK_SIZE)


func _expanded(visible_rect: Rect2, viewport_logical: Vector2,
		factor: float) -> Rect2:
	var horizontal := maxf(0.0, viewport_logical.x * 0.10)
	var vertical := maxf(0.0, viewport_logical.y * factor)
	return visible_rect.grow_individual(horizontal, vertical, horizontal, vertical)


func _empty_result(visible_rect: Rect2) -> Dictionary:
	return {
		"add": [],
		"remove": [],
		"load_rect": visible_rect,
		"keep_rect": visible_rect,
		"active_chunks": [],
	}