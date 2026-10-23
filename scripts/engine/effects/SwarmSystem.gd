## Aura continue : groupes alliés, bonus déterministes et liens avant/après.
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const SIDES = StoneSide.ALL
const Board := preload("res://scripts/engine/combat/CombatBoard.gd")
const SWARM_CAP := 2

static func recalculate(state: GameState) -> void:
	for cell in state.board:
		var stone := Board.stone_at(cell)
		if stone != null:
			for side in SIDES:
				stone.swarm_blades[side] = 0
	var visited := {}
	for index in range(state.board.size()):
		if visited.has(index) or not _is_swarm_cell(state.board[index]):
			continue
		var owner: int = state.board[index]["owner"]
		var component: Array[int] = []
		var pending: Array[int] = [index]
		visited[index] = true
		while not pending.is_empty():
			var current: int = pending.pop_back()
			component.append(current)
			var current_row := current / GameState.BOARD_SIZE
			var current_col := current % GameState.BOARD_SIZE
			for adjacent in GameState.get_adjacent_positions(current_row, current_col):
				var next_index := GameState.cell_index(adjacent["row"], adjacent["col"])
				if visited.has(next_index):
					continue
				if state.board[next_index]["owner"] == owner and _is_swarm_cell(state.board[next_index]):
					visited[next_index] = true
					pending.append(next_index)
		var bonus_count := mini(SWARM_CAP, component.size() - 1)
		for member_index in component:
			var member := Board.stone_at(state.board[member_index])
			var contributor := 0
			for other_index in component:
				if other_index == member_index or contributor >= bonus_count:
					continue
				var other := Board.stone_at(state.board[other_index])
				var pair_key := "%d:%d" % [mini(member.instance_id, other.instance_id), maxi(member.instance_id, other.instance_id)]
				var start := absi(hash(pair_key + ":" + str(member.instance_id))) % SIDES.size()
				for offset in range(SIDES.size()):
					var side := SIDES[(start + offset) % SIDES.size()]
					if member.free_marker_slots(side) > 0:
						member.swarm_blades[side] = int(member.swarm_blades[side]) + 1
						contributor += 1
						break


## Capture les seules données nécessaires à la présentation de l'Essaim.
## L'instantané reste interne au résolveur : les vues reçoivent ensuite un
## compte rendu avant/après et ne recalculent jamais les groupes elles-mêmes.


static func snapshot(state: GameState) -> Dictionary:
	var members := {}
	var links := {}
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		if not _is_swarm_cell(cell):
			continue
		var stone := Board.stone_at(cell)
		var instance_id := int(stone.instance_id)
		members[instance_id] = {
			"instance_id": instance_id,
			"row": index / GameState.BOARD_SIZE,
			"col": index % GameState.BOARD_SIZE,
			"owner": int(cell["owner"]),
			"blades": stone.swarm_blades.duplicate(true)
		}
	for instance_id in members:
		var member: Dictionary = members[instance_id]
		for offset in [Vector2i(0, 1), Vector2i(1, 0)]:
			var next_row: int = int(member["row"]) + offset.x
			var next_col: int = int(member["col"]) + offset.y
			if next_row >= GameState.BOARD_SIZE or next_col >= GameState.BOARD_SIZE:
				continue
			var other_cell := state.get_cell(next_row, next_col)
			if int(other_cell["owner"]) != int(member["owner"]) or not _is_swarm_cell(other_cell):
				continue
			var other := Board.stone_at(other_cell)
			var other_id := int(other.instance_id)
			var key := _swarm_link_key(int(instance_id), other_id)
			links[key] = {
				"key": key,
				"a_instance": int(instance_id), "b_instance": other_id,
				"a_row": int(member["row"]), "a_col": int(member["col"]),
				"b_row": next_row, "b_col": next_col
			}
	return {"members": members, "links": links}


## Description publique et immuable du réseau courant, destinée au
## coordinateur d'affichage. Elle permet de reconstruire les lianes après un
## rafraîchissement sans dupliquer les règles d'adjacence dans la vue.


