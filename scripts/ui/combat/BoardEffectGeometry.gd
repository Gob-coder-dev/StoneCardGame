## Conversion des événements logiques en points du plateau. Aucun dessin ni règle.
extends RefCounted
const FACE_DIRECTIONS = StoneSide.SCREEN
const GAP = BoardView.GAP
var _board: BoardView

func _init(board: BoardView) -> void:
	_board = board

func get_global_transform() -> Transform2D:
	return _board.get_global_transform()

func _attack_point(row: int, col: int, side: String) -> Vector2:
	var first: Panel = _board.slot_at(0, 0)
	var last: Panel = _board.slot_at(GameState.BOARD_SIZE - 1, GameState.BOARD_SIZE - 1)
	if row < 0 or col < 0 or row >= GameState.BOARD_SIZE or col >= GameState.BOARD_SIZE:
		var point := first.position + first.size * 0.5 + Vector2(col, row) * (first.size.x + GAP)
		point.x = clampf(point.x, first.position.x - first.size.x * 0.10, last.position.x + last.size.x * 1.10)
		point.y = clampf(point.y, first.position.y - first.size.y * 0.10, last.position.y + last.size.y * 1.10)
		return point
	var target: StoneCard = _board.card_at(row, col)
	if target != null:
		var to_board := get_global_transform().affine_inverse() * target.get_global_transform()
		return to_board * target.face_center(StoneSide.opposite(side))
	var slot: Panel = _board.slot_at(row, col)
	return slot.position + slot.size * 0.5 - FACE_DIRECTIONS[side] * slot.size.x * 0.48

## Fusionne une cible du premier état avant au dernier état après, puis
## prépare un groupe visuel par source. Les événements du moteur restent intacts.
func weakness_groups(events: Array) -> Array:
	var merged := {}
	var order: Array = []
	for event in events:
		var key := "%d:%d" % [event["row"], event["col"]]
		if merged.has(key):
			merged[key]["weakness_after"] = event["weakness_after"]
			continue
		merged[key] = event.duplicate()
		order.append(key)
	var by_source := {}
	var sources: Array = []
	for key in order:
		var event: Dictionary = merged[key]
		var source_key := "%d:%d" % [int(event.get("source_row", -1)), int(event.get("source_col", -1))]
		if not by_source.has(source_key):
			by_source[source_key] = []
			sources.append(source_key)
		by_source[source_key].append(event)
	var result: Array = []
	for source_key in sources:
		var group: Array = by_source[source_key]
		var first: Dictionary = group[0]
		var row := int(first.get("source_row", -1))
		var col := int(first.get("source_col", -1))
		if row < 0 or col < 0:
			continue
		var source := _board.card_at(row, col)
		if source == null:
			continue
		var targets := weakness_targets(group)
		if not targets.is_empty():
			result.append({"source": source, "targets": targets})
	return result


func weakness_targets(events: Array) -> Array:
	var targets: Array = []
	for event in events:
		var row := int(event.get("row", -1))
		var col := int(event.get("col", -1))
		if row < 0 or col < 0:
			continue
		var card: StoneCard = _board.card_at(row, col)
		if card == null:
			continue
		var transform_to_board := get_global_transform().affine_inverse() * card.get_global_transform()
		targets.append({
			"card": card, "center": transform_to_board * (card.size * 0.5),
			"square": minf(card.size.x, card.size.y),
			"before": int(event.get("weakness_before", 0)),
			"after": int(event.get("weakness_after", 0))
		})
	return targets

func _swarm_visual_links(raw_links: Array, positions: Dictionary) -> Array:
	var result: Array = []
	for link_value in raw_links:
		var link: Dictionary = link_value
		var a_id := int(link.get("a_instance", -1))
		var b_id := int(link.get("b_instance", -1))
		if not positions.has(a_id) or not positions.has(b_id):
			continue
		var first: Dictionary = positions[a_id]
		var second: Dictionary = positions[b_id]
		var first_center: Vector2 = first["center"]
		var second_center: Vector2 = second["center"]
		var direction := (second_center - first_center).normalized()
		var visual: Dictionary = link.duplicate(true)
		visual["start"] = first_center + direction * float(first["square"]) * 0.40
		visual["end"] = second_center - direction * float(second["square"]) * 0.40
		visual["square"] = minf(float(first["square"]), float(second["square"]))
		result.append(visual)
	return result


## Synchronisation de secours au début d'un tour. Le résolveur fournit les
## connexions ; cette vue ne décide jamais quelles cartes appartiennent au groupe.

