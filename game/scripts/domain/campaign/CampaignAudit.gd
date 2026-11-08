## CampaignAudit.gd
## Métriques de contenu indépendantes du rendu. L'audit ne modifie rien et
## n'ouvre aucune scène : il transforme le graphe chargé en statistiques
## vérifiables par les tests et par la documentation.
class_name CampaignAudit
extends RefCounted

const MIN_GOD_CARDS: int = 3


static func build(graph: CampaignGraph) -> Dictionary:
	if graph == null:
		return {}
	var depth := _depths(graph)
	var order := _topological_order(graph)
	var mode_counts := {}
	var tier_counts := {}
	var series_counts := {}
	var type_counts := {}
	var chapter_counts := {}
	var theme_counts := {}
	var fixed_god_counts := {}
	var generator_god_counts := {}
	var forced_generators: Array[String] = []
	var mirror_fixed_decks: Array[String] = []
	var precision_values: Array[float] = []
	var precision_bands := {}
	var non_quarter := 0
	var optional_minis: Array[String] = []
	var mandatory_minis: Array[String] = []
	var mini_not_ft2: Array[String] = []
	var optional_with_exit: Array[String] = []
	var mandatory_bypassable: Array[String] = []
	var dead_ends: Array[String] = []
	var multi_exit: Array[String] = []
	var three_way: Array[String] = []
	var four_way: Array[String] = []
	var merges: Array[String] = []
	var tutorials: Array[String] = []
	var fixed_decks: Array = []
	var fixed_god_deck_counts := {}
	var fixed_decks_below_three: Array[String] = []
	var exact_duplicates: Array = []
	var near_duplicates: Array = []
	var min_node_distance := INF
	var nodes := graph.nodes()

	for index in range(nodes.size()):
		var node: CampaignNode = nodes[index]
		_bump(mode_counts, node.game_mode())
		_bump(tier_counts, str(node.max_power_tier()))
		_bump(series_counts, node.series_format())
		_bump(type_counts, node.type)
		_bump(chapter_counts, node.chapter)
		if node.theme_god_id != "":
			_bump(theme_counts, node.theme_god_id)
		if node.fixed_god_id() != "":
			_bump(fixed_god_counts, node.fixed_god_id())
		if node.generator_god_id() != "":
			_bump(generator_god_counts, node.generator_god_id())
			forced_generators.append(node.id)
		if not node.mirror_fixed_deck().is_empty():
			mirror_fixed_decks.append(node.id)
		var precision := float(node.ai_profile().get("precision", 0.0))
		precision_values.append(precision)
		if int(round(precision * 100.0)) % 25 != 0:
			non_quarter += 1
		var band := int(floor(float(depth.get(node.id, 0)) / 20.0)) * 20
		var band_key := "%d-%d" % [band, band + 19]
		var band_stats: Dictionary = precision_bands.get(band_key, {
			"count": 0, "min": 1.0, "max": 0.0, "sum": 0.0,
		})
		band_stats["count"] = int(band_stats["count"]) + 1
		band_stats["min"] = minf(float(band_stats["min"]), precision)
		band_stats["max"] = maxf(float(band_stats["max"]), precision)
		band_stats["sum"] = float(band_stats["sum"]) + precision
		precision_bands[band_key] = band_stats

		if node.is_tutorial():
			tutorials.append(node.id)
		if node.is_optional_mini_boss():
			optional_minis.append(node.id)
			if not graph.is_dead_end(node.id):
				optional_with_exit.append(node.id)
		if node.is_mandatory_mini_boss():
			mandatory_minis.append(node.id)
			if graph.is_dead_end(node.id):
				mandatory_bypassable.append(node.id)
			elif graph.reachable_from(graph.start_node_id, node.id).has(graph.final_node_id):
				mandatory_bypassable.append(node.id)
		if node.is_mini_boss() and node.series_format() != SeriesRules.SERIES_FT2:
			mini_not_ft2.append(node.id)
		if graph.is_dead_end(node.id) and node.id != graph.final_node_id:
			dead_ends.append(node.id)
		var outgoing_count := graph.successors(node.id).size()
		if outgoing_count >= 2:
			multi_exit.append(node.id)
		if outgoing_count >= 3:
			three_way.append(node.id)
		if outgoing_count >= 4:
			four_way.append(node.id)
		if graph.predecessors(node.id).size() >= 2:
			merges.append(node.id)

		if not node.fixed_deck().is_empty():
			var sorted_cards: Array = node.fixed_deck()
			sorted_cards.sort()
			var identity := ""
			for card in sorted_cards:
				identity += str(card) + "|"
			fixed_decks.append({
				"node_id": node.id,
				"identity": identity,
				"lineages": _lineages(node.fixed_deck()),
			})
			if node.fixed_god_id() != "":
				var same_god := 0
				for card in node.fixed_deck():
					if StoneLoader.stone_affinity(str(card)) == node.fixed_god_id():
						same_god += 1
				fixed_god_deck_counts[node.id] = same_god
				if same_god < MIN_GOD_CARDS:
					fixed_decks_below_three.append(node.id)

	for index in range(nodes.size()):
		var first_node: CampaignNode = nodes[index]
		for other_index in range(index + 1, nodes.size()):
			var second_node: CampaignNode = nodes[other_index]
			var distance: float = first_node.position.distance_to(second_node.position)
			min_node_distance = minf(min_node_distance, distance)

	var seen_decks := {}
	for entry in fixed_decks:
		if seen_decks.has(entry["identity"]):
			exact_duplicates.append({
				"first": seen_decks[entry["identity"]],
				"second": entry["node_id"],
			})
		else:
			seen_decks[entry["identity"]] = entry["node_id"]
	for first_index in range(fixed_decks.size()):
		for second_index in range(first_index + 1, fixed_decks.size()):
			var first: Dictionary = fixed_decks[first_index]
			var second: Dictionary = fixed_decks[second_index]
			var common := 0
			for lineage in (first["lineages"] as Dictionary).keys():
				if (second["lineages"] as Dictionary).has(lineage):
					common += 1
			if common >= 7:
				near_duplicates.append({
					"first": first["node_id"],
					"second": second["node_id"],
					"common_lineages": common,
				})

	var unreachable: Array[String] = []
	var reachable := graph.reachable_from(graph.start_node_id)
	for node_id in graph.node_ids():
		if not reachable.has(node_id):
			unreachable.append(node_id)
	var duplicate_edges: Array[String] = []
	var seen_pairs := {}
	for edge in graph.edges():
		var pair := "%s>%s" % [edge.from_id, edge.to_id]
		if seen_pairs.has(pair):
			duplicate_edges.append(pair)
		seen_pairs[pair] = true

	var precision_min := 0.0
	var precision_max := 0.0
	if not precision_values.is_empty():
		precision_values.sort()
		precision_min = precision_values[0]
		precision_max = precision_values[precision_values.size() - 1]
	for key in precision_bands:
		var stats: Dictionary = precision_bands[key]
		stats["average"] = float(stats["sum"]) / maxi(1, int(stats["count"]))
		precision_bands[key] = stats

	var min_fixed_god_cards := 0
	if not fixed_god_deck_counts.is_empty():
		var god_counts: Array = fixed_god_deck_counts.values()
		god_counts.sort()
		min_fixed_god_cards = int(god_counts[0])
	var theme_min := 0
	var theme_max := 0
	if not theme_counts.is_empty():
		var theme_values: Array = theme_counts.values()
		theme_values.sort()
		theme_min = int(theme_values[0])
		theme_max = int(theme_values[theme_values.size() - 1])
	var max_depth := 0
	for value in depth.values():
		max_depth = maxi(max_depth, int(value))
	var mode_run := _longest_equal_run(graph, order, "game_mode")
	var theme_run := _longest_equal_run(graph, order, "theme_god_id")

	return {
		"total_nodes": graph.node_count(),
		"total_edges": graph.edge_count(),
		"start_node_id": graph.start_node_id,
		"final_node_id": graph.final_node_id,
		"map_size": graph.map_size,
		"mode_counts": mode_counts,
		"tier_counts": tier_counts,
		"series_counts": series_counts,
		"type_counts": type_counts,
		"chapter_counts": chapter_counts,
		"chapter_count": chapter_counts.size(),
		"theme_counts": theme_counts,
		"fixed_god_counts": fixed_god_counts,
		"generator_god_counts": generator_god_counts,
		"forced_generators": forced_generators,
		"forced_generator_count": forced_generators.size(),
		"mirror_fixed_decks": mirror_fixed_decks,
		"mirror_fixed_deck_count": mirror_fixed_decks.size(),
		"theme_min": theme_min,
		"theme_max": theme_max,
		"tutorials": tutorials,
		"tutorial_count": tutorials.size(),
		"optional_minis": optional_minis,
		"mandatory_minis": mandatory_minis,
		"optional_mini_count": optional_minis.size(),
		"mandatory_mini_count": mandatory_minis.size(),
		"mini_not_ft2": mini_not_ft2,
		"optional_with_exit": optional_with_exit,
		"mandatory_bypassable": mandatory_bypassable,
		"dead_ends": dead_ends,
		"dead_end_count": dead_ends.size(),
		"multi_exit": multi_exit,
		"multi_exit_count": multi_exit.size(),
		"three_way": three_way,
		"three_way_count": three_way.size(),
		"four_way": four_way,
		"four_way_count": four_way.size(),
		"merges": merges,
		"merge_count": merges.size(),
		"min_depth": 0,
		"max_depth": max_depth,
		"max_mode_run": int(mode_run["length"]),
		"max_mode_chain": mode_run["chain"],
		"max_theme_run": int(theme_run["length"]),
		"max_theme_chain": theme_run["chain"],
		"depth_by_node": depth,
		"precision_min": precision_min,
		"precision_max": precision_max,
		"precision_unique": _unique_count(precision_values),
		"precision_non_quarter": non_quarter,
		"precision_bands": precision_bands,
		"fixed_deck_count": fixed_decks.size(),
		"unique_fixed_decks": seen_decks.size(),
		"fixed_god_deck_counts": fixed_god_deck_counts,
		"fixed_god_deck_count": fixed_god_deck_counts.size(),
		"min_fixed_god_cards": min_fixed_god_cards,
		"fixed_decks_below_three": fixed_decks_below_three,
		"exact_duplicate_decks": exact_duplicates,
		"near_duplicate_decks": near_duplicates,
		"unreachable": unreachable,
		"duplicate_edges": duplicate_edges,
		"has_cycle": graph.has_cycle(),
		"min_node_distance": min_node_distance,
	}


