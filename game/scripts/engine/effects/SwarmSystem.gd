## Aura continue : groupes alliés, bonus déterministes et liens avant/après.
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const SIDES = StoneSide.ALL
const Board := preload("res://scripts/engine/combat/CombatBoard.gd")
const Effects := preload("res://scripts/domain/StoneEffects.gd")

## Seules les pierres Essaim d'un camp dont le dieu est celui de la carte
## reçoivent des lames d'aura. Une pierre Essaim capturée par un autre dieu
## perd donc son aura. Sans pierre Essaim, il n'y a rien à recalculer.
static func recalculate(state: GameState) -> void:
	var members := _reset_and_active_members(state)
	for component in _connected_components(state, members):
		_apply_component_bonus(state, component)


## Retire les anciennes auras de toutes les pierres Essaim et renvoie uniquement
## celles dont le pouvoir est actif dans leur camp actuel.
static func _reset_and_active_members(state: GameState) -> Dictionary:
	var members := {}
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		var stone := Board.stone_at(cell)
		if stone == null or not StoneLoader.has_effect(stone.stone_id, Effects.SWARM):
			continue
		for side in SIDES:
			stone.swarm_blades[side] = 0
		if Board.has_active_power(state, cell, Effects.SWARM):
			members[index] = true
	return members


static func _connected_components(state: GameState, members: Dictionary) -> Array:
	var components: Array = []
	var visited := {}
	for index in members:
		if visited.has(index):
			continue
		var owner: int = state.board[index]["owner"]
		var component: Array[int] = []
		var pending: Array[int] = [index]
		visited[index] = true
		while not pending.is_empty():
			var current: int = pending.pop_back()
			component.append(current)
			var row := current / GameState.BOARD_SIZE
			var col := current % GameState.BOARD_SIZE
			for adjacent in GameState.get_adjacent_positions(row, col):
				var next_index := GameState.cell_index(adjacent["row"], adjacent["col"])
				if not visited.has(next_index) and members.has(next_index) \
						and state.board[next_index]["owner"] == owner:
					visited[next_index] = true
					pending.append(next_index)
		components.append(component)
	return components


static func _apply_component_bonus(state: GameState, component: Array) -> void:
	var bonus_count := mini(Effects.SWARM_CAP,
		(component.size() - 1) * Effects.BLADES_PER_ALLY)
	for member_index in component:
		var member := Board.stone_at(state.board[member_index])
		var contributor := 0
		for other_index in component:
			if other_index == member_index or contributor >= bonus_count:
				continue
			var other := Board.stone_at(state.board[other_index])
			var pair_key := "%d:%d" % [mini(member.instance_id, other.instance_id),
				maxi(member.instance_id, other.instance_id)]
			var start := absi(hash(pair_key + ":" + str(member.instance_id))) % SIDES.size()
			contributor = _add_ally_blades(member, start, contributor, bonus_count)


static func _add_ally_blades(member: BattleStoneModel, start: int, contributor: int,
		bonus_count: int) -> int:
	# Chaque lame d'un même allié part de la face suivante : l'aura se répartit.
	for blade in range(Effects.BLADES_PER_ALLY):
		if contributor >= bonus_count:
			break
		for offset in range(SIDES.size()):
			var side := SIDES[(start + blade + offset) % SIDES.size()]
			if member.free_marker_slots(side) > 0:
				member.swarm_blades[side] = int(member.swarm_blades[side]) + 1
				contributor += 1
				break
	return contributor


## Capture les seules données nécessaires à la présentation de l'Essaim.
## L'instantané reste interne au résolveur : les vues reçoivent ensuite un
## compte rendu avant/après et ne recalculent jamais les groupes elles-mêmes.


static func snapshot(state: GameState) -> Dictionary:
	var members := {}
	var links := {}
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		if not Board.has_active_power(state, cell, Effects.SWARM):
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
			if int(other_cell["owner"]) != int(member["owner"]) or not Board.has_active_power(state, other_cell, Effects.SWARM):
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
	var affected := _changed_members(before_members, after_members,
		before_links, after_links)
	if affected.is_empty():
		return []
	_expand_affected_component(affected, before_links, after_links)
	return [CombatEvents.swarm_change(source_row, source_col,
		_member_transitions(affected, before_members, after_members),
		_visible_links(affected, before_links),
		_visible_links(affected, after_links))]


static func _changed_members(before_members: Dictionary, after_members: Dictionary,
		before_links: Dictionary, after_links: Dictionary) -> Dictionary:
	var affected := {}
	for instance_id in before_members:
		var old_member: Dictionary = before_members[instance_id]
		var new_member: Dictionary = after_members.get(instance_id, {})
		if not new_member.is_empty() \
				and old_member.get("blades", {}) != new_member.get("blades", {}):
			affected[instance_id] = true
	for instance_id in after_members:
		if not before_members.has(instance_id) \
				and after_members[instance_id].get("blades", {}) != _empty_side_map():
			affected[instance_id] = true
	for key in before_links:
		if not after_links.has(key):
			_mark_link_members(affected, before_links[key])
	for key in after_links:
		if not before_links.has(key):
			_mark_link_members(affected, after_links[key])
	return affected


static func _mark_link_members(affected: Dictionary, link: Dictionary) -> void:
	affected[link["a_instance"]] = true
	affected[link["b_instance"]] = true


## Les liaisons stables transportent l'impulsion à toute la composante touchée.
static func _expand_affected_component(affected: Dictionary, before_links: Dictionary,
		after_links: Dictionary) -> void:
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


static func _member_transitions(affected: Dictionary, before_members: Dictionary,
		after_members: Dictionary) -> Array:
	var result: Array = []
	var member_ids: Array = affected.keys()
	member_ids.sort()
	for instance_id in member_ids:
		var old_member: Dictionary = before_members.get(instance_id, {})
		var new_member: Dictionary = after_members.get(instance_id, {})
		var reference: Dictionary = new_member if not new_member.is_empty() else old_member
		result.append({
			"instance_id": instance_id,
			"row": int(reference["row"]), "col": int(reference["col"]),
			"before": old_member.get("blades", _empty_side_map()).duplicate(true),
			"after": new_member.get("blades", _empty_side_map()).duplicate(true)
		})
	return result


static func _visible_links(affected: Dictionary, links: Dictionary) -> Array:
	var result: Array = []
	var keys: Array = links.keys()
	keys.sort()
	for key in keys:
		var link: Dictionary = links[key]
		if affected.has(link["a_instance"]) and affected.has(link["b_instance"]):
			result.append(link.duplicate(true))
	return result


static func _swarm_link_key(first: int, second: int) -> String:
	return "%d:%d" % [mini(first, second), maxi(first, second)]


static func _empty_side_map() -> Dictionary:
	return {"top": 0, "bottom": 0, "left": 0, "right": 0}