func _add_swarm_link_position(positions: Dictionary, instance_id: int,
	row: int, col: int) -> void:
	if positions.has(instance_id) or row < 0 or col < 0 \
		or row >= GameState.BOARD_SIZE or col >= GameState.BOARD_SIZE:
		return
	var card: StoneCard = _board.card_at(row, col)
	if card == null:
		return
	var transform_to_board := get_global_transform().affine_inverse() * card.get_global_transform()
	positions[instance_id] = {
		"center": transform_to_board * (card.size * 0.5),
		"square": minf(card.size.x, card.size.y)
	}

## Symboles volés par un Pillage, placés sur les cartes vaincues. Les indices
## du moteur décrivent la face avant le coup : ils sont lus sur la carte telle
## qu'elle est affichée, pas sur son état final.
func pillage_transfers(event: Dictionary) -> Array:
	var transfers: Array = []
	for transfer_value in event.get("transfers", []):
		var transfer: Dictionary = transfer_value
		var target: StoneCard = _board.card_at(int(transfer["row"]), int(transfer["col"]))
		if target == null or target.displayed_stone() == null:
			continue
		var side := str(transfer["defense_side"])
		var markers := target.displayed_stone().markers_for_side(side)
		var marker_index := int(transfer.get("marker_index", -1))
		if marker_index < 0 or marker_index >= markers.size():
			continue
		var to_board := get_global_transform().affine_inverse() * target.get_global_transform()
		var visual: Dictionary = transfer.duplicate()
		visual["card"] = target
		visual["side"] = side
		visual["kind"] = markers[marker_index]["kind"]
		visual["position"] = to_board * target.displayed_marker_position(side, marker_index)
		visual["face"] = to_board * target.face_center(side)
		transfers.append(visual)
	return transfers

func attack_paths(card: StoneCard, attacks: Array) -> Array:
	var to_board := get_global_transform().affine_inverse() * card.get_global_transform()
	var paths: Array = []
	for attack in attacks:
		var side := str(attack["direction"])
		var hits: Array = []
		for hit in attack["hits"]:
			var display_hit: Dictionary = hit.duplicate()
			display_hit["point"] = _attack_point(int(hit["row"]), int(hit["col"]), side)
			hits.append(display_hit)
		var markers := card.attack_markers(side, bool(attack["adjacent_enemy"]))
		for marker in markers:
			marker["position"] = to_board * marker["position"]
		var endpoint: Dictionary = attack["endpoint"]
		paths.append({"attack": attack, "direction": FACE_DIRECTIONS[side], "hits": hits, "markers": markers,
			"source_face": to_board * card.face_center(side),
			"end": _attack_point(int(endpoint["row"]), int(endpoint["col"]), side)})
	return paths

func swarm_data(event: Dictionary) -> Dictionary:
	var members: Array = []
	var positions := {}
	for member_value in event.get("members", []):
		var member: Dictionary = member_value
		var row := int(member.get("row", -1))
		var col := int(member.get("col", -1))
		if row < 0 or col < 0 or row >= GameState.BOARD_SIZE or col >= GameState.BOARD_SIZE:
			continue
		var card: StoneCard = _board.card_at(row, col)
		if card == null:
			continue
		var transform_to_board := get_global_transform().affine_inverse() * card.get_global_transform()
		var visual: Dictionary = member.duplicate(true)
		visual["card"] = card
		visual["center"] = transform_to_board * (card.size * 0.5)
		visual["square"] = minf(card.size.x, card.size.y)
		members.append(visual)
		positions[int(member["instance_id"])] = visual
	if members.is_empty():
		return {}
	var links_before := _swarm_visual_links(event.get("links_before", []), positions)
	var links_after := _swarm_visual_links(event.get("links_after", []), positions)
	var source_row := int(event.get("source_row", -1))
	var source_col := int(event.get("source_col", -1))
	var source_center: Vector2
	if source_row >= 0 and source_col >= 0 and source_row < GameState.BOARD_SIZE and source_col < GameState.BOARD_SIZE:
		var source_card: StoneCard = _board.card_at(source_row, source_col)
		if source_card != null:
			var source_transform := get_global_transform().affine_inverse() * source_card.get_global_transform()
			source_center = source_transform * (source_card.size * 0.5)
		else:
			var source_slot: Panel = _board.slot_at(source_row, source_col)
			source_center = source_slot.position + source_slot.size * 0.5
	else:
		source_center = members[0]["center"]
	return {"members": members, "links_before": links_before, "links_after": links_after, "source": source_center}

func persistent_links(raw_links: Array) -> Array:
	var positions := {}
	for link in raw_links:
		_add_swarm_link_position(positions, int(link.get("a_instance", -1)),
			int(link.get("a_row", -1)), int(link.get("a_col", -1)))
		_add_swarm_link_position(positions, int(link.get("b_instance", -1)),
			int(link.get("b_row", -1)), int(link.get("b_col", -1)))
	return _swarm_visual_links(raw_links, positions)