static func _depths(graph: CampaignGraph) -> Dictionary:
	var depth := {}
	var indegree := {}
	for node_id in graph.node_ids():
		depth[node_id] = 0
		indegree[node_id] = graph.predecessors(node_id).size()
	var queue: Array[String] = []
	for node_id in graph.node_ids():
		if int(indegree[node_id]) == 0:
			queue.append(node_id)
	var cursor := 0
	while cursor < queue.size():
		var current: String = queue[cursor]
		cursor += 1
		for child in graph.successors(current):
			depth[child] = maxi(int(depth[child]), int(depth[current]) + 1)
			indegree[child] = int(indegree[child]) - 1
			if int(indegree[child]) == 0:
				queue.append(child)
	return depth


static func _topological_order(graph: CampaignGraph) -> Array[String]:
	var indegree := {}
	var queue: Array[String] = []
	for node_id in graph.node_ids():
		indegree[node_id] = graph.predecessors(node_id).size()
		if int(indegree[node_id]) == 0:
			queue.append(node_id)
	var result: Array[String] = []
	var cursor := 0
	while cursor < queue.size():
		var current: String = queue[cursor]
		cursor += 1
		result.append(current)
		for child in graph.successors(current):
			indegree[child] = int(indegree[child]) - 1
			if int(indegree[child]) == 0:
				queue.append(child)
	return result