static func links(state: GameState) -> Array:
	var links: Dictionary = snapshot(state)["links"]
	var keys: Array = links.keys()
	keys.sort()
	var result: Array = []
	for key in keys:
		result.append(links[key].duplicate(true))
	return result


## Décrit uniquement le réseau touché. Ajouter une quatrième pierre à un
## groupe plafonné anime encore sa nouvelle liaison, sans faire pulser les
## éventuels groupes Essaim indépendants du plateau.


static func transitions(before: Dictionary, after: Dictionary,
	source_row: int, source_col: int) -> Array:
	var before_members: Dictionary = before.get("members", {})
	var after_members: Dictionary = after.get("members", {})
	var before_links: Dictionary = before.get("links", {})
	var after_links: Dictionary = after.get("links", {})
	var affected := {}
	for instance_id in before_members:
		var old_member: Dictionary = before_members[instance_id]
		var new_member: Dictionary = after_members.get(instance_id, {})
		if not new_member.is_empty() and old_member.get("blades", {}) != new_member.get("blades", {}):
			affected[instance_id] = true
	for instance_id in after_members:
		if before_members.has(instance_id):
			continue
		if after_members[instance_id].get("blades", {}) != _empty_side_map():
			affected[instance_id] = true
	for key in before_links:
		if not after_links.has(key):
			var removed: Dictionary = before_links[key]
			affected[removed["a_instance"]] = true
			affected[removed["b_instance"]] = true
	for key in after_links:
		if not before_links.has(key):
			var added: Dictionary = after_links[key]
			affected[added["a_instance"]] = true
			affected[added["b_instance"]] = true
	if affected.is_empty():
		return []

	# Étend la sélection aux composantes avant et après : les liaisons stables
	# transportent elles aussi l'impulsion jusqu'aux membres renforcés.
	var expanded := true
	while expanded:
		expanded = false
		for links in [before_links, after_links]:
			for key in links:
				var link: Dictionary = links[key]
				var a = link["a_instance"]
				var b = link["b_instance"]
				if affected.has(a) and not affected.has(b):
					affected[b] = true
					expanded = true
				elif affected.has(b) and not affected.has(a):
					affected[a] = true
					expanded = true

	var member_events: Array = []
	var member_ids: Array = affected.keys()
	member_ids.sort()
	for instance_id in member_ids:
		var old_member: Dictionary = before_members.get(instance_id, {})
		var new_member: Dictionary = after_members.get(instance_id, {})
		var reference: Dictionary = new_member if not new_member.is_empty() else old_member
		member_events.append({
			"instance_id": instance_id,
			"row": int(reference["row"]), "col": int(reference["col"]),
			"before": old_member.get("blades", _empty_side_map()).duplicate(true),
			"after": new_member.get("blades", _empty_side_map()).duplicate(true)
		})
	var visible_before: Array = []
	var visible_after: Array = []
	var before_keys: Array = before_links.keys()
	var after_keys: Array = after_links.keys()
	before_keys.sort()
	after_keys.sort()
	for key in before_keys:
		var link: Dictionary = before_links[key]
		if affected.has(link["a_instance"]) and affected.has(link["b_instance"]):
			visible_before.append(link.duplicate(true))
	for key in after_keys:
		var link: Dictionary = after_links[key]
		if affected.has(link["a_instance"]) and affected.has(link["b_instance"]):
			visible_after.append(link.duplicate(true))
	return [CombatEvents.swarm_change(source_row, source_col, member_events, visible_before, visible_after)]


static func _swarm_link_key(first: int, second: int) -> String:
	return "%d:%d" % [mini(first, second), maxi(first, second)]


static func _empty_side_map() -> Dictionary:
	return {"top": 0, "bottom": 0, "left": 0, "right": 0}


static func _is_swarm_cell(cell: Dictionary) -> bool:
	var stone := Board.stone_at(cell)
	if stone == null or cell["owner"] == GameState.PLAYER_NONE:
		return false
	return StoneLoader.get_stone(stone.stone_id).get("effects", []).has("swarm")