static func _longest_equal_run(graph: CampaignGraph, order: Array[String], field: String) -> Dictionary:
	var runs := {}
	var previous := {}
	var best_length := 0
	var best_id := ""
	for node_id in order:
		var value := _run_value(graph.node(node_id), field)
		var length := 1
		var predecessor := ""
		for parent_id in graph.predecessors(node_id):
			var candidate := 1
			if _run_value(graph.node(parent_id), field) == value:
				candidate = int(runs.get(parent_id, 1)) + 1
			if candidate > length:
				length = candidate
				predecessor = parent_id
		runs[node_id] = length
		previous[node_id] = predecessor
		if length > best_length:
			best_length = length
			best_id = node_id
	var chain: Array[String] = []
	var cursor := best_id
	while cursor != "":
		chain.append(cursor)
		cursor = str(previous.get(cursor, ""))
	chain.reverse()
	return {"length": best_length, "chain": chain}


static func _run_value(node: CampaignNode, field: String) -> String:
	if field == "theme_god_id":
		return node.theme_god_id
	return node.game_mode()


static func _lineages(deck: Array) -> Dictionary:
	var result := {}
	for raw_id in deck:
		var card_id := str(raw_id)
		var lineage := StoneLoader.stone_lineage(card_id)
		if lineage == "":
			lineage = card_id
		result[lineage] = true
	return result


static func _unique_count(values: Array) -> int:
	var seen := {}
	for value in values:
		seen[value] = true
	return seen.size()


static func _bump(counts: Dictionary, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1
